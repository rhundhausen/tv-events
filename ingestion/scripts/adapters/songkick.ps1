#Requires -Version 7.4
<#
.SYNOPSIS
  Reads upcoming events for one metro area from the Songkick API.
.DESCRIPTION
  Requires the SONGKICK_API_KEY environment variable.

  Not yet run against the live API, and its official documentation could not be confirmed.
  The endpoint and field names need checking against a real response before this is enabled.
.PARAMETER Source
  One entry from sources.json, with metroAreaId.
.PARAMETER FetchedAt
  UTC timestamp recorded on each event.
.PARAMETER Response
  JSON pages to parse instead of fetching. Used by tests.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][pscustomobject]$Source,
  [Parameter(Mandatory)][string]$FetchedAt,
  [string[]]$Response
)

. "$PSScriptRoot/../lib/Schema.ps1"
. "$PSScriptRoot/../lib/Http.ps1"

function Get-SongkickPage {
  if (-not $env:SONGKICK_API_KEY) {
    throw 'SONGKICK_API_KEY is not set'
  }
  if (-not $Source.metroAreaId) {
    throw "$($Source.name): needs metroAreaId"
  }

  $perPage = 50
  $page = 1
  do {
    if ($page -gt 1) { Start-Sleep -Seconds 1 }
    $result = Invoke-TvRequest "$($Source.url.TrimEnd('/'))/metro_areas/$($Source.metroAreaId)/calendar.json?apikey=$($env:SONGKICK_API_KEY)&page=$page&per_page=$perPage"
    $result
    $more = ($page * $perPage) -lt [int]$result.resultsPage.totalEntries
    $page++
  } while ($more)
}

$pages = if ($Response) { $Response | ForEach-Object { ConvertFrom-TvJson $_ } } else { Get-SongkickPage }

foreach ($item in ($pages | ForEach-Object { $_.resultsPage.results.event } | Where-Object { $_ })) {
  if ($item.status -eq 'cancelled') { continue }

  try {
    # The title often ends with the date and venue. Without a time, the event is all-day.
    $title = ConvertTo-PlainText ($item.displayName -replace '\s+at\s+.+\(.*\)$', '' -replace '\s+\([^)]*\d{4}\)$', '')
    $allDay = -not $item.start.datetime
    $start = if ($allDay) { $item.start.date } else { ConvertTo-BoiseTime $item.start.datetime }

    $venue = ConvertTo-PlainText $item.venue.displayName
    $hasVenue = $venue -and $venue -ne 'Unknown venue'
    $city = Resolve-TvCity (($item.location.city -split ',')[0])

    New-TvEvent -Title $title -Start $start -AllDay:$allDay `
      -Venue ($hasVenue ? $venue : $Source.venue) -VenueKey ($hasVenue ? (Get-VenueKey $venue) : $Source.venueKey) -City ($city ? $city : $Source.city) `
      -Category $Source.category -InferCategory:([bool]$Source.inferCategory) -Url $item.uri `
      -Sources @(@{ name = $Source.name; url = $item.uri; fetchedAt = $FetchedAt })
  } catch {
    Write-Warning "$($Source.name): skipping '$($item.displayName)': $_"
  }
}
