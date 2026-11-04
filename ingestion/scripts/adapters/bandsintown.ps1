#Requires -Version 7.4
<#
.SYNOPSIS
  Reads events for one artist from the Bandsintown API.
.DESCRIPTION
  The events endpoint is keyed by artist, so only Idaho dates are kept. Requires the
  BANDSINTOWN_APP_ID environment variable, which must be an id Bandsintown has approved.
.PARAMETER Source
  One entry from sources.json, with artistOrVenue.
.PARAMETER FetchedAt
  UTC timestamp recorded on each event.
.PARAMETER Response
  JSON to parse instead of fetching. Used by tests.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][pscustomobject]$Source,
  [Parameter(Mandatory)][string]$FetchedAt,
  [string[]]$Response
)

. "$PSScriptRoot/../lib/Schema.ps1"
. "$PSScriptRoot/../lib/Http.ps1"

function Get-BandsintownEvent {
  if (-not $env:BANDSINTOWN_APP_ID) {
    throw 'BANDSINTOWN_APP_ID is not set'
  }
  $name = [uri]::EscapeDataString($Source.artistOrVenue)
  Invoke-TvRequest "$($Source.url)/artists/$name/events?app_id=$($env:BANDSINTOWN_APP_ID)"
}

$items = if ($Response) { ConvertFrom-TvJson $Response[0] } else { Get-BandsintownEvent }

foreach ($item in ($items | Where-Object { $_ })) {
  if ($item.venue.region -ne 'ID') { continue }

  try {
    $venue = ConvertTo-PlainText $item.venue.name
    $city = Resolve-TvCity $item.venue.city
    $title = if ($item.title) { ConvertTo-PlainText $item.title } else { "$($item.lineup -join ', ') at $venue" }

    New-TvEvent -Title $title -Start (ConvertTo-BoiseTime $item.datetime) `
      -Venue ($venue ? $venue : $Source.venue) -City ($city ? $city : $Source.city) `
      -Category $Source.category -InferCategory:([bool]$Source.inferCategory) -Url $item.url -Description $item.description `
      -Sources @(@{ name = $Source.name; url = $item.url; fetchedAt = $FetchedAt })
  } catch {
    Write-Warning "$($Source.name): skipping '$($item.title)': $_"
  }
}
