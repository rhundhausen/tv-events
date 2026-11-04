#Requires -Version 7.4
<#
.SYNOPSIS
  Fetches every running source and writes data/events.json and data/archive/YYYY-MM.json.
.DESCRIPTION
  Runs the entries in sources.json whose status is running. One broken source logs a warning and
  is skipped. Its stored events are kept until a later run refreshes them. The run exits non-zero
  only if zero sources succeed. Each run writes run.json to OutDir: per source, the count, status,
  error, and warnings.
.PARAMETER Source
  Run only this source, by name. Any configured entry can be run this way, whatever its status.
  Other sources' stored events are left in place.
.PARAMETER OutDir
  Where per-source raw output goes, as <name>.json, plus run.json.
.PARAMETER NoWrite
  Fetch and report, but don't touch data/.
.PARAMETER Days
  Drop events starting more than this many days out.
#>
[CmdletBinding()]
param(
  [string]$Source,
  [string]$OutDir = './out',
  [switch]$NoWrite,
  [int]$Days = 180
)

$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..'))
. (Join-Path $PSScriptRoot 'lib' 'Store.ps1')

$sourcesPath = Join-Path $root 'sources.json'
$dataPath = Join-Path $repoRoot 'data' 'events.json'
$archiveDir = Join-Path $repoRoot 'data' 'archive'
$outPath = [IO.Path]::GetFullPath($OutDir, $PWD.Path)

$global:LASTEXITCODE = 0
& (Join-Path $PSScriptRoot 'Test-Sources.ps1') -Path $sourcesPath
if ($LASTEXITCODE -ne 0) { exit 1 }

$allSources = @((Get-Content -LiteralPath $sourcesPath -Raw | ConvertFrom-TvJson).sources)
$running = @($allSources | Where-Object { $_.status -eq 'running' })
$selected = if ($Source) {
  @($allSources | Where-Object { $_.name -and $_.name -eq $Source })
} else {
  $running
}
foreach ($entry in $selected | Where-Object { $_.status -ne 'running' }) {
  Write-Warning "$($entry.name): status is $($entry.status ? $entry.status : 'idea'), running it because it was asked for by name"
}
if ($selected.Count -eq 0) {
  Write-Host "No source to run$($Source ? " named '$Source'" : '')"
  exit 1
}

$priorities = @{}
foreach ($entry in $allSources) {
  if ($null -ne $entry.priority) { $priorities[$entry.name] = $entry.priority }
}

$now = [DateTimeOffset]::UtcNow
$fetchedAt = $now.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
$fetched = [System.Collections.Generic.List[object]]::new()
$results = [System.Collections.Generic.List[object]]::new()

foreach ($entry in $selected) {
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $status = 'ok'
  $count = 0
  $errorText = $null
  $adapterWarnings = $null
  try {
    $events = @(& (Join-Path $PSScriptRoot 'adapters' "$($entry.adapter).ps1") -Source $entry -FetchedAt $fetchedAt -WarningVariable adapterWarnings)
    $count = $events.Count
    Write-TvEventFile (Join-Path $outPath "$($entry.name).json") $events
    $fetched.AddRange($events)
  } catch {
    $status = 'failed'
    $errorText = Hide-TvSecret "$_"
    Write-Warning "$($entry.name): $errorText"
  }
  $results.Add([pscustomobject]@{
      Source   = $entry.name
      Fetched  = $count
      Deduped  = 0
      Status   = $status
      Duration = '{0:n1}s' -f $timer.Elapsed.TotalSeconds
      Warnings = @($adapterWarnings | ForEach-Object { Hide-TvSecret "$_" })
      Error    = $errorText
    })
}

function Write-RunLog {
  param([object[]]$Upcoming = @(), [int]$Past = 0)
  $countBy = {
    param([string]$Property)
    $counts = [ordered]@{}
    $Upcoming | Group-Object $Property | Sort-Object Count -Descending | ForEach-Object { $counts[$_.Name] = $_.Count }
    $counts
  }
  $log = [ordered]@{
    fetchedAt  = $fetchedAt
    noWrite    = [bool]$NoWrite
    upcoming   = $Upcoming.Count
    past       = $Past
    categories = & $countBy 'category'
    sizes      = & $countBy 'size'
    sources    = @($results | ForEach-Object {
        [ordered]@{
          name     = $_.Source
          status   = $_.Status
          fetched  = $_.Fetched
          deduped  = $_.Deduped
          duration = $_.Duration
          error    = $_.Error
          warnings = @($_.Warnings)
        }
      })
  }
  $null = New-Item -ItemType Directory -Force -Path $outPath
  [IO.File]::WriteAllText((Join-Path $outPath 'run.json'), (($log | ConvertTo-Json -Depth 5) -replace "`r`n", "`n") + "`n")
}

$display = @('Source', 'Fetched', 'Deduped', 'Status', 'Duration', @{ Name = 'Warnings'; Expression = { @($_.Warnings).Count } })
$refreshed = @($results | Where-Object Status -eq 'ok' | ForEach-Object Source)
if ($refreshed.Count -eq 0) {
  Write-RunLog
  $results | Format-Table $display | Out-String | Write-Host
  Write-Host 'No source succeeded'
  exit 1
}

$existing = @(Read-TvEventFile $dataPath)
$carried = @(Get-CarriedTvEvents $existing -Refreshed $refreshed -Enabled @($running | ForEach-Object name) -Now $now)
$merged = @(Merge-TvEvents (@($fetched) + $carried) -Priorities $priorities)
Restore-TvFetchedAt $merged $existing

# Each event was valid when built, so a failure here is a merge bug. Never store one.
$merged = @($merged | Where-Object {
    $valid = Test-TvEvent $_
    if (-not $valid) { Write-Warning "Dropping invalid event after merge: $($_.id) '$($_.title)'" }
    $valid
  })

$horizon = $now.AddDays($Days)
$past = @($merged | Where-Object { Test-TvEventPast $_ $now })
$upcoming = @($merged | Where-Object { -not (Test-TvEventPast $_ $now) -and (Get-TvEventInstant $_.start) -le $horizon })
$upcoming = @(Sort-TvEvents $upcoming)

foreach ($result in $results) {
  $result.Deduped = @($upcoming | Where-Object { $result.Source -in @($_.sources.name) }).Count
}

if (-not $NoWrite) {
  Add-TvArchive $archiveDir $past -Priorities $priorities
  Write-TvEventFile $dataPath $upcoming
}

Write-RunLog -Upcoming $upcoming -Past $past.Count
$results | Format-Table $display | Out-String | Write-Host
$failed = @($results | Where-Object Status -ne 'ok').Count
Write-Host "$($results.Count - $failed) of $($results.Count) sources succeeded, $($upcoming.Count) upcoming, $($past.Count) past$($NoWrite ? ' (not written)' : '')"
exit 0
