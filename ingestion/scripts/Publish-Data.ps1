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
Invoke-Git -c 'user.name=WeekendBoise bot' -c 'user.email=weekendboise-bot@noreply.invalid' commit -m $subject

# Push to the branch the run was triggered on. GitHub Actions sets GITHUB_REF.
$branchRef = $env:GITHUB_REF
if ($branchRef -like 'refs/heads/*') {
  Invoke-Git push origin "HEAD:$branchRef"
}
else {
  Invoke-Git push
}
