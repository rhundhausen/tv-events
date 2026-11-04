#Requires -Version 7.4
<#
.SYNOPSIS
  Reads upcoming events from an RSS 2.0 feed that uses the RSS event module.
.DESCRIPTION
  Each item needs ev:startdate (http://purl.org/rss/1.0/modules/event/); items without one are
  skipped, because a plain news feed has no event dates. ev:enddate, ev:location and ev:type are
  used when present. carbonhouse venue sites publish this at /events/rss.

  The venue is ev:location, with venuePrefix in front of it when set, so a location of "Arena"
  becomes "Ford Idaho Center Arena". With fixedVenue, or when an item has no location, the entry's
  own venue is used. ev:type is passed on as a publisher label for classification.
.PARAMETER Source
  One entry from sources.json. url is the feed.
.PARAMETER FetchedAt
  UTC timestamp recorded on each event.
.PARAMETER Response
  Feed XML to parse instead of fetching. Used by tests.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][pscustomobject]$Source,
  [Parameter(Mandatory)][string]$FetchedAt,
  [string]$Response
)

. "$PSScriptRoot/../lib/Schema.ps1"
. "$PSScriptRoot/../lib/Http.ps1"

$text = if ($Response) { $Response } else { Invoke-TvRequest $Source.url -Raw }
$feed = [xml]$text
$ns = [System.Xml.XmlNamespaceManager]::new($feed.NameTable)
$ns.AddNamespace('ev', 'http://purl.org/rss/1.0/modules/event/')

function Get-ItemText([System.Xml.XmlNode]$Item, [string]$Path) {
  $node = $Item.SelectSingleNode($Path, $ns)
  if ($node) { $node.InnerText.Trim() } else { '' }
}

foreach ($item in $feed.SelectNodes('/rss/channel/item')) {
  $title = ConvertTo-PlainText (Get-ItemText $item 'title')
  try {
    $startText = Get-ItemText $item 'ev:startdate'
    if (-not $startText) { continue }
    if ($Source.excludeTitlePattern -and $title -match $Source.excludeTitlePattern) { continue }

    $start = ConvertTo-BoiseTime $startText
    $endText = Get-ItemText $item 'ev:enddate'
    $end = if ($endText) { ConvertTo-BoiseTime $endText }
    if ($end -and $end -le $start) { $end = $null }

    $location = ConvertTo-PlainText (Get-ItemText $item 'ev:location')
    if ($Source.fixedVenue -or -not $location) {
      $venue = $Source.venue
      $venueKey = $Source.venueKey
    } else {
      $venue = if ($Source.venuePrefix) { "$($Source.venuePrefix) $location" } else { $location }
      $venueKey = Get-VenueKey $venue
    }

    $link = Get-ItemText $item 'link'
    $url = if ($link) { $link } else { $Source.url }
    $type = ConvertTo-PlainText (Get-ItemText $item 'ev:type')

    New-TvEvent -Title $title -Start $start -End $end -Venue $venue -VenueKey $venueKey -City $Source.city `
      -Category $Source.category -InferCategory:([bool]$Source.inferCategory) -Labels @($type | Where-Object { $_ }) `
      -Url $url -Description (ConvertTo-PlainText (Get-ItemText $item 'description')) `
      -Sources @(@{ name = $Source.name; url = $url; fetchedAt = $FetchedAt })
  } catch {
    Write-Warning "$($Source.name): skipping '$title': $_"
  }
}
