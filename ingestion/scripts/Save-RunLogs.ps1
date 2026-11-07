#Requires -Version 7.4
<#
.SYNOPSIS
  Saves the GitHub Actions log of each finished job in this workflow run, for the report email.
.DESCRIPTION
  GitHub serves a job's log only once that job has finished, so the workflows email their report
  from a separate report job that runs after the main one. This script runs there: it lists the
  run's jobs, skips the report job itself, and saves each other job's log as <job name>.log in
  OutDir. Send-Report.ps1 then zips that folder into the email.

  It never fails: a log it can't read gets a warning, so the email still goes out without it.
  GitHub's logs carry terminal color codes, which are stripped so the files read as plain text.
  Needs GH_TOKEN and the actions: read permission. It calls the REST API directly rather than
  gh api, which refuses to print text that contains terminal escape sequences.
.PARAMETER RunId
  github.run_id. Defaults to the RUN_ID environment variable.
.PARAMETER Repository
  owner/name. Defaults to the GITHUB_REPOSITORY environment variable.
.PARAMETER ExcludeJob
  Jobs not to save: the report job, which is still running.
.PARAMETER Fetch
  Returns the response text for a GitHub API endpoint, or throws. Defaults to gh api. Used by tests.
#>
[CmdletBinding()]
param(
  [string]$RunId = $env:RUN_ID,
  [string]$Repository = $env:GITHUB_REPOSITORY,
  [string]$OutDir = './logs',
  [string[]]$ExcludeJob = @('report'),
  [scriptblock]$Fetch = {
    # The logs endpoint redirects to a storage URL; PowerShell follows it and drops the token there.
    param([string]$Endpoint)
    $headers = @{ Accept = 'application/vnd.github+json'; 'X-GitHub-Api-Version' = '2022-11-28' }
    if ($env:GH_TOKEN) { $headers.Authorization = "Bearer $env:GH_TOKEN" }
    $response = Invoke-WebRequest -Uri "https://api.github.com/$Endpoint" -TimeoutSec 60 -Headers $headers
    if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { "$($response.Content)" }
  }
)

$ErrorActionPreference = 'Stop'
$null = New-Item -ItemType Directory -Force -Path $OutDir

$jobs = try {
  @((& $Fetch "repos/$Repository/actions/runs/$RunId/jobs" | ConvertFrom-Json).jobs)
} catch {
  Write-Warning "Can't list the jobs of run $RunId, so no logs are attached: $_"
  @()
}

foreach ($job in $jobs | Where-Object { $_.name -notin $ExcludeJob }) {
  # Job names become file names, so keep them plain.
  $name = ("$($job.name)" -replace '[^\w.-]+', '-').Trim('-')
  try {
    $text = "$(& $Fetch "repos/$Repository/actions/jobs/$($job.id)/logs")" -replace "$([char]27)\[[0-9;]*[A-Za-z]", ''
    [IO.File]::WriteAllText((Join-Path $OutDir "$name.log"), $text)
    Write-Host "Saved the log of job $($job.name)"
  } catch {
    Write-Warning "Can't read the log of job $($job.name): $_"
  }
}

# A failed request can leave a failing exit code behind, and the workflow step would report it.
exit 0
