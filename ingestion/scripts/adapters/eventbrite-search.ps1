#Requires -Version 7.4
<#
.SYNOPSIS
  Reads events from an Eventbrite browse page, such as https://www.eventbrite.com/d/id--emmett/events/.
.DESCRIPTION
  Eventbrite's API dropped location search in 2019, but its browse pages carry their events as
  JSON in window.__SERVER_DATA__ (buckets[].events[]), with start and end in the event's zone.
  Online events and events with no address, or an address outside Idaho, are skipped.

  The listing has no prices, so each kept event's own page is read for its schema.org offers,
  which set the cost tier. A failed event page keeps the event without a cost. Every request is
  checked against robots.txt and spaced at least 1 second apart, as in scrape.ps1.
.PARAMETER Source
  One entry from sources.json, with url set to the browse page.
.PARAMETER FetchedAt
  UTC timestamp recorded on each event.
.PARAMETER Response
  HTML to parse instead of fetching: the browse page, then each kept event's page in order.
  Missing event pages mean no cost. Used by tests.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][pscustomobject]$Source,
  [Parameter(Mandatory)][string]$FetchedAt,
  [string[]]$Response
)

. "$PSScriptRoot/../lib/Schema.ps1"
. "$PSScriptRoot/../lib/Http.ps1"
. "$PSScriptRoot/../lib/Scrape.ps1"

$listUri = [uri]$Source.url
$script:robots = ''
$script:delay = 1
$script:requests = 0

if (-not $Response) {
  try {
    $script:robots = Invoke-TvRequest "$($listUri.GetLeftPart('Authority'))/robots.txt" -Raw
  } catch {
    if ("$_" -notmatch 'HTTP 404') { throw }
  }
  $script:delay = [Math]::Max(1, [int](Get-TvRobotsGroup $script:robots).Delay)
  if ($script:delay -gt 60) { throw "$($Source.name): robots.txt asks for $($script:delay) seconds between requests" }
}

function Get-EventbritePage {
  param([uri]$Uri)

  if (-not (Test-TvRobotsAllowed $script:robots $Uri.PathAndQuery)) {
    throw "$($Source.name): robots.txt disallows $($Uri.PathAndQuery)"
  }
  if ($script:requests -gt 0) { Start-Sleep -Seconds $script:delay }
  $script:requests++
  Invoke-TvRequest $Uri.AbsoluteUri -Raw
}

function Read-ServerData {
  # The object after "window.__SERVER_DATA__ = " runs to its closing brace, followed by more script.
  # Newtonsoft (shipped with PowerShell) reads exactly one JSON value and stops there.
  param([string]$Html)

  $at = $Html.IndexOf('__SERVER_DATA__ = ')
  if ($at -lt 0) { throw "$($Source.name): no __SERVER_DATA__ on the page" }
  $reader = [Newtonsoft.Json.JsonTextReader]::new([IO.StringReader]::new($Html.Substring($at + 18)))
  $reader.DateParseHandling = [Newtonsoft.Json.DateParseHandling]::None
  ConvertFrom-TvJson ([Newtonsoft.Json.Linq.JToken]::ReadFrom($reader).ToString([Newtonsoft.Json.Formatting]::None))
}

function Get-EventbriteCost {
  # Eventbrite's offers are reliable, so a lowest price of 0 means free here.
  param([string]$Html)

  $node = @(Get-TvJsonLdEvent $Html) | Select-Object -First 1
  if (-not $node) { return '' }
  $prices = @(@($node.offers) | ForEach-Object { $_.lowPrice; $_.price } | ForEach-Object {
      $value = 0.0
      if ([double]::TryParse("$_", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) { $value }
    })
  if ($prices.Count -eq 0) { return '' }
  Get-TvCostTier -Amount ($prices | Measure-Object -Minimum).Minimum
}

$html = if ($Response) { $Response[0] } else { Get-EventbritePage $listUri }
$data = Read-ServerData $html

$seen = [Collections.Generic.HashSet[string]]::new()
$kept = @(foreach ($item in @($data.buckets | ForEach-Object { $_.events } | Where-Object { $_ })) {
    if (-not $seen.Add("$($item.id)")) { continue }
    if ($item.is_online_event -or $item.is_cancelled) { continue }
    $address = $item.primary_venue.address
    if (-not $address -or -not $address.city -or "$($address.region)" -ne 'ID') { continue }
    $item
  })

for ($n = 0; $n -lt $kept.Count; $n++) {
  $item = $kept[$n]
  try {
    $zone = if ($item.timezone) { $item.timezone } else { 'America/Boise' }
    $allDay = -not $item.start_time
    $start = if ($allDay) { $item.start_date } else { ConvertTo-BoiseTime "$($item.start_date) $($item.start_time)" $zone }
    $end = if ($allDay) {
      if ($item.end_date -gt $item.start_date) { $item.end_date }
    } elseif ($item.end_date -and $item.end_time) {
      $value = ConvertTo-BoiseTime "$($item.end_date) $($item.end_time)" $zone
      if ($value -gt $start) { $value }
    }

    $venueName = ConvertTo-PlainText $item.primary_venue.name
    $city = Resolve-TvCity $item.primary_venue.address.city
    $url = "$($item.url)"

    $page = if ($Response) { if ($Response.Count -gt $n + 1) { $Response[$n + 1] } } else {
      try { Get-EventbritePage ([uri]$url) } catch {
        if ("$_" -match 'robots.txt disallows') { throw }
        Write-Warning "$($Source.name): no price for '$($item.name)': $_"
      }
    }
    $cost = if ($page) { Get-EventbriteCost $page } else { '' }

    New-TvEvent -Title (ConvertTo-PlainText $item.name) -Start $start -End $end -AllDay:$allDay `
      -Venue ($venueName ? $venueName : $Source.venue) -VenueKey ($venueName ? (Get-VenueKey $venueName) : $Source.venueKey) `
      -City ($city ? $city : $Source.city) -Category $Source.category -InferCategory:([bool]$Source.inferCategory) `
      -Url $url -Description $item.summary -Cost $cost -Sources @(@{ name = $Source.name; url = $url; fetchedAt = $FetchedAt })
  } catch {
    if ("$_" -match 'robots.txt disallows') { throw }
    Write-Warning "$($Source.name): skipping '$($item.name)': $_"
  }
}
