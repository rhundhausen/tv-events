#Requires -Version 7.4
<#
.SYNOPSIS
  Decides whether a scheduled workflow run is the one for a given hour in Boise.
.DESCRIPTION
  Cron is UTC and Boise is UTC-6 in summer and UTC-7 in winter, so a workflow schedules both UTC
  hours and calls this to skip the one that isn't the target hour in Boise that day. A manual run
  (any event other than schedule) always runs.

  Scheduled runs can start late, so it checks the scheduled hour, not the clock. For a scheduled
  run, At is the scheduled time as yyyy-MM-ddTHH:mm:ssZ. When GITHUB_OUTPUT is set, it also
  appends at= (scheduled runs only) and run=true or run=false for the job's outputs.

  Returns an object with Run (bool) and At (string, empty for a manual run).
.PARAMETER Hour
  The target hour in Boise, 0 to 23. Ingest uses 0 (midnight), refine uses 1.
.PARAMETER EventName
  github.event_name. Defaults to the EVENT environment variable.
.PARAMETER Schedule
  github.event.schedule, the cron line that fired. Defaults to the SCHEDULE environment variable.
.PARAMETER Today
  The UTC date the run is for. Defaults to today. Used by tests.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateRange(0, 23)][int]$Hour,
  [string]$EventName = $env:EVENT,
  [string]$Schedule = $env:SCHEDULE,
  [DateTime]$Today = [DateTime]::UtcNow.Date
)

$ErrorActionPreference = 'Stop'

$run = $true
$at = ''
if ($EventName -eq 'schedule') {
  $fields = "$Schedule".Trim() -split '\s+'
  $utcHour = 0
  if ($fields.Count -ne 5 -or -not [int]::TryParse($fields[1], [ref]$utcHour)) {
    throw "Can't read the hour from the cron line '$Schedule'"
  }
  $scheduled = [DateTime]::SpecifyKind($Today.Date.AddHours($utcHour), 'Utc')
  $boise = [TimeZoneInfo]::ConvertTimeFromUtc($scheduled, [TimeZoneInfo]::FindSystemTimeZoneById('America/Boise'))
  $run = $boise.Hour -eq $Hour
  $at = $scheduled.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
  Write-Host "Scheduled '$Schedule' is $($boise.ToString('HH:mm')) in Boise, target hour $Hour; run: $($run.ToString().ToLowerInvariant())"
}

if ($env:GITHUB_OUTPUT) {
  if ($at) { "at=$at" | Add-Content -LiteralPath $env:GITHUB_OUTPUT }
  "run=$($run.ToString().ToLowerInvariant())" | Add-Content -LiteralPath $env:GITHUB_OUTPUT
}

[pscustomobject]@{ Run = $run; At = $at }
