#Requires -Version 7.4
<#
.SYNOPSIS
  Commits the given data paths and pushes them, if they changed. Used by the ingest and refine
  workflows. Run from the repo root.
.PARAMETER Path
  The files or folders to commit, relative to the repo root. Nothing else is staged, so each
  workflow commits only the files it owns.
.PARAMETER Message
  The commit subject. The Boise date is appended.
.PARAMETER SkipDeploy
  Add [skip ci], so Cloudflare Workers Builds doesn't deploy the commit. Ingest uses it, because
  the site doesn't read the raw file.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string[]]$Path,
  [Parameter(Mandatory)][string]$Message,
  [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib' 'Schema.ps1')

function Invoke-Git {
  git @args
  if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed" }
}

Invoke-Git add --all -- @Path

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Write-Host "No changes to commit in $($Path -join ', ')"
  exit 0
}

$date = (ConvertTo-BoiseTime ([DateTimeOffset]::UtcNow)).Substring(0, 10)
# Without -SkipDeploy there is no [skip ci], because Cloudflare skips commits that carry it and this
# commit is what puts the new data on the site. The test workflow doesn't run either way, because
# GitHub never starts workflows from a push made with the workflow's own GITHUB_TOKEN.
$subject = "$Message $date$($SkipDeploy ? ' [skip ci]' : '')"
$bot = @('-c', 'user.name=WeekendBoise bot', '-c', 'user.email=weekendboise-bot@noreply.invalid')
Invoke-Git @bot commit -m $subject

# Push to the branch the run was triggered on. GitHub Actions sets GITHUB_REF.
$branch = if ("$env:GITHUB_REF" -like 'refs/heads/*') { $env:GITHUB_REF.Substring(11) } else { git rev-parse --abbrev-ref HEAD }

# Refine takes 15 minutes or more, so someone may push code to the branch while it runs, and
# the push is then rejected as out of date. Each workflow commits only its own data files, so
# replay this commit on top of the new branch head and push again. If someone changed the same
# files, stop rather than overwrite their change.
for ($attempt = 1; ; $attempt++) {
  git push origin "HEAD:refs/heads/$branch"
  if ($LASTEXITCODE -eq 0) { break }
  if ($attempt -ge 3) { throw "git push failed $attempt times; giving up" }
  Write-Host "Push rejected, so replaying the commit on top of origin/$branch (attempt $attempt)"
  Invoke-Git fetch origin $branch
  git @bot rebase FETCH_HEAD
  if ($LASTEXITCODE -ne 0) {
    git rebase --abort
    throw "Someone changed the same files ($($Path -join ', ')) on $branch during this run, so this run's data was not pushed. Run the workflow again."
  }
}
