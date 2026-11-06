BeforeAll {
  $script:repo = Join-Path $PSScriptRoot '..' '..'
  $script:adapter = Join-Path $repo 'scripts' 'adapters' 'eventbrite-search.ps1'
  $script:source = (Get-Content (Join-Path $repo 'sources.json') -Raw | ConvertFrom-Json).sources | Where-Object name -eq 'eventbrite-emmett'
  $script:fetchedAt = '2026-11-06T04:00:00Z'

  function Get-Fixture {
    param([string]$Name)
    Get-Content (Join-Path $repo 'tests' 'fixtures' 'eventbrite-search' $Name) -Raw
  }

  function New-OfferPage {
    param([string]$Low)
    "<script type=`"application/ld+json`">{`"@type`":`"Event`",`"offers`":[{`"@type`":`"AggregateOffer`",`"lowPrice`":`"$Low`",`"highPrice`":`"200.0`"}]}</script>"
  }
}

Describe 'eventbrite-search adapter' {
  BeforeAll {
    $events = @(& $adapter -Source $source -FetchedAt $fetchedAt -Response @(Get-Fixture 'emmett.html'))
  }

  It 'keeps the in-person events and drops the ones with no place' {
    $events.Count | Should -Be 8
    $events.title | Should -Not -Contain 'Managing Your Emotions - Prof Ethan Kross'
  }

  It 'reads the start and end in Boise time' {
    $event = $events | Where-Object title -eq 'Birding the Park at Expo Idaho'
    $event.start | Should -Be '2026-11-08T08:30:00-07:00'
    $event.end | Should -Be '2026-11-08T11:00:00-07:00'
  }

  It 'takes the venue and city from the event' {
    $event = $events | Where-Object title -eq 'Birding the Park at Expo Idaho'
    $event.city | Should -Be 'Garden City'
    $event.venue | Should -Be 'Meet at the parking lot near Glenwood Bridge'
  }

  It 'links the Eventbrite page and records the source' {
    $event = $events | Where-Object title -eq 'Birding the Park at Expo Idaho'
    $event.url | Should -Be 'https://www.eventbrite.com/e/birding-the-park-at-expo-idaho-registration-2003380234210'
    $event.sources[0].name | Should -Be 'eventbrite-emmett'
  }

  It 'reads the cost tier from each event page' {
    $pages = @(Get-Fixture 'emmett.html'; Get-Fixture 'event-free.html'; New-OfferPage '35.0')
    $priced = @(& $adapter -Source $source -FetchedAt $fetchedAt -Response $pages)
    $priced[0].cost | Should -BeExactly 'free'
    $priced[1].cost | Should -BeExactly '$$'
    $priced[2].PSObject.Properties.Name | Should -Not -Contain 'cost'
  }

  It 'fails when the page has no event data' {
    { & $adapter -Source $source -FetchedAt $fetchedAt -Response @('<html></html>') } | Should -Throw '*__SERVER_DATA__*'
  }
}
