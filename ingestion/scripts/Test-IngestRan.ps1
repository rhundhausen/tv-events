#Requires -Version 7.4
<#
.SYNOPSIS
  Decides whether refine should run after an ingest run finished.
.DESCRIPTION
  Refine starts on workflow_run each time an ingest run completes. Ingest schedules two cron lines
  for daylight saving and skips the one that isn't midnight in Boise, and that run still completes,
  so refine looks at the ingest run's jobs: it runs if the job named ingest started, whatever its
  outcome (success, failure, cancelled, timed out), and skips it if that job was skipped or never
  reached. A failed ingest still gets a refine, so past events move to the archive and links are
  checked against the last good raw file. A manual run (any event other than workflow_run) always
  runs.

  When GITHUB_OUTPUT is set, it appends run=true or run=false for the job's outputs. Returns an
  object with Run (bool).
.PARAMETER EventName
  github.event_name. Defaults to the EVENT environment variable.
.PARAMETER RunId
  github.event.workflow_run.id, the ingest run. Defaults to the INGEST_RUN_ID environment variable.
.PARAMETER Repository
  owner/name. Defaults to the GITHUB_REPOSITORY environment variable.
.PARAMETER Jobs
  The ingest run's jobs, each with name and conclusion. When left out, they are read with
  gh api, which needs GH_TOKEN and the actions: read permission. Used by tests.
#>
[CmdletBinding()]
param(
  [string]$EventName = $env:EVENT,
  [string]$RunId = $env:INGEST_RUN_ID,
  [string]$Repository = $env:GITHUB_REPOSITORY,
  [object[]]$Jobs
)

$ErrorActionPreference = 'Stop'

$run = $true
if ($EventName -eq 'workflow_run') {
  if (-not $PSBoundParameters.ContainsKey('Jobs')) {
    if (-not $RunId) { throw 'No ingest run id to look up. Set INGEST_RUN_ID to github.event.workflow_run.id.' }
    $json = gh api "repos/$Repository/actions/runs/$RunId/jobs"
    if ($LASTEXITCODE -ne 0) { throw "Can't read the jobs of ingest run $RunId" }
    $Jobs = @(($json | Out-String | ConvertFrom-Json).jobs)
  }
  $ingest = @($Jobs | Where-Object name -eq 'ingest') | Select-Object -First 1
  $conclusion = if ($ingest) { "$($ingest.conclusion)" } else { 'missing' }
  $run = $ingest -and $conclusion -ne 'skipped'
  Write-Host "Ingest run $RunId, ingest job: $conclusion; refine: $($run.ToString().ToLowerInvariant())"
}

if ($env:GITHUB_OUTPUT) {
  "run=$($run.ToString().ToLowerInvariant())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
}

[pscustomobject]@{ Run = [bool]$run }
