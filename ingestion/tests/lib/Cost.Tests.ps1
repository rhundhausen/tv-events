BeforeAll {
  . "$PSScriptRoot/../../scripts/lib/Dedupe.ps1"

  function New-TestEvent {
    param(
      [string]$Title = 'Test Show',
      [string]$Venue = 'Test Hall',
      [string]$Category = 'music',
      [string]$Source = 'a',
      [string]$Description,
      [string]$Cost
    )
    New-TvEvent -Title $Title -Start '2026-11-14T19:30:00-07:00' -Venue $Venue -Category $Category -Url "https://$Source.test/e" `
      -Description $Description -Cost $Cost -Sources @(@{ name = $Source; url = "https://$Source.test/e"; fetchedAt = '2026-11-01T10:00:00Z' })
  }
}

Describe 'Get-TvCostTier' {
  It 'maps <amount> to <want>' -ForEach @(
    @{ amount = 0; want = 'free' }
    @{ amount = 24.99; want = '$' }
    @{ amount = 25; want = '$$' }
    @{ amount = 99.99; want = '$$' }
    @{ amount = 100; want = '$$$' }
  ) {
    Get-TvCostTier -Amount $amount | Should -BeExactly $want
  }
}

Describe 'ConvertFrom-TvCostText' {
  It 'reads "<text>" as <want>' -ForEach @(
    @{ text = 'Free'; want = 'free' }
    @{ text = '$0'; want = 'free' }
    @{ text = '$32.75'; want = '$$' }
    @{ text = '$10 - $20'; want = '$' }
    @{ text = 'Free - $20'; want = 'free' }
    @{ text = '$0 - $15'; want = 'free' }
    @{ text = '$1,250'; want = '$$$' }
    @{ text = '$10 suggested'; want = '$' }
    @{ text = '25'; want = '$$' }
  ) {
    ConvertFrom-TvCostText $text | Should -BeExactly $want
  }

  It 'gives nothing for "<text>"' -ForEach @(
    @{ text = 'Donation' }
    @{ text = 'Varies' }
    @{ text = '' }
    @{ text = $null }
  ) {
    ConvertFrom-TvCostText $text | Should -BeNullOrEmpty
  }
}

Describe 'New-TvEvent cost' {
  It 'takes the tier from a dollar amount in the description, and still drops that sentence' {
    $event = New-TestEvent -Description 'A great night. Tickets are $45.'
    $event.cost | Should -BeExactly '$$'
    $event.description | Should -Be 'A great night.'
  }

  It 'counts a free-admission event as free' {
    (New-TestEvent -Title 'Free Admission Day').cost | Should -BeExactly 'free'
  }

  It 'prefers the source tier over the text' {
    (New-TestEvent -Title 'Free Admission Day' -Description 'Tickets are $45.' -Cost '$$$').cost | Should -BeExactly '$$$'
  }

  It 'leaves cost out when nothing says' {
    (New-TestEvent).PSObject.Properties.Name | Should -Not -Contain 'cost'
  }

  It 'is valid with a cost' {
    Test-TvEvent (New-TestEvent -Cost '$') | Should -BeTrue
  }
}

Describe 'Set-TvCostGuess' {
  It 'guesses free for a library source' {
    $event = New-TestEvent -Source 'nampa-public-library' -Category 'learning-business'
    Set-TvCostGuess @($event)
    $event.costGuess | Should -BeExactly 'free'
  }

  It 'guesses $$ for a concert at a big arena' {
    $event = New-TestEvent -Venue 'ExtraMile Arena' -Category 'music'
    Set-TvCostGuess @($event)
    $event.costGuess | Should -BeExactly '$$'
  }

  It 'does not use the arena rule for other categories' {
    $event = New-TestEvent -Venue 'ExtraMile Arena' -Category 'community-civic'
    Set-TvCostGuess @($event)
    $event.PSObject.Properties.Name | Should -Not -Contain 'costGuess'
  }

  It 'adds no guess when the event has a real cost, and removes an old one' {
    $event = New-TestEvent -Source 'nampa-public-library' -Cost '$'
    $event | Add-Member -NotePropertyName costGuess -NotePropertyValue 'free'
    Set-TvCostGuess @($event)
    $event.PSObject.Properties.Name | Should -Not -Contain 'costGuess'
  }

  It 'keeps the event valid' {
    $event = New-TestEvent -Source 'nampa-public-library'
    Set-TvCostGuess @($event)
    Test-TvEvent $event | Should -BeTrue
  }
}

Describe 'Merge-TvEvents cost' {
  It 'takes the cost from a lower-priority duplicate when the best one has none' {
    $merged = @(Merge-TvEvents @((New-TestEvent -Source a), (New-TestEvent -Source b -Cost '$$')) -Priorities @{ a = 10; b = 90 })
    $merged.Count | Should -Be 1
    $merged[0].url | Should -Be 'https://a.test/e'
    $merged[0].cost | Should -BeExactly '$$'
  }

  It 'keeps the best source''s own cost' {
    $merged = @(Merge-TvEvents @((New-TestEvent -Source a -Cost '$'), (New-TestEvent -Source b -Cost '$$')) -Priorities @{ a = 10; b = 90 })
    $merged[0].cost | Should -BeExactly '$'
  }
}
