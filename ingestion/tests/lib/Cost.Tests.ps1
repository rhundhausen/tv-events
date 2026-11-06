BeforeAll {
  . "$PSScriptRoot/../../scripts/lib/Dedupe.ps1"

  function New-TestEvent {
    param(
      [string]$Title = 'Test Show',
      [string]$Venue = 'Test Hall',
      [string]$Category = 'music',
      [string]$Source = 'a',
      [string]$Description,
      [AllowNull()][Nullable[decimal]]$PriceMin
    )
    New-TvEvent -Title $Title -Start '2026-11-14T19:30:00-07:00' -Venue $Venue -Category $Category -Url "https://$Source.test/e" `
      -Description $Description -PriceMin $PriceMin -Sources @(@{ name = $Source; url = "https://$Source.test/e"; fetchedAt = '2026-11-01T10:00:00Z' })
  }
}

Describe 'Get-CostTier' {
  It 'maps <price> to <want>' -ForEach @(
    @{ price = 0; want = 'free' }
    @{ price = 0.01; want = '$' }
    @{ price = 14.99; want = '$' }
    @{ price = 15; want = '$$' }
    @{ price = 39.99; want = '$$' }
    @{ price = 40; want = '$$$' }
    @{ price = 1250; want = '$$$' }
  ) {
    Get-CostTier -PriceMin $price | Should -BeExactly $want
  }

  It 'gives null for an unknown price' {
    Get-CostTier -PriceMin $null | Should -BeNullOrEmpty
  }

  It 'treats a negative price as unknown' {
    Get-CostTier -PriceMin -5 | Should -BeNullOrEmpty
  }

  It 'takes its breakpoints from the one config block' {
    $saved = $script:CostTierBreakpoints
    try {
      $script:CostTierBreakpoints = @{ Low = 20; High = 50 }
      Get-CostTier -PriceMin 15 | Should -BeExactly '$'
      Get-CostTier -PriceMin 45 | Should -BeExactly '$$'
    } finally {
      $script:CostTierBreakpoints = $saved
    }
  }
}

Describe 'ConvertFrom-TvPriceText' {
  It 'reads "<text>" as <want>' -ForEach @(
    @{ text = 'Free'; want = 0 }
    @{ text = '$0'; want = 0 }
    @{ text = '$32.75'; want = 32.75 }
    @{ text = '$10 - $20'; want = 10 }
    @{ text = '$10 to $60'; want = 10 }
    @{ text = 'Free - $20'; want = 0 }
    @{ text = '$1,250'; want = 1250 }
    @{ text = '25'; want = 25 }
    # Cheapest adult ticket: kids, senior, student, and member prices don't count.
    @{ text = '$15 adults, $10 kids'; want = 15 }
    @{ text = '$12 students / $20 general admission'; want = 20 }
    @{ text = '$30 members, $40 nonmembers'; want = 40 }
    @{ text = 'Free for kids under 12, $10 adults'; want = 10 }
    @{ text = '$15 for Adults/FREE for Youth 18 & under.'; want = 15 }
    # No clear adult price: the lowest listed.
    @{ text = 'Seniors $8, children $5'; want = 5 }
    # Face value: fees are not the ticket.
    @{ text = '$25 + fees'; want = 25 }
    @{ text = '$25 plus a $3.50 service fee'; want = 25 }
    # Donations and free entry with paid extras are free.
    @{ text = 'Suggested donation $10'; want = 0 }
    @{ text = 'Pay what you can'; want = 0 }
    @{ text = 'Free admission, parking $5'; want = 0 }
    # A pass with no single-day price is the pass price.
    @{ text = 'Season pass $120'; want = 120 }
  ) {
    ConvertFrom-TvPriceText $text | Should -Be $want
  }

  It 'gives null for "<text>"' -ForEach @(
    @{ text = 'Tickets at the door' }
    @{ text = 'See website' }
    @{ text = 'Varies' }
    @{ text = 'Parking is $5' }
    @{ text = '' }
    @{ text = $null }
  ) {
    ConvertFrom-TvPriceText $text | Should -BeNullOrEmpty
  }

  It 'ignores the word free in prose, where it rarely means the price' {
    ConvertFrom-TvPriceText 'Feel free to bring a chair.' -Prose | Should -BeNullOrEmpty
    ConvertFrom-TvPriceText 'Feel free to bring a chair. Tickets are $18.' -Prose | Should -Be 18
  }
}

Describe 'New-TvEvent costTier' {
  It 'derives the tier from the price the source gave' {
    (New-TestEvent -PriceMin 39.99).costTier | Should -BeExactly '$$'
  }

  It 'never stores the price' {
    $event = New-TestEvent -PriceMin 25 -Description 'A great night. Tickets are $45.'
    $event.PSObject.Properties.Name | Should -Not -Contain 'priceMin'
    $event.description | Should -Be 'A great night.'
  }

  It 'reads a dollar amount in the description when the source gave no price' {
    (New-TestEvent -Description 'A great night. Tickets are $45.').costTier | Should -BeExactly '$$$'
  }

  It 'counts a free-admission event as free' {
    (New-TestEvent -Title 'Free Admission Day').costTier | Should -BeExactly 'free'
  }

  It 'prefers the source price over the text' {
    (New-TestEvent -Title 'Free Admission Day' -Description 'Tickets are $45.' -PriceMin 12).costTier | Should -BeExactly '$'
  }

  It 'leaves costTier out when nothing gives a price' {
    $names = (New-TestEvent).PSObject.Properties.Name
    $names | Should -Not -Contain 'costTier'
    $names | Should -Not -Contain 'cost'
  }

  It 'is valid with a tier' {
    Test-TvEvent (New-TestEvent -PriceMin 5) | Should -BeTrue
  }
}

Describe 'Update-TvLegacyCost' {
  It 'keeps the old tiers that mean the same under the new breakpoints, and drops the rest' {
    $events = @(
      [pscustomobject]@{ id = 'a'; cost = 'free' }
      [pscustomobject]@{ id = 'b'; cost = '$$$' }
      [pscustomobject]@{ id = 'c'; cost = '$' }
      [pscustomobject]@{ id = 'd'; costGuess = '$$' }
      [pscustomobject]@{ id = 'e'; costTier = '$$' }
    )
    Update-TvLegacyCost $events | Should -Be 4
    $events[0].costTier | Should -BeExactly 'free'
    $events[1].costTier | Should -BeExactly '$$$'
    $events[2].PSObject.Properties.Name | Should -Not -Contain 'costTier'
    foreach ($event in $events) {
      $event.PSObject.Properties.Name | Should -Not -Contain 'cost'
      $event.PSObject.Properties.Name | Should -Not -Contain 'costGuess'
    }
    $events[4].costTier | Should -BeExactly '$$'
  }
}

Describe 'Get-TvCostTierCounts' {
  It 'counts each tier and unknown' {
    $counts = Get-TvCostTierCounts @(
      [pscustomobject]@{ costTier = 'free' }, [pscustomobject]@{ costTier = '$' }, [pscustomobject]@{ costTier = '$' },
      [pscustomobject]@{ id = 'x' }
    )
    $counts.free | Should -Be 1
    $counts.'$' | Should -Be 2
    $counts.'$$' | Should -Be 0
    $counts.'$$$' | Should -Be 0
    $counts.unknown | Should -Be 1
  }
}

Describe 'Merge-TvEvents costTier' {
  It 'takes the tier from a lower-priority duplicate when the best one has none' {
    $merged = @(Merge-TvEvents @((New-TestEvent -Source a), (New-TestEvent -Source b -PriceMin 30)) -Priorities @{ a = 10; b = 90 })
    $merged.Count | Should -Be 1
    $merged[0].url | Should -Be 'https://a.test/e'
    $merged[0].costTier | Should -BeExactly '$$'
  }

  It 'keeps the best source''s own tier' {
    $merged = @(Merge-TvEvents @((New-TestEvent -Source a -PriceMin 5), (New-TestEvent -Source b -PriceMin 30)) -Priorities @{ a = 10; b = 90 })
    $merged[0].costTier | Should -BeExactly '$'
  }
}
