# Reading and writing data/raw-events.json, the file ingest writes and refine reads.
#
# Shape:
#   {
#     "asOf": "2026-11-06T07:00:00Z",          the scheduled time of the run, shown on the site
#     "sources": {
#       "<name>": { "fetchedAt": "...", "events": [ ... ] }    the source's last good fetch
#     }
#   }
# Events are as the adapters built them (New-TvEvent), before any merge, so an event two
# sources report appears once under each.

. "$PSScriptRoot/Store.ps1"

function Read-TvRawFile {
  # The raw file, or nothing if it doesn't exist yet. Fails on a file that isn't one.
  [CmdletBinding()]
  param([Parameter(Mandatory, Position = 0)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return }
  $raw = ConvertFrom-TvJson (Get-Content -LiteralPath $Path -Raw)
  if ($raw -isnot [pscustomobject] -or -not $raw.asOf -or $null -eq $raw.sources) {
    throw "$Path is not a raw events file: it needs asOf and sources"
  }
  $raw
}

function Write-TvRawFile {
  # 2-space JSON with LF line endings and a final newline, as Write-TvEventFile.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)][string]$Path,
    [Parameter(Mandatory, Position = 1)][object]$Raw
  )

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
  $json = ConvertTo-Json -InputObject $Raw -Depth 10
  [IO.File]::WriteAllText($Path, ($json -replace "`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
}

function Get-TvRawEvents {
  <#
  .SYNOPSIS
    Every source's events in one list.
  .PARAMETER Order
    Source names in the order to list them; sources not named come after, by name. The merge
    breaks a priority tie by input order, so refine passes the sources.json order, which is the
    order ingest used to fetch them in before the split.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)][object]$Raw,
    [string[]]$Order = @()
  )

  $names = @($Raw.sources.PSObject.Properties.Name)
  $ordered = @($Order | Where-Object { $_ -in $names }) + @($names | Where-Object { $_ -notin $Order })
  foreach ($name in $ordered) {
    @($Raw.sources.$name.events) | Where-Object { $_ }
  }
}

function Update-TvRawFile {
  <#
  .SYNOPSIS
    Builds the new raw file from the previous one and this run's fetches.
  .DESCRIPTION
    A source that was fetched replaces its entry, even with no events. A source that failed, or
    wasn't fetched this run, keeps its last good entry, so refine always sees every source. Sources
    not in Keep are dropped. An event already stored keeps its first fetchedAt, so the file only
    changes when the events do.
  .PARAMETER Previous
    The current raw file, or $null.
  .PARAMETER Results
    One object per source fetched: Name, Status (ok or failed), and Events.
  .PARAMETER Keep
    The sources the file should hold: the running ones, plus any run by name.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)][AllowNull()][object]$Previous,
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Keep,
    [Parameter(Mandatory)][string]$AsOf,
    [Parameter(Mandatory)][string]$FetchedAt
  )

  $entries = @{}
  if ($Previous) {
    foreach ($property in $Previous.sources.PSObject.Properties) { $entries[$property.Name] = $property.Value }
  }
  foreach ($result in $Results | Where-Object Status -eq 'ok') {
    $events = @($result.Events | Where-Object { $_ })
    $old = $entries[$result.Name]
    if ($old) { Restore-TvFetchedAt $events @($old.events | Where-Object { $_ }) }
    $entries[$result.Name] = [pscustomobject][ordered]@{
      fetchedAt = $FetchedAt
      events    = @(if ($events.Count) { Sort-TvEvents $events })
    }
  }

  $sources = [ordered]@{}
  foreach ($name in @($entries.Keys | Where-Object { $_ -in $Keep } | Sort-Object { $_ } -Culture ([Globalization.CultureInfo]::InvariantCulture))) {
    $sources[$name] = $entries[$name]
  }
  [pscustomobject][ordered]@{ asOf = $AsOf; sources = [pscustomobject]$sources }
}
