BeforeAll {
  . "$PSScriptRoot/../../scripts/lib/Scrape.ps1"
}

Describe 'Test-TvRobotsAllowed' {
  It 'allows everything with no robots.txt' {
    Test-TvRobotsAllowed '' '/events/' | Should -BeTrue
  }

  It 'treats an empty Disallow as allowing everything' {
    Test-TvRobotsAllowed "User-agent: *`nDisallow:" '/events/' | Should -BeTrue
  }

  It 'blocks a matching prefix' {
    $robots = "User-agent: *`nDisallow: /private/"
    Test-TvRobotsAllowed $robots '/private/page' | Should -BeFalse
    Test-TvRobotsAllowed $robots '/events/' | Should -BeTrue
  }

  It 'blocks the whole site with /' {
    Test-TvRobotsAllowed "User-agent: *`nDisallow: /" '/events/' | Should -BeFalse
  }

  It 'keeps a wildcard from blocking everything' {
    $robots = "User-agent: *`nDisallow: /*?format=json`nDisallow: /*?format=ical"
    Test-TvRobotsAllowed $robots '/calendar' | Should -BeTrue
    Test-TvRobotsAllowed $robots '/calendar?format=ical' | Should -BeFalse
    Test-TvRobotsAllowed $robots '/calendar?format=json' | Should -BeFalse
  }

  It 'honors an end anchor' {
    $robots = "User-agent: *`nDisallow: /*.pdf$"
    Test-TvRobotsAllowed $robots '/a.pdf' | Should -BeFalse
    Test-TvRobotsAllowed $robots '/a.pdf?x=1' | Should -BeTrue
  }

  It 'lets the longest rule win' {
    $robots = "User-agent: *`nDisallow: /events/`nAllow: /events/public/"
    Test-TvRobotsAllowed $robots '/events/public/a' | Should -BeTrue
    Test-TvRobotsAllowed $robots '/events/private/a' | Should -BeFalse
  }

  It 'lets Allow win a tie' {
    Test-TvRobotsAllowed "User-agent: *`nDisallow: /a`nAllow: /a" '/a' | Should -BeTrue
  }

  It 'ignores groups for other agents' {
    Test-TvRobotsAllowed "User-agent: Googlebot`nDisallow: /" '/events/' | Should -BeTrue
  }

  It 'prefers a group naming us over *' {
    $robots = "User-agent: *`nDisallow: /`n`nUser-agent: WeekendBoise`nDisallow: /private/"
    Test-TvRobotsAllowed $robots '/events/' | Should -BeTrue
  }

  It 'obeys a group naming us' {
    $robots = "User-agent: *`nDisallow:`n`nUser-agent: WeekendBoise`nDisallow: /"
    Test-TvRobotsAllowed $robots '/events/' | Should -BeFalse
  }

  It 'applies shared rules to agents listed together' {
    $robots = "User-agent: Googlebot`nUser-agent: *`nDisallow: /x/"
    Test-TvRobotsAllowed $robots '/x/a' | Should -BeFalse
  }

  It 'ignores comments' {
    Test-TvRobotsAllowed "User-agent: * # all`nDisallow: /x/ # hidden" '/x/a' | Should -BeFalse
  }
}

Describe 'Get-TvRobotsGroup' {
  It 'reads Crawl-delay from our group' {
    (Get-TvRobotsGroup "User-agent: *`nCrawl-delay: 10`n`nUser-agent: Siteimprove`nCrawl-delay: 20").Delay | Should -Be 10
  }
}

Describe 'Get-TvJsonLdEvent' {
  It 'finds a single event' {
    $html = '<script type="application/ld+json">{"@type":"Event","name":"Show"}</script>'
    (Get-TvJsonLdEvent $html).name | Should -Be 'Show'
  }

  It 'finds events in an array and in @graph' {
    $html = '<script type="application/ld+json">[{"@type":"Event","name":"A"},{"@type":"Thing"}]</script>' +
    '<script type="application/ld+json">{"@graph":[{"@type":"MusicEvent","name":"B"}]}</script>'
    (Get-TvJsonLdEvent $html).name | Should -Be @('A', 'B')
  }

  It 'ignores other types' {
    @(Get-TvJsonLdEvent '<script type="application/ld+json">{"@type":"Organization"}</script>').Count | Should -Be 0
  }

  It 'skips a broken block and keeps reading' {
    $html = '<script type="application/ld+json">{broken</script><script type="application/ld+json">{"@type":"Event","name":"Good"}</script>'
    (Get-TvJsonLdEvent $html).name | Should -Be 'Good'
  }

  It 'returns nothing for a page with no data' {
    @(Get-TvJsonLdEvent '<html></html>').Count | Should -Be 0
  }
}
