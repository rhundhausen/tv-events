#Requires -Version 7.4
<#
.SYNOPSIS
  Reads live events from Eventbrite, for a list of organizations and venues.
.DESCRIPTION
  Eventbrite shut down location search in 2019, so each organization or venue must be listed
  by id. Requires the EVENTBRITE_TOKEN environment variable.

  Not yet run against the live API. Field names follow Eventbrite's documented event object.
.PARAMETER Source
  One entry from sources.json, with organizationIds or venueIds.
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

function Get-EventbritePage {
  if (-not $env:EVENTBRITE_TOKEN) {
    throw 'EVENTBRITE_TOKEN is not set'
  }

  $paths = @(@($Source.organizationIds | Where-Object { $_ } | ForEach-Object { "organizations/$_/events/" }) +
    @($Source.venueIds | Where-Object { $_ } | ForEach-Object { "venues/$_/events/" }))
  if ($paths.Count -eq 0) {
    throw "$($Source.name): needs organizationIds or venueIds, because Eventbrite has no location search"
  }

  $headers = @{ Authorization = "Bearer $($env:EVENTBRITE_TOKEN)" }
  $first = $true
  foreach ($path in $paths) {
    $continuation = ''
    do {
      if (-not $first) { Start-Sleep -Seconds 1 }
      $first = $false
      $result = Invoke-TvRequest "$($Source.url.TrimEnd('/'))/$($path)?status=live&order_by=start_asc&time_filter=current_future&expand=venue$continuation" -Headers $headers
      $result
      $more = [bool]$result.pagination.has_more_items
      $continuation = "&continuation=$($result.pagination.continuation)"
    } while ($more)
  }
}

$pages = if ($Response) { $Response | ForEach-Object { ConvertFrom-TvJson $_ } } else { Get-EventbritePage }

foreach ($item in ($pages | ForEach-Object { $_.events } | Where-Object { $_ })) {
  if ($item.status -eq 'canceled' -or $item.online_event) { continue }

  try {
    $start = ConvertTo-BoiseTime "$($item.start.utc)"
    $end = if ($item.end.utc) { ConvertTo-BoiseTime "$($item.end.utc)" }
    $venue = $item.venue
    $name = ConvertTo-PlainText $venue.name
    $city = Resolve-TvCity $venue.address.city

    New-TvEvent -Title (ConvertTo-PlainText $item.name.text) -Start $start -End $end `
      -Venue ($name ? $name : $Source.venue) -VenueKey ($name ? (Get-VenueKey $name) : $Source.venueKey) -City ($city ? $city : $Source.city) `
      -Category $Source.category -InferCategory:([bool]$Source.inferCategory) -Url $item.url -Description $item.summary `
      -Sources @(@{ name = $Source.name; url = $item.url; fetchedAt = $FetchedAt })
  } catch {
    Write-Warning "$($Source.name): skipping '$($item.name.text)': $_"
  }
}
