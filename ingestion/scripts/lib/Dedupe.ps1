# Cross-source deduplication.

. "$PSScriptRoot/Schema.ps1"

function Get-JaroWinkler {
  [CmdletBinding()]
  [OutputType([double])]
  param(
    [Parameter(Mandatory, Position = 0)][AllowEmptyString()][string]$First,
    [Parameter(Mandatory, Position = 1)][AllowEmptyString()][string]$Second
  )

  if ($First -ceq $Second) { return [double]1 }
  if (-not $First -or -not $Second) { return [double]0 }

  $window = [Math]::Max([Math]::Max($First.Length, $Second.Length) / 2 - 1, 0)
  $window = [Math]::Floor($window)
  $firstMatched = [bool[]]::new($First.Length)
  $secondMatched = [bool[]]::new($Second.Length)

  $matchCount = 0
  for ($i = 0; $i -lt $First.Length; $i++) {
    $from = [Math]::Max($i - $window, 0)
    $to = [Math]::Min($i + $window, $Second.Length - 1)
    for ($j = $from; $j -le $to; $j++) {
      if (-not $secondMatched[$j] -and $First[$i] -ceq $Second[$j]) {
        $firstMatched[$i] = $true
        $secondMatched[$j] = $true
        $matchCount++
        break
      }
    }
  }
  if ($matchCount -eq 0) { return [double]0 }

  $transpositions = 0
  $k = 0
  for ($i = 0; $i -lt $First.Length; $i++) {
    if (-not $firstMatched[$i]) { continue }
    while (-not $secondMatched[$k]) { $k++ }
    if ($First[$i] -cne $Second[$k]) { $transpositions++ }
    $k++
  }

  $m = [double]$matchCount
  $jaro = ($m / $First.Length + $m / $Second.Length + ($m - [Math]::Floor($transpositions / 2)) / $m) / 3

  $prefix = 0
  $limit = [Math]::Min(4, [Math]::Min($First.Length, $Second.Length))
  while ($prefix -lt $limit -and $First[$prefix] -ceq $Second[$prefix]) { $prefix++ }

  [double]($jaro + $prefix * 0.1 * (1 - $jaro))
}

function Get-TvEventRank {
  # The best (lowest) priority among the sources that reported the event.
  param(
    [object]$Event,
    [hashtable]$Priorities
  )

  $ranks = @($Event.sources | ForEach-Object {
      if ($Priorities.ContainsKey($_.name)) { $Priorities[$_.name] } else { 50 }
    })
  if ($ranks.Count -eq 0) { return 50 }
  ($ranks | Measure-Object -Minimum).Minimum
}

function Merge-TvEvents {
  <#
  .SYNOPSIS
    Collapses events that describe the same thing.
  .DESCRIPTION
    Two events are the same if their ids match, or if their normalized titles have Jaro-Winkler
    similarity above 0.9, they start within 30 minutes, and venueKey matches.

    The event from the best-priority source supplies the url and other fields, the longest
    description wins, tags are unioned, and sources are unioned by name. When two reports from one source
    disagree on fetchedAt, the earliest is kept so a re-run doesn't change stored data.
  .PARAMETER Priorities
    Source name to priority. Lower is better, and sources not listed count as 50.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [AllowEmptyCollection()]
    [object[]]$Events,

    [hashtable]$Priorities = @{}
  )

  $ordered = $Events |
    Select-Object @{ n = 'Event'; e = { $_ } }, @{ n = 'Rank'; e = { Get-TvEventRank $_ $Priorities } }, @{ n = 'Instant'; e = { Get-TvEventInstant $_.start } } |
    Sort-Object Rank, Instant, @{ e = { $_.Event.id } }

  $kept = [System.Collections.Generic.List[object]]::new()
  $byId = @{}
  $bySlot = @{}
  $slotTicks = [TimeSpan]::FromMinutes(30).Ticks

  foreach ($entry in $ordered) {
    $event = $entry.Event
    $title = Get-NormalizedTitle $event.title
    $slot = [Math]::Floor($entry.Instant.UtcTicks / $slotTicks)

    $match = $byId[$event.id]
    if (-not $match) {
      # Anything within 30 minutes lands in this slot or a neighbor, so a busy venue stays cheap.
      :search foreach ($neighbor in ($slot - 1), $slot, ($slot + 1)) {
        foreach ($candidate in @($bySlot["$($event.venueKey)|$neighbor"])) {
          if (-not $candidate) { continue }
          $gap = [Math]::Abs(($candidate.Instant - $entry.Instant).TotalMinutes)
          if ($gap -le 30 -and (Get-JaroWinkler $title $candidate.Title) -gt 0.9) {
            $match = $candidate
            break search
          }
        }
      }
    }

    if ($match) {
      $target = $match.Event
      if ("$($event.description)".Length -gt "$($target.description)".Length) {
        $target | Add-Member -NotePropertyName description -NotePropertyValue $event.description -Force
      }
      # A timed end doesn't fit an all-day event, or the other way around.
      if ($event.end -and -not $target.end -and $event.allDay -eq $target.allDay) {
        $target | Add-Member -NotePropertyName end -NotePropertyValue $event.end -Force
      }

      [string[]]$tags = @(@($target.tags) + @($event.tags) | Where-Object { $_ } | Select-Object -Unique)
      [Array]::Sort($tags, [StringComparer]::Ordinal)
      $target.tags = $tags

      $union = @{}
      foreach ($source in (@($target.sources) + @($event.sources))) {
        $seen = $union[$source.name]
        if (-not $seen -or [string]$source.fetchedAt -lt [string]$seen.fetchedAt) {
          $union[$source.name] = $source
        }
      }
      $target.sources = @($union.Keys | Sort-Object | ForEach-Object { $union[$_] })
      $byId[$event.id] = $match
      continue
    }

    $copy = $event | Select-Object *
    $copy.sources = @($event.sources)
    $record = [pscustomobject]@{ Event = $copy; Title = $title; Instant = $entry.Instant }
    $kept.Add($record)
    $byId[$event.id] = $record
    $slotKey = "$($event.venueKey)|$slot"
    if (-not $bySlot.ContainsKey($slotKey)) {
      $bySlot[$slotKey] = [System.Collections.Generic.List[object]]::new()
    }
    $bySlot[$slotKey].Add($record)
  }

  $kept | ForEach-Object { $_.Event }
}
