#Requires -Version 7.4
<#
.SYNOPSIS
  Commits data/ and pushes it, if it changed. Used by the ingest workflow. Run from the repo root.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib' 'Schema.ps1')

function Invoke-Git {
  git @args
  if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed" }
}

Invoke-Git add --all data

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Write-Host 'No data changes to commit'
  exit 0
}

$date = (ConvertTo-BoiseTime ([DateTimeOffset]::UtcNow)).Substring(0, 10)
# No [skip ci]: Cloudflare Workers Builds skips commits that carry it, and this commit is what puts
# the new data on the site. The test workflow doesn't run anyway, because GitHub never starts
# workflows from a push made with the workflow's own GITHUB_TOKEN.
Invoke-Git -c 'user.name=WeekendBoise bot' -c 'user.email=weekendboise-bot@noreply.invalid' commit -m "data: nightly ingest $date"

# Push to the branch the run was triggered on. GitHub Actions sets GITHUB_REF.
$branchRef = $env:GITHUB_REF
if ($branchRef -like 'refs/heads/*') {
  Invoke-Git push origin "HEAD:$branchRef"
}
else {
  Invoke-Git push
}
