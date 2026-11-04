BeforeAll {
  . "$PSScriptRoot/../../scripts/lib/Dedupe.ps1"

  function New-TestEvent {
    param(
      [string]$Title = 'Boise Philharmonic Season Opener',
      [string]$Start = '2026-11-14T19:30:00-07:00',
      [string]$Venue = 'Morrison Center',
      [string]$Source = 'a',
      [string]$Url = "https://$Source.test/e",
      [string]$Description,
      [string]$FetchedAt = '2026-11-01T10:00:00Z',
      [switch]$AllDay
    )
    New-TvEvent -Title $Title -Start $Start -Venue $Venue -Category 'music' -Url $Url -Description $Description -AllDay:$AllDay `
      -Sources @(@{ name = $Source; url = $Url; fetchedAt = $FetchedAt })
  }
}

Describe 'Get-JaroWinkler' {
  It 'scores <first> and <second>' -ForEach @(
    @{ first = 'MARTHA'; second = 'MARHTA'; want = 0.9611 }
    @{ first = 'DIXON'; second = 'DICKSONX'; want = 0.8133 }
    @{ first = 'DWAYNE'; second = 'DUANE'; want = 0.84 }
    @{ first = 'same'; second = 'same'; want = 1 }
    @{ first = 'abc'; second = 'xyz'; want = 0 }
    @{ first = ''; second = 'abc'; want = 0 }
  ) {
    Get-JaroWinkler $first $second | Should -BeLessOrEqual ($want + 0.0001)
    Get-JaroWinkler $first $second | Should -BeGreaterOrEqual ($want - 0.0001)
  }

  It 'is case sensitive' {
    Get-JaroWinkler 'ABC' 'abc' | Should -Be 0
  }
}

Describe 'Merge-TvEvents' {
  It 'merges events with the same id' {
    $merged = @(Merge-TvEvents @((New-TestEvent -Source a), (New-TestEvent -Source b)))
    $merged.Count | Should -Be 1
    $merged[0].sources.name | Should -Be @('a', 'b')
  }

  It 'merges similar titles at the same venue within 30 minutes' {
    $merged = @(Merge-TvEvents @(
        (New-TestEvent -Title 'Boise Philharmonic Season Opener' -Source a)
        (New-TestEvent -Title 'Boise Philharmonic Season Openers' -Start '2026-11-14T20:00:00-07:00' -Source b)
      ))
    $merged.Count | Should -Be 1
  }

  It 'keeps events 31 minutes apart' {
    $merged = @(Merge-TvEvents @(
        (New-TestEvent -Title 'Boise Philharmonic Season Opener' -Source a)
        (New-TestEvent -Title 'Boise Philharmonic Season Openers' -Start '2026-11-14T20:01:00-07:00' -Source b)
      ))
    $merged.Count | Should -Be 2
  }

  It 'merges across midnight' {
    $merged = @(Merge-TvEvents @(
        (New-TestEvent -Title 'New Years Eve Countdown Party' -Start '2026-12-31T23:50:00-07:00' -Source a)
        (New-TestEvent -Title 'New Years Eve Countdown Parties' -Start '2027-01-01T00:10:00-07:00' -Source b)
      ))
    $merged.Count | Should -Be 1
  }

  It 'keeps similar titles at different venues' {
    $merged = @(Merge-TvEvents @(
        (New-TestEvent -Title 'Boise Philharmonic Season Opener' -Venue 'Morrison Center')
        (New-TestEvent -Title 'Boise Philharmonic Season Openers' -Venue 'Egyptian Theatre')
      ))
    $merged.Count | Should -Be 2
  }

  It 'keeps different titles at the same time and venue' {
    $merged = @(Merge-TvEvents @((New-TestEvent -Title 'Comedy Night'), (New-TestEvent -Title 'Ballet Idaho Nutcracker')))
    $merged.Count | Should -Be 2
  }

  It 'keeps the longest description' {
    $merged = @(Merge-TvEvents @(
        (New-TestEvent -Source a -Description 'Short')
        (New-TestEvent -Source b -Description 'A much longer description')
      ) -Priorities @{ a = 1; b = 99 })
    $merged[0].description | Should -Be 'A much longer description'
  }

  It 'adds a description the preferred source lacks' {
    $merged = @(Merge-TvEvents @((New-TestEvent -Source a), (New-TestEvent -Source b -Description 'Only here')) -Priorities @{ a = 1; b = 99 })
    $merged[0].description | Should -Be 'Only here'
  }

  It 'prefers the url from the lowest priority number, whatever the input order' {
    $first = New-TestEvent -Source a
    $second = New-TestEvent -Source b
    (Merge-TvEvents @($first, $second) -Priorities @{ a = 10; b = 90 }).url | Should -Be 'https://a.test/e'
    (Merge-TvEvents @($second, $first) -Priorities @{ a = 10; b = 90 }).url | Should -Be 'https://a.test/e'
    (Merge-TvEvents @($first, $second) -Priorities @{ a = 90; b = 10 }).url | Should -Be 'https://b.test/e'
  }

  It 'treats a missing priority as 50' {
    (Merge-TvEvents @((New-TestEvent -Source a), (New-TestEvent -Source b)) -Priorities @{ b = 40 }).url | Should -Be 'https://b.test/e'
    (Merge-TvEvents @((New-TestEvent -Source a), (New-TestEvent -Source b)) -Priorities @{ b = 60 }).url | Should -Be 'https://a.test/e'
  }

  It 'unions sources with one entry per name and the earliest fetchedAt' {
    $merged = @(Merge-TvEvents @(
        (New-TestEvent -Source a -FetchedAt '2026-11-02T10:00:00Z')
        (New-TestEvent -Source a -FetchedAt '2026-11-01T10:00:00Z')
        (New-TestEvent -Source b)
      ))
    @($merged[0].sources).Count | Should -Be 2
    ($merged[0].sources | Where-Object name -eq 'a').fetchedAt | Should -Be '2026-11-01T10:00:00Z'
  }

  It 'merges three reports that chain together' {
    $merged = @(Merge-TvEvents @(
        (New-TestEvent -Source a)
        (New-TestEvent -Title 'Boise Philharmonic Season Openers' -Source b)
        (New-TestEvent -Source c)
      ))
    $merged.Count | Should -Be 1
    @($merged[0].sources).Count | Should -Be 3
  }

  It 'does not change its input' {
    $first = New-TestEvent -Source a
    $null = Merge-TvEvents @($first, (New-TestEvent -Source b -Description 'More'))
    @($first.sources).Count | Should -Be 1
    $first.PSObject.Properties.Name | Should -Not -Contain 'description'
  }

  It 'unions tags' {
    $first = New-TestEvent -Title 'Trivia Night' -Source a
    $second = New-TestEvent -Title 'Trivia Night' -Description 'Great for kids' -Source b
    @((Merge-TvEvents @($first, $second))[0].tags) | Should -Be @('kids', 'trivia')
  }

  It 'keeps a merged event valid when one report is all-day and one is timed' {
    $allDay = New-TestEvent -Start '2026-11-14' -AllDay -Source a
    $timed = New-TvEvent -Title 'Boise Philharmonic Season Opener' -Start '2026-11-14T10:00:00-07:00' -End '2026-11-14T16:00:00-07:00' `
      -Venue 'Morrison Center' -Category 'music' -Url 'https://b.test/e' -Sources @(@{ name = 'b'; url = 'https://b.test/e'; fetchedAt = '2026-11-01T10:00:00Z' })
    foreach ($priorities in @{ a = 1; b = 2 }, @{ a = 2; b = 1 }) {
      $merged = @(Merge-TvEvents @($allDay, $timed) -Priorities $priorities)
      $merged.Count | Should -Be 1
      Test-TvEvent $merged[0] | Should -BeTrue
    }
  }

  It 'handles all-day events' {
    $merged = @(Merge-TvEvents @(
        (New-TestEvent -Start '2026-11-14' -AllDay -Source a)
        (New-TestEvent -Start '2026-11-14' -AllDay -Source b)
      ))
    $merged.Count | Should -Be 1
  }

  It 'returns nothing for no events' {
    @(Merge-TvEvents @()).Count | Should -Be 0
  }
}
