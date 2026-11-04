#Requires -Version 7.4
<#
.SYNOPSIS
  Reads upcoming events from the Ticketmaster Discovery API, for one venue or for an area.
.DESCRIPTION
  With venueId, venue and city come from the source entry, not the response, so a venue's key
  matches the key other sources use for it. With latlong and radius, they come from each event,
  and excludeVenueIds, excludeSegments, and excludeTitlePattern keep out what other sources
  already cover and listings that aren't events. Requires the TICKETMASTER_KEY environment
  variable.
.PARAMETER Source
  One entry from sources.json, with venueId, or with latlong and radius.
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

$categories = @{
  'Music'          = 'music'
  'Sports'         = 'sports'
  'Arts & Theatre' = 'performing-arts'
  'Film'           = 'arts-culture'
}

function Get-TicketmasterPage {
  if (-not $env:TICKETMASTER_KEY) {
    throw 'TICKETMASTER_KEY is not set'
  }

  $filter = if ($Source.venueId) {
    "venueId=$($Source.venueId)"
  } else {
    "latlong=$($Source.latlong)&radius=$($Source.radius)&unit=miles"
  }

  # The API refuses to page past 1,000 results, so 10 pages of 100 is the limit.
  $page = 0
  do {
    if ($page -gt 0) { Start-Sleep -Seconds 1 }
    $result = Invoke-TvRequest "$($Source.url)?$filter&size=100&sort=date,asc&page=$page&apikey=$($env:TICKETMASTER_KEY)"
    $totalPages = [Math]::Min([int]$result.page.totalPages, 10)
    $result
    $page++
  } while ($page -lt $totalPages)
}

$pages = if ($Response) { $Response | ForEach-Object { ConvertFrom-TvJson $_ } } else { Get-TicketmasterPage }

foreach ($item in ($pages | ForEach-Object { $_._embedded.events } | Where-Object { $_ })) {
  if ($item.test -or $item.dates.status.code -eq 'cancelled') { continue }

  $venue = @($item._embedded.venues) | Select-Object -First 1
  $classification = $item.classifications | Select-Object -First 1
  $segment = $classification.segment.name
  if ($venue.id -and $venue.id -in @($Source.excludeVenueIds)) { continue }
  if ($segment -and $segment -in @($Source.excludeSegments)) { continue }
  if ($Source.excludeTitlePattern -and $item.name -match $Source.excludeTitlePattern) { continue }

  try {
    $when = $item.dates.start
    $allDay = -not $when.dateTime -or $when.timeTBA -or $when.noSpecificTime
    $start = if ($allDay) { $when.localDate } else { ConvertTo-BoiseTime $when.dateTime }

    $labels = @($segment, $classification.genre.name, $classification.subGenre.name)
    $category = if ($segment -and $categories.ContainsKey($segment)) { $categories[$segment] } else { $Source.category }

    $venueName = if ($Source.venueId) { $Source.venue } else { ConvertTo-PlainText $venue.name }
    if (-not $venueName) { $venueName = $Source.venue }
    $venueKey = if ($Source.venueId -or -not $venue.name) { $Source.venueKey } else { Get-VenueKey $venueName }
    $city = if ($Source.venueId) { $Source.city } else { Resolve-TvCity $venue.city.name }
    if (-not $city) { $city = $Source.city }

    New-TvEvent -Title (ConvertTo-PlainText $item.name) -Start $start -AllDay:$allDay `
      -Venue $venueName -VenueKey $venueKey -City $city `
      -Category $category -InferCategory:([bool]$Source.inferCategory) -Labels $labels -Url $item.url -Description $item.info `
      -Sources @(@{ name = $Source.name; url = $item.url; fetchedAt = $FetchedAt })
  } catch {
    Write-Warning "$($Source.name): skipping '$($item.name)': $_"
  }
}
