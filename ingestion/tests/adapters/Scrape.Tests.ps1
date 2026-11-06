BeforeAll {
  $script:repo = Join-Path $PSScriptRoot '..' '..'
  $script:adapter = Join-Path $repo 'scripts' 'adapters' 'scrape.ps1'
  $script:sources = (Get-Content (Join-Path $repo 'sources.json') -Raw | ConvertFrom-Json).sources
  $script:fetchedAt = '2026-11-02T10:00:00Z'

  . (Join-Path $repo 'scripts' 'lib' 'Schema.ps1')

  function Get-TestSource {
    param([string]$Name)
    $sources | Where-Object name -eq $Name
  }

  function Get-Fixture {
    param([string]$Name)
    Get-Content (Join-Path $repo 'tests' 'fixtures' 'scrape' $Name) -Raw
  }

  function New-FakeResponse {
    param([int]$Status, [string]$Body = '')
    [pscustomobject]@{
      StatusCode       = $Status
      RawContentStream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Body))
    }
  }
}

Describe 'scrape adapter, jsonld from the list page' {
  BeforeAll {
    $events = @(& $adapter -Source (Get-TestSource 'visit-boise') -FetchedAt $fetchedAt -Response (Get-Fixture 'visit-boise.html'))
  }

  It 'reads every event' {
    $events.Count | Should -Be 12
  }

  It 'reads a price from the offers, and ignores a price of 0, which sites use as a placeholder' {
    $html = { param($offers) "<script type=`"application/ld+json`">{`"@type`":`"Event`",`"name`":`"Priced Show`",`"startDate`":`"2026-11-20T19:00:00-07:00`",`"location`":{`"name`":`"Test Hall`"},`"offers`":$offers}</script>" }
    $source = Get-TestSource 'visit-boise'
    (& $adapter -Source $source -FetchedAt $fetchedAt -Response (& $html '{"price":"45","priceCurrency":"USD"}')).cost | Should -BeExactly '$$'
    (& $adapter -Source $source -FetchedAt $fetchedAt -Response (& $html '[{"lowPrice":12,"highPrice":30}]')).cost | Should -BeExactly '$'
    (& $adapter -Source $source -FetchedAt $fetchedAt -Response (& $html '{"price":"0"}')).PSObject.Properties.Name | Should -Not -Contain 'cost'
  }

  It 'corrects times written as UTC, matching what the site displays' {
    $events[0].title | Should -Be 'Distillery Tour'
    $events[0].start | Should -Be '2026-11-02T11:00:00-07:00'
    $events[0].end | Should -Be '2026-11-02T20:00:00-07:00'
  }

  It 'reads the venue and city' {
    $events[0].venue | Should -Be 'Bardenay Distilling Co.'
    $events[0].venueKey | Should -Be 'bardenay-distilling-co'
    $events[0].city | Should -Be 'Boise'
  }

  It 'infers the category' {
    $events[0].category | Should -Be 'food-drink'
  }

  It 'decodes entities in urls' {
    $events.url | Where-Object { $_ -match '&#' } | Should -BeNullOrEmpty
  }
}

Describe 'scrape adapter, jsonld from linked pages' {
  BeforeAll {
    $source = Get-TestSource 'indian-creek-plaza'
    $list = '<a href="/calendar/2026/10/10/past-event">x</a><a href="/calendar/2026/11/20/winter-wonderland-festival">a</a><a href="/calendar/2026/11/20/winter-wonderland-festival">b</a>'
    $events = @(& $adapter -Source $source -FetchedAt $fetchedAt -Response @($list, (Get-Fixture 'indian-creek-plaza-event.html')))
  }

  It 'skips past dates and repeated links' {
    $events.Count | Should -Be 1
  }

  It 'makes the link absolute and uses it as the url' {
    $events[0].url | Should -Be 'https://indiancreekplaza.com/calendar/2026/11/20/winter-wonderland-festival'
  }

  It 'removes the site name from the title' {
    $events[0].title | Should -Be 'Winter Wonderland Festival'
  }

  It 'reads an offset with no colon' {
    $events[0].start | Should -Be '2026-11-20T18:00:00-07:00'
  }

  It 'uses the fixed venue' {
    $events[0].venueKey | Should -Be 'indian-creek-plaza'
    $events[0].city | Should -Be 'Caldwell'
  }

  It 'caps the pages it reads' {
    $capped = $source | Select-Object *
    $capped | Add-Member -NotePropertyName maxPages -NotePropertyValue 1 -Force
    $links = '<a href="/calendar/2026/11/20/a">x</a><a href="/calendar/2026/11/21/b">y</a>'
    $page = Get-Fixture 'indian-creek-plaza-event.html'
    @(& $adapter -Source $capped -FetchedAt $fetchedAt -Response @($links, $page, $page) -WarningAction SilentlyContinue).Count | Should -Be 1
  }
}

Describe 'scrape adapter, event states' {
  BeforeAll {
    $source = [pscustomobject]@{
      name = 'test'; displayName = 'Test'; adapter = 'scrape'; url = 'https://x.test/events/'; category = 'music'; city = 'Boise'
      venue = 'Hall'; venueKey = 'hall'; enabled = $true; scrapeMode = 'jsonld'
    }
    function Invoke-WithNode {
      param([string]$Json)
      @(& $adapter -Source $source -FetchedAt $fetchedAt -Response "<script type=`"application/ld+json`">$Json</script>" -WarningAction SilentlyContinue)
    }
  }

  It 'skips a cancelled event' {
    @(Invoke-WithNode '{"@type":"Event","name":"Gone","startDate":"2026-11-20T19:00:00-07:00","eventStatus":"https://schema.org/EventCancelled"}').Count | Should -Be 0
  }

  It 'skips an event with an unreadable date' {
    @(Invoke-WithNode '{"@type":"Event","name":"Odd","startDate":"sometime soon"}').Count | Should -Be 0
  }

  It 'reads a date-only event as all day' {
    $event = (Invoke-WithNode '{"@type":"Event","name":"Fair","startDate":"2026-11-20"}')[0]
    $event.allDay | Should -BeTrue
    $event.start | Should -Be '2026-11-20'
  }

  It 'leaves correct times alone without localTimeAsUtc' {
    (Invoke-WithNode '{"@type":"Event","name":"Show","startDate":"2026-11-20T19:00:00-07:00"}')[0].start | Should -Be '2026-11-20T19:00:00-07:00'
  }

  It 'drops an end that is not after the start' {
    $event = (Invoke-WithNode '{"@type":"Event","name":"Show","startDate":"2026-11-20T19:00:00-07:00","endDate":"2026-11-20T19:00:00-07:00"}')[0]
    $event.PSObject.Properties.Name | Should -Not -Contain 'end'
  }

  It 'falls back to the source venue with no location' {
    (Invoke-WithNode '{"@type":"Event","name":"Show","startDate":"2026-11-20T19:00:00-07:00"}')[0].venueKey | Should -Be 'hall'
  }

  It 'rejects an unknown mode' {
    $bad = $source | Select-Object *
    $bad.scrapeMode = 'guess'
    { & $adapter -Source $bad -FetchedAt $fetchedAt -Response 'x' } | Should -Throw '*unknown scrapeMode*'
  }
}

Describe 'scrape adapter, cards' {
  BeforeAll {
    $events = @(& $adapter -Source (Get-TestSource 'boise-centre') -FetchedAt $fetchedAt -Response (Get-Fixture 'boise-centre.html'))
  }

  It 'keeps public events and skips conventions and meetings' {
    $events.Count | Should -Be 1
  }

  It 'reads an all-day date range' {
    $events[0].title | Should -Be '2026 Festival of Trees'
    $events[0].allDay | Should -BeTrue
    $events[0].start | Should -Be '2026-11-24'
    $events[0].end | Should -Be '2026-11-30'
  }

  It 'uses the fixed venue and the link on the card' {
    $events[0].venueKey | Should -Be 'boise-centre'
    $events[0].url | Should -BeLike 'https://www.saintalphonsus.org/*'
  }

  It 'moves a date in an early month to next year' {
    $html = '<article class="event-card public"><span class="month">Jan</span> <span class="day">15</span><h3>Winter Show</h3></article>'
    $event = & $adapter -Source (Get-TestSource 'boise-centre') -FetchedAt $fetchedAt -Response $html
    $event.start | Should -Be '2027-01-15'
  }
}

Describe 'scrape adapter, cards with custom patterns' {
  BeforeAll {
    $jump = Get-TestSource 'jump-boise'
    $events = @(& $adapter -Source $jump -FetchedAt $fetchedAt -Response (Get-Fixture 'jump-boise.html'))
  }

  It 'reads every card' {
    $events.Count | Should -Be 3
  }

  It 'reads the title with titlePattern and the date with datePattern' {
    $events[0].title | Should -Be 'StoryCorps: Remembrance Stories'
    $events[2].title | Should -Be 'Tractor Tours'
    $events[2].start | Should -BeLike '2026-11-04T*'
  }

  It 'reads start and end times with timePattern' {
    $events[0].allDay | Should -BeFalse
    $events[0].start | Should -Be '2026-11-03T15:00:00-07:00'
    $events[0].end | Should -Be '2026-11-03T18:00:00-07:00'
    $events[2].start | Should -Be '2026-11-04T12:00:00-07:00'
    $events[2].end | Should -Be '2026-11-04T13:30:00-07:00'
  }

  It 'uses the fixed venue and the detail link' {
    $events[0].venueKey | Should -Be 'jump'
    $events[0].url | Should -Be 'https://jumpboise.org/events/storycorps-remembrance-stories'
  }

  It 'falls back to an all-day event when a card has no time' {
    $html = '<div class="event flex"><p class="text-xs">Dec</p><p class="relative">06</p><p class="font-bold text-black">Holiday Market</p><a href="/events/market">View Details</a></div>'
    $event = & $adapter -Source $jump -FetchedAt $fetchedAt -Response $html
    $event.allDay | Should -BeTrue
    $event.start | Should -Be '2026-12-06'
  }

  It 'reads a start time with no end and no minutes' {
    $html = '<div class="event flex"><p class="text-xs">Dec</p><p class="relative">6</p><p class="font-bold text-black">Late Show</p><p>Time: 7 pm</p><a href="/events/late">View Details</a></div>'
    $event = & $adapter -Source $jump -FetchedAt $fetchedAt -Response $html
    $event.start | Should -Be '2026-12-06T19:00:00-07:00'
    $event.PSObject.Properties.Name | Should -Not -Contain 'end'
  }

  It 'reads 12 pm as noon and 12 am as midnight' {
    $noon = '<div class="event flex"><p class="text-xs">Dec</p><p class="relative">6</p><p class="font-bold text-black">A</p><p>Time: 12:00 pm - 12:30 pm</p>View Details</a></div>'
    (& $adapter -Source $jump -FetchedAt $fetchedAt -Response $noon).start | Should -Be '2026-12-06T12:00:00-07:00'
    $midnight = $noon -replace '12:00 pm - 12:30 pm', '12:00 am'
    (& $adapter -Source $jump -FetchedAt $fetchedAt -Response $midnight).start | Should -Be '2026-12-06T00:00:00-07:00'
  }

  It 'skips a card with no title' {
    $html = '<div class="event flex"><p class="text-xs">Dec</p><p class="relative">6</p><a href="/x">View Details</a></div>'
    @(& $adapter -Source $jump -FetchedAt $fetchedAt -Response $html -WarningAction SilentlyContinue).Count | Should -Be 0
  }
}

Describe 'scrape adapter, calendarapp' {
  BeforeAll {
    $events = @(& $adapter -Source (Get-TestSource 'boise-arts-history') -FetchedAt '2026-11-03T18:00:00Z' -Response (Get-Fixture 'boise-arts-history.html'))
  }

  It 'reads upcoming events and skips past ones' {
    $events.Count | Should -Be 2
    $events.title | Should -Not -Contain 'Boise Philharmonsters: A Spooky Symphony'
  }

  It 'reads the cost tier from the cost text' {
    $events[0].cost | Should -BeExactly 'free'
  }

  It 'reads start and end as Boise wall-clock time' {
    $events[0].title | Should -Be 'Open Arms Dance Project: Family Boogie'
    $events[0].start | Should -Be '2026-11-05T17:00:00-07:00'
    $events[0].end | Should -Be '2026-11-05T17:45:00-07:00'
  }

  It 'takes the venue from the location, without the address, and merges it with JUMP' {
    $events[0].venueKey | Should -Be 'jump'
    $events[0].venue | Should -Be 'JUMP'
  }

  It 'falls back to the source venue when the location is None' {
    $events[1].venueKey | Should -Be 'boise-arts-history'
  }

  It 'links each event page' {
    $events[0].url | Should -Be 'https://www.boiseartsandhistory.org/calendar/event?key=open-arms-dance-project-family-boogie_20261105'
  }

  It 'fails when the page has no calendar data' {
    { & $adapter -Source (Get-TestSource 'boise-arts-history') -FetchedAt $fetchedAt -Response '<html></html>' } | Should -Throw '*no #calendar-app*'
  }
}

Describe 'scrape adapter, civicplus' {
  BeforeAll {
    $source = Get-TestSource 'city-of-star'
    $html = Get-Fixture 'civicplus.html'
    # 2026-11-02 in Boise. Two pages, so the second month repeats the first and shows dedupe by event id.
    $events = @(& $adapter -Source $source -FetchedAt $fetchedAt -Response @($html, $html))
    $byTitle = @{}
    $events | ForEach-Object { $byTitle[$_.title] = $_ }
  }

  It 'skips meetings by title, past events, and repeats across months' {
    $events.title | Should -Be @('Veterans Day Potato Feed', 'HALO Teen Meetup', 'Kuna Arbor Day', 'Holiday Market')
  }

  It 'reads an all-day event as a date' {
    $byTitle['Veterans Day Potato Feed'].start | Should -Be '2026-11-06'
    $byTitle['Veterans Day Potato Feed'].allDay | Should -BeTrue
    $byTitle['Veterans Day Potato Feed'].description | Should -Be 'Baked potatoes for veterans and their families.'
  }

  It 'reads start and end times from the date line' {
    $byTitle['HALO Teen Meetup'].start | Should -Be '2026-11-24T18:30:00-07:00'
    $byTitle['HALO Teen Meetup'].end | Should -Be '2026-11-24T20:00:00-07:00'
  }

  It 'reads an event with no microdata' {
    $byTitle['Kuna Arbor Day'].start | Should -Be '2026-11-18T08:00:00-07:00'
    $byTitle['Kuna Arbor Day'].end | Should -Be '2026-11-18T17:00:00-07:00'
  }

  It 'reads a multi-day event' {
    $byTitle['Holiday Market'].start | Should -Be '2026-11-27'
    $byTitle['Holiday Market'].end | Should -Be '2026-11-29'
  }

  It 'uses a real place name, and the source venue for the placeholder' {
    $byTitle['HALO Teen Meetup'].venue | Should -Be 'Star Community Center'
    $byTitle['Veterans Day Potato Feed'].venueKey | Should -Be 'city-of-star'
    $byTitle['Veterans Day Potato Feed'].city | Should -Be 'Star'
  }

  It 'links the event by id' {
    $byTitle['Veterans Day Potato Feed'].url | Should -Be 'https://www.staridaho.org/Calendar.aspx?EID=539'
  }
}

Describe 'ics adapter, excludeTitlePattern' {
  It 'skips matching titles' {
    $source = Get-TestSource 'mountain-home-library'
    $feed = "BEGIN:VCALENDAR`r`nBEGIN:VEVENT`r`nUID:1`r`nSUMMARY:CLOSED for Thanksgiving Day Holiday`r`nDTSTART;VALUE=DATE:20261126`r`nEND:VEVENT`r`nBEGIN:VEVENT`r`nUID:2`r`nSUMMARY:Chess Club`r`nDTSTART:20261110T230000Z`r`nEND:VEVENT`r`nEND:VCALENDAR`r`n"
    $events = @(& (Join-Path $repo 'scripts' 'adapters' 'ics.ps1') -Source $source -FetchedAt $fetchedAt -Response $feed)
    $events.title | Should -Be @('Chess Club')
    $events[0].city | Should -Be 'Mountain Home'
  }
}

Describe 'scrape adapter, staying out of bounds' {
  BeforeAll {
    $source = Get-TestSource 'indian-creek-plaza'
  }

  BeforeEach {
    $global:TvScrapeRequests = [System.Collections.Generic.List[string]]::new()
  }

  AfterAll {
    Remove-Variable -Name TvScrapeRequests -Scope Global -ErrorAction SilentlyContinue
  }

  It 'sends no page request when robots.txt disallows the list page' {
    Mock Invoke-WebRequest {
      $global:TvScrapeRequests.Add("$Uri")
      New-FakeResponse 200 "User-agent: *`nDisallow: /calendar"
    }
    { & $adapter -Source $source -FetchedAt $fetchedAt } | Should -Throw '*robots.txt disallows*'
    $global:TvScrapeRequests | Should -Be @('https://indiancreekplaza.com/robots.txt')
  }

  It 'stops before a disallowed event page' {
    Mock Invoke-WebRequest {
      $global:TvScrapeRequests.Add("$Uri")
      if ("$Uri" -like '*/robots.txt') { New-FakeResponse 200 "User-agent: *`nDisallow: /calendar/2026/" }
      else { New-FakeResponse 200 '<a href="/calendar/2026/12/1/event">x</a>' }
    }
    Mock Start-Sleep {}
    { & $adapter -Source $source -FetchedAt $fetchedAt } | Should -Throw '*robots.txt disallows*'
    $global:TvScrapeRequests | Should -Not -Contain 'https://indiancreekplaza.com/calendar/2026/12/1/event'
  }

  It 'obeys a site that names us' {
    Mock Invoke-WebRequest {
      $global:TvScrapeRequests.Add("$Uri")
      New-FakeResponse 200 "User-agent: WeekendBoise`nDisallow: /"
    }
    { & $adapter -Source $source -FetchedAt $fetchedAt } | Should -Throw '*robots.txt disallows*'
    $global:TvScrapeRequests.Count | Should -Be 1
  }

  It 'fails on a 403 and does not try again' {
    Mock Invoke-WebRequest {
      $global:TvScrapeRequests.Add("$Uri")
      if ("$Uri" -like '*/robots.txt') { New-FakeResponse 404 } else { New-FakeResponse 403 'Just a moment...' }
    }
    { & $adapter -Source $source -FetchedAt $fetchedAt } | Should -Throw '*HTTP 403*'
    $global:TvScrapeRequests.Count | Should -Be 2
  }

  It 'stops when robots.txt can not be read, because it can not tell what is allowed' {
    Mock Invoke-WebRequest {
      $global:TvScrapeRequests.Add("$Uri")
      New-FakeResponse 403
    }
    { & $adapter -Source $source -FetchedAt $fetchedAt } | Should -Throw '*HTTP 403*'
    $global:TvScrapeRequests.Count | Should -Be 1
  }

  It 'treats a missing robots.txt as no restrictions' {
    Mock Invoke-WebRequest {
      $global:TvScrapeRequests.Add("$Uri")
      if ("$Uri" -like '*/robots.txt') { New-FakeResponse 404 } else { New-FakeResponse 200 '<html></html>' }
    }
    @(& $adapter -Source $source -FetchedAt $fetchedAt).Count | Should -Be 0
    $global:TvScrapeRequests.Count | Should -Be 2
  }

  It 'waits the Crawl-delay between pages, at least 1 second' {
    Mock Invoke-WebRequest {
      if ("$Uri" -like '*/robots.txt') { New-FakeResponse 200 "User-agent: *`nCrawl-delay: 7" }
      else { New-FakeResponse 200 '<a href="/calendar/2026/12/1/event">x</a>' }
    }
    Mock Start-Sleep {}
    $null = & $adapter -Source $source -FetchedAt $fetchedAt
    Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
  }

  It 'fails rather than stalling or ignoring a very long Crawl-delay' {
    Mock Invoke-WebRequest {
      $global:TvScrapeRequests.Add("$Uri")
      New-FakeResponse 200 "User-agent: *`nCrawl-delay: 600"
    }
    Mock Start-Sleep {}
    { & $adapter -Source $source -FetchedAt $fetchedAt } | Should -Throw '*600 seconds between requests*'
    $global:TvScrapeRequests.Count | Should -Be 1
    Should -Invoke Start-Sleep -Times 0 -Exactly
  }

  It 'waits 1 second when the site sets no delay' {
    Mock Invoke-WebRequest {
      if ("$Uri" -like '*/robots.txt') { New-FakeResponse 404 }
      else { New-FakeResponse 200 '<a href="/calendar/2026/12/1/event">x</a>' }
    }
    Mock Start-Sleep {}
    $null = & $adapter -Source $source -FetchedAt $fetchedAt
    Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
  }

  It 'keeps a bad page from stopping the others' {
    Mock Invoke-WebRequest {
      if ("$Uri" -like '*/robots.txt') { New-FakeResponse 404 }
      elseif ("$Uri" -like '*/calendar') { New-FakeResponse 200 '<a href="/calendar/2026/12/1/bad">x</a><a href="/calendar/2026/12/2/good">y</a>' }
      elseif ("$Uri" -like '*/bad') { New-FakeResponse 500 }
      else { New-FakeResponse 200 '<script type="application/ld+json">{"@type":"Event","name":"Good","startDate":"2026-12-02T19:00:00-07:00"}</script>' }
    }
    Mock Start-Sleep {}
    $events = @(& $adapter -Source $source -FetchedAt $fetchedAt -WarningAction SilentlyContinue)
    $events.title | Should -Be 'Good'
  }
}
