#Requires -Version 7.4
<#
.SYNOPSIS
  Reads upcoming events from the City of Boise events API.
.DESCRIPTION
  cityofboise.org/events is a Vue app that pages through /umbraco/api/events/events, 10 events at
  a time. This adapter makes the same requests, starting today, 1 second apart. Times are Boise
  wall-clock time with no offset. Cancelled events are listed with a "Canceled - " prefix and
  are skipped.
.PARAMETER Source
  One entry from sources.json. url is the API endpoint.
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

$pageSize = 10
$maxPages = 40

function Get-CityPage {
  $today = (ConvertTo-BoiseTime $FetchedAt).Substring(0, 10)
  $page = 0
  $totalPages = 1
  do {
    if ($page -gt 0) { Start-Sleep -Seconds 1 }
    $result = Invoke-TvRequest "$($Source.url)?demo=all&category=all&startDate=$today&endDate=&department=all&playlist=all&page=$page"
    $totalPages = [Math]::Ceiling([int]$result.Total / $pageSize)
    $result
    $page++
  } while ($page -lt $totalPages -and $page -lt $maxPages)
  if ($totalPages -gt $maxPages) {
    Write-Warning "$($Source.name): $totalPages pages, read the first $maxPages"
  }
}

$pages = if ($Response) { $Response | ForEach-Object { ConvertFrom-TvJson $_ } } else { Get-CityPage }
$origin = ([uri]$Source.url).GetLeftPart('Authority')

foreach ($item in ($pages | ForEach-Object { $_.Cards } | Where-Object { $_ })) {
  try {
    if ($item.Title -match '^\s*Cancel+ed\b') { continue }

    $start = ConvertTo-BoiseTime $item.StartDate
    $end = if ($item.EndDate) { ConvertTo-BoiseTime $item.EndDate }
    if ($end -and $end -le $start) { $end = $null }

    $name = ConvertTo-PlainText $item.Location
    $url = if ($item.Url) { [uri]::new([uri]$origin, $item.Url).AbsoluteUri } else { $Source.url }

    New-TvEvent -Title (ConvertTo-PlainText $item.Title) -Start $start -End $end `
      -Venue ($name ? $name : $Source.venue) -VenueKey ($name ? (Get-VenueKey $name) : $Source.venueKey) -City $Source.city `
      -Category $Source.category -InferCategory:([bool]$Source.inferCategory) -Url $url -Description $item.Description `
      -Sources @(@{ name = $Source.name; url = $url; fetchedAt = $FetchedAt })
  } catch {
    Write-Warning "$($Source.name): skipping '$($item.Title)': $_"
  }
}
