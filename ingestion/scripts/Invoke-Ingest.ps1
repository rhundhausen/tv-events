#Requires -Version 7.4
<#
.SYNOPSIS
  Fetches every running source and writes data/events.json and data/archive/YYYY-MM.json.
.DESCRIPTION
  Runs the entries in sources.json whose status is running. One broken source logs a warning and
  is skipped. Its stored events are kept until a later run refreshes them. The run exits non-zero
  only if zero sources succeed. Each run writes run.json to OutDir: per source, the count, status,
  error, and warnings. Events get a rough cost tier guess (Set-TvCostGuess) when no source gave a
  price. Events any source reports as canceled are dropped, and events stored as
  city Other get a city when their own text says where they are (Resolve-TvOtherCity). A run that fetched
  writes data/meta.json with the time of the last ingest.
.PARAMETER Source
  Run only this source, by name. Any configured entry can be run this way, whatever its status.
  Other sources' stored events are left in place.
.PARAMETER OutDir
  Where per-source raw output goes, as <name>.json, plus run.json.
.PARAMETER NoWrite
  Fetch and report, but don't touch data/.
.PARAMETER Days
  Drop events starting more than this many days out.
.PARAMETER CleanupOnly
  Don't fetch anything. Re-run dedupe and cleanup over the stored events.json and every archive
  month, so a change to the merge rules applies without a network request. Events from sources
  that are no longer running are dropped, as on a normal run. data/meta.json is left alone.
.PARAMETER AsOf
  The UTC time to record as the last ingest in data/meta.json, as yyyy-MM-ddTHH:mm:ssZ. The nightly
  workflow passes the scheduled midnight, because GitHub often starts scheduled runs late. Defaults
  to the time the run started. Event fetchedAt times always use the real time.
#>
[CmdletBinding()]
param(
  [string]$Source,
  [string]$OutDir = './out',
  [switch]$NoWrite,
  [int]$Days = 180,
  [switch]$CleanupOnly,
  [ValidatePattern('^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$')][string]$AsOf
)

$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' '..'))
. (Join-Path $PSScriptRoot 'lib' 'Store.ps1')
. (Join-Path $PSScriptRoot 'lib' 'Cities.ps1')

$sourcesPath = Join-Path $root 'sources.json'
$dataPath = Join-Path $repoRoot 'data' 'events.json'
$metaPath = Join-Path $repoRoot 'data' 'meta.json'
$archiveDir = Join-Path $repoRoot 'data' 'archive'
$outPath = [IO.Path]::GetFullPath($OutDir, $PWD.Path)

$global:LASTEXITCODE = 0
& (Join-Path $PSScriptRoot 'Test-Sources.ps1') -Path $sourcesPath
if ($LASTEXITCODE -ne 0) { exit 1 }

$allSources = @((Get-Content -LiteralPath $sourcesPath -Raw | ConvertFrom-TvJson).sources)
$running = @($allSources | Where-Object { $_.status -eq 'running' })
$priorities = @{}
foreach ($entry in $allSources) {
  if ($null -ne $entry.priority) { $priorities[$entry.name] = $entry.priority }
}

if ($CleanupOnly) {
  if ($Source) { Write-Host '-CleanupOnly fetches nothing, so -Source does not apply'; exit 1 }
  $now = [DateTimeOffset]::UtcNow
  $existing = @(Read-TvEventFile $dataPath)
  # Nothing was refreshed, so every stored event of a running source is carried as it is.
  $carried = @(Get-CarriedTvEvents $existing -Refreshed @() -Enabled @($running | ForEach-Object name) -Now $now)
  $merged = @(Merge-TvEvents $carried -Priorities $priorities -DropCanceled)
  $archived = @(if (Test-Path -LiteralPath $archiveDir) { Get-ChildItem -LiteralPath $archiveDir -Filter '*.json' | ForEach-Object { Read-TvEventFile $_.FullName } })
  $cityFixes = Resolve-TvOtherCity $merged -Known $archived
  $costFixes = Set-TvCostGuess $merged
  $horizon = $now.AddDays($Days)
  $past = @($merged | Where-Object { Test-TvEventPast $_ $now })
  $upcoming = @(Sort-TvEvents @($merged | Where-Object { -not (Test-TvEventPast $_ $now) -and (Get-TvEventInstant $_.start) -le $horizon }))

  $archiveBefore = 0
  $archiveAfter = 0
  $months = @(if (Test-Path -LiteralPath $archiveDir) { Get-ChildItem -LiteralPath $archiveDir -Filter '*.json' | Sort-Object Name })
  foreach ($file in $months) {
    $stored = @(Read-TvEventFile $file.FullName)
    $cleaned = @(Merge-TvEvents $stored -Priorities $priorities -DropCanceled)
    $monthFixes = Resolve-TvOtherCity $cleaned -Known $archived
    $monthCosts = Set-TvCostGuess $cleaned
    $cityFixes += $monthFixes
    $costFixes += $monthCosts
    $archiveBefore += $stored.Count
    $archiveAfter += $cleaned.Count
    if (-not $NoWrite -and ($cleaned.Count -ne $stored.Count -or $monthFixes -gt 0 -or $monthCosts -gt 0)) {
      Restore-TvFetchedAt $cleaned $stored
      Write-TvEventFile $file.FullName @(Sort-TvEvents $cleaned)
    }
  }
  if (-not $NoWrite) {
    Add-TvArchive $archiveDir $past -Priorities $priorities
    Write-TvEventFile $dataPath $upcoming
  }

  Write-Host "Cleanup: events.json $($existing.Count) -> $($upcoming.Count) upcoming ($($past.Count) moved to the archive), archive $archiveBefore -> $archiveAfter, $cityFixes cities filled in, $costFixes cost guesses changed$($NoWrite ? ' (not written)' : '')"
  exit 0
}

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
$merged = @(Merge-TvEvents (@($fetched) + $carried) -Priorities $priorities -DropCanceled)
Restore-TvFetchedAt $merged $existing
$cityFixes = Resolve-TvOtherCity $merged
$null = Set-TvCostGuess $merged

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
  # Read by the website for its "as of" time. Only the time is kept, so it changes once per run.
  [IO.File]::WriteAllText($metaPath, (([ordered]@{ lastIngest = ($AsOf ? $AsOf : $fetchedAt) } | ConvertTo-Json) -replace "`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
}

Write-RunLog -Upcoming $upcoming -Past $past.Count
$results | Format-Table $display | Out-String | Write-Host
$failed = @($results | Where-Object Status -ne 'ok').Count
Write-Host "$($results.Count - $failed) of $($results.Count) sources succeeded, $($upcoming.Count) upcoming, $($past.Count) past, $cityFixes cities filled in$($NoWrite ? ' (not written)' : '')"
exit 0
