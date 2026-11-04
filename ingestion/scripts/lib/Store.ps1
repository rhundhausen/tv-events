# Reading and writing data/events.json and data/archive/YYYY-MM.json.

. "$PSScriptRoot/Schema.ps1"
. "$PSScriptRoot/Http.ps1"
. "$PSScriptRoot/Dedupe.ps1"

function Read-TvEventFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) { return }
  $text = Get-Content -LiteralPath $Path -Raw
  if ([string]::IsNullOrWhiteSpace($text)) { return }
  ConvertFrom-TvJson $text
}

function Write-TvEventFile {
  # 2-space JSON with LF line endings and a final newline, so git diffs stay small.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Path,

    [Parameter(Mandatory, Position = 1)]
    [AllowEmptyCollection()]
    [object[]]$Events
  )

  $directory = Split-Path -Parent $Path
  if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
  }
  $json = ConvertTo-Json -InputObject @($Events) -Depth 6
  $text = ($json -replace "`r`n", "`n") + "`n"
  [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

function Sort-TvEvents {
  # Sorts by instant, not by string, so the order doesn't depend on culture or offset.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [AllowEmptyCollection()]
    [object[]]$Events
  )

  $Events | Sort-Object @{ e = { Get-TvEventInstant $_.start } }, id
}

function Test-TvEventPast {
  # Past once it has ended, or once it has started if it reports no end.
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory, Position = 0)]
    [object]$Event,

    [Parameter(Mandatory, Position = 1)]
    [DateTimeOffset]$Now
  )

  $last = if ($Event.end) { $Event.end } else { $Event.start }
  if ($last.Length -eq 10) {
    $today = (ConvertTo-BoiseTime $Now).Substring(0, 10)
    return $last -lt $today
  }
  (Get-TvEventInstant $last) -lt $Now
}

function Get-CarriedTvEvents {
  <#
  .SYNOPSIS
    Picks the stored events that must survive a run.
  .DESCRIPTION
    Past events stay so they can be archived, since feeds stop reporting them. Upcoming events
    stay for sources that weren't refreshed, so a failed adapter or a -Source run can't wipe
    another source's events. A refreshed source's upcoming events are dropped, because the
    new fetch replaces them: that is how a removed event disappears. Sources that are no longer
    enabled aren't carried.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [AllowEmptyCollection()]
    [object[]]$Existing,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [string[]]$Refreshed,

    [Parameter(Mandatory)]
    [AllowEmptyCollection()]
    [string[]]$Enabled,

    [Parameter(Mandatory)]
    [DateTimeOffset]$Now
  )

  foreach ($event in $Existing) {
    if (Test-TvEventPast $event $Now) {
      $event
      continue
    }

    $remaining = @($event.sources | Where-Object { $_.name -notin $Refreshed -and $_.name -in $Enabled })
    if ($remaining.Count -gt 0) {
      $copy = $event | Select-Object *
      $copy.sources = $remaining
      $copy
    }
  }
}

function Restore-TvFetchedAt {
  <#
  .SYNOPSIS
    Keeps the first fetchedAt for each event and source already stored.
  .DESCRIPTION
    A new timestamp on every event would rewrite the whole file nightly, even when nothing
    changed, and bury real changes in the git history.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [AllowEmptyCollection()]
    [object[]]$Events,

    [Parameter(Mandatory, Position = 1)]
    [AllowEmptyCollection()]
    [object[]]$Existing
  )

  $firstSeen = @{}
  foreach ($event in $Existing) {
    foreach ($source in @($event.sources)) {
      $firstSeen["$($event.id)|$($source.name)"] = $source.fetchedAt
    }
  }

  foreach ($event in $Events) {
    foreach ($source in @($event.sources)) {
      $stored = $firstSeen["$($event.id)|$($source.name)"]
      if ($stored) { $source.fetchedAt = $stored }
    }
  }
}

function Add-TvArchive {
  # Appends past events to data/archive/YYYY-MM.json, deduping within each month's file.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [string]$Directory,

    [Parameter(Mandatory, Position = 1)]
    [AllowEmptyCollection()]
    [object[]]$Events,

    [hashtable]$Priorities = @{}
  )

  foreach ($month in ($Events | Group-Object { $_.start.Substring(0, 7) })) {
    $path = Join-Path $Directory "$($month.Name).json"
    $stored = @(Read-TvEventFile $path)
    $combined = @($stored) + @($month.Group)
    $merged = @(Merge-TvEvents $combined -Priorities $Priorities)
    Restore-TvFetchedAt $merged $stored
    Write-TvEventFile $path @(Sort-TvEvents $merged)
  }
}
