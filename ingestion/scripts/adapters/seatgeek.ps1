#Requires -Version 7.4
<#
.SYNOPSIS
  Reads upcoming events near a point from the SeatGeek API.
.DESCRIPTION
  Only Idaho venues are kept. Ticket prices in the response are ignored. Requires the
  SEATGEEK_CLIENT_ID environment variable.

  Not yet run against the live API. Field names follow SeatGeek's platform documentation.
.PARAMETER Source
  One entry from sources.json, with latlong and radius.
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
  'concert' = 'music'
  'music_festival' = 'music'
  'theater' = 'performing-arts'
  'broadway_tickets_national' = 'performing-arts'
  'comedy' = 'performing-arts'
  'dance_performance_tour' = 'performing-arts'
  'classical' = 'music'
  'sports' = 'sports'
}

function Get-SeatGeekPage {
  if (-not $env:SEATGEEK_CLIENT_ID) {
    throw 'SEATGEEK_CLIENT_ID is not set'
  }

  $lat, $lon = $Source.latlong -split ','
  $perPage = 100
  $page = 1
  do {
    if ($page -gt 1) { Start-Sleep -Seconds 1 }
    $result = Invoke-TvRequest "$($Source.url)?client_id=$($env:SEATGEEK_CLIENT_ID)&lat=$lat&lon=$lon&range=$($Source.radius)mi&per_page=$perPage&page=$page"
    $result
    $more = ($page * $perPage) -lt [int]$result.meta.total
    $page++
  } while ($more)
}

$pages = if ($Response) { $Response | ForEach-Object { ConvertFrom-TvJson $_ } } else { Get-SeatGeekPage }

foreach ($item in ($pages | ForEach-Object { $_.events } | Where-Object { $_ })) {
  if ($item.venue.state -ne 'ID') { continue }

  try {
    # When the time is unknown, SeatGeek sends a placeholder of 3:30 AM on the right date.
    $allDay = [bool]$item.time_tbd -or [bool]$item.date_tbd
    $start = if ($allDay) { $item.datetime_local.Substring(0, 10) } else { ConvertTo-BoiseTime "$($item.datetime_utc)Z" }

    $venue = ConvertTo-PlainText $item.venue.name
    $city = Resolve-TvCity $item.venue.city
    $labels = @($item.type) + @($item.taxonomies.name)
    $category = if ($item.type -and $categories.ContainsKey($item.type)) { $categories[$item.type] } else { $Source.category }

    New-TvEvent -Title (ConvertTo-PlainText $item.title) -Start $start -AllDay:$allDay `
      -Venue ($venue ? $venue : $Source.venue) -VenueKey ($venue ? (Get-VenueKey $venue) : $Source.venueKey) -City ($city ? $city : $Source.city) `
      -Category $category -InferCategory:([bool]$Source.inferCategory) -Labels $labels -Url $item.url `
      -Cost ($null -ne $item.stats.lowest_price ? (Get-TvCostTier -Amount $item.stats.lowest_price) : '') -Sources @(@{ name = $Source.name; url = $item.url; fetchedAt = $FetchedAt })
  } catch {
    Write-Warning "$($Source.name): skipping '$($item.title)': $_"
  }
}
