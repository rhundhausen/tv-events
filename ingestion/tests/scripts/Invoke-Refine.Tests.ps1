BeforeAll {
  $script:refine = Join-Path $PSScriptRoot '..' '..' 'scripts' 'Invoke-Refine.ps1'
  . "$PSScriptRoot/../../scripts/lib/Raw.ps1"
  . "$PSScriptRoot/../../scripts/lib/Links.ps1"

  $script:now = '2026-11-15T12:00:00Z'

  function New-TestEvent {
    param(
      [string]$Title = 'Show',
      [string]$Start = '2026-11-20T19:30:00-07:00',
      [string]$Source = 'beta',
      [string]$Url = 'https://beta.test/show'
    )
    New-TvEvent -Title $Title -Start $Start -Venue 'Hall' -City 'Boise' -Category 'music' -Url $Url `
      -Sources @(@{ name = $Source; url = $Url; fetchedAt = '2026-11-15T07:01:00Z' })
  }

  function Write-TestRaw {
    param([hashtable]$Sources, [string]$AsOf = '2026-11-15T07:00:00Z')
    $results = foreach ($name in $Sources.Keys) { [pscustomobject]@{ Name = $name; Status = 'ok'; Events = @($Sources[$name]) } }
    $raw = Update-TvRawFile $null -Results @($results) -Keep @($Sources.Keys) -AsOf $AsOf -FetchedAt '2026-11-15T07:01:00Z'
    Write-TvRawFile $script:rawPath $raw
  }

  function Invoke-TestRefine {
    param([hashtable]$Options = @{})
    $null = & $refine -InputPath $script:rawPath -OutputPath $script:eventsPath -SourcesPath $script:sourcesPath `
      -OutDir (Join-Path $script:dir 'out') -Now $now -SkipLinkCheck -SkipCityLookup @Options *>&1
  }
}

Describe 'Invoke-Refine' {
  BeforeEach {
    $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $dir
    $script:rawPath = Join-Path $dir 'raw-events.json'
    $script:eventsPath = Join-Path $dir 'events.json'
    $script:sourcesPath = Join-Path $dir 'sources.json'
    $list = foreach ($name in 'nampa-public-library', 'beta', 'gamma') {
      [ordered]@{ name = $name; displayName = $name; status = 'running'; adapter = 'ics'; url = "https://$name.test"; priority = ($name -eq 'beta') ? 10 : 50 }
    }
    [ordered]@{ sources = @($list) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sourcesPath
  }

  It 'fails with a clear message when the raw file is missing' {
    { Invoke-TestRefine } | Should -Throw '*raw-events.json*ingest*'
  }

  It 'merges the sources, copies asOf to meta.json, and adds cost guesses' {
    Write-TestRaw @{
      'nampa-public-library' = @(New-TestEvent -Source 'nampa-public-library' -Url 'https://nampa.test/show'), (New-TestEvent -Title 'Story Time' -Source 'nampa-public-library' -Url 'https://nampa.test/story')
      beta                   = @(New-TestEvent)
    }
    Invoke-TestRefine
    $events = @(Read-TvEventFile $eventsPath)
    $events.Count | Should -Be 2
    $show = $events | Where-Object title -eq 'Show'
    @($show.sources.name) | Should -Be @('beta', 'nampa-public-library')
    $show.url | Should -Be 'https://beta.test/show'
    ($events | Where-Object title -eq 'Story Time').costGuess | Should -BeExactly 'free'
    (Get-Content (Join-Path $dir 'meta.json') -Raw | ConvertFrom-Json -DateKind String).lastIngest | Should -BeExactly '2026-11-15T07:00:00Z'
  }

  It 'breaks a priority tie by sources.json order, not by name' {
    $list = foreach ($name in 'zeta', 'alpha') {
      [ordered]@{ name = $name; displayName = $name; status = 'running'; adapter = 'ics'; url = "https://$name.test"; priority = 40 }
    }
    [ordered]@{ sources = @($list) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sourcesPath
    Write-TestRaw @{
      alpha = @(New-TestEvent -Source alpha -Url 'https://alpha.test/show')
      zeta  = @(New-TestEvent -Source zeta -Url 'https://zeta.test/show')
    }
    Invoke-TestRefine
    (Read-TvEventFile $eventsPath)[0].url | Should -Be 'https://zeta.test/show'
  }

  It 'moves past events to the archive' {
    Write-TestRaw @{ beta = @((New-TestEvent), (New-TestEvent -Title 'Last Week' -Start '2026-11-10T19:30:00-07:00' -Url 'https://beta.test/old')) }
    Invoke-TestRefine
    @(Read-TvEventFile $eventsPath).title | Should -Be @('Show')
    @(Read-TvEventFile (Join-Path $dir 'archive' '2026-11.json')).title | Should -Be @('Last Week')
  }

  It 'carries a running source''s upcoming events from events.json when the raw file has no entry for it' {
    Write-TvEventFile $eventsPath @(New-TestEvent -Title 'Gamma Gig' -Source gamma -Url 'https://gamma.test/gig')
    Write-TestRaw @{ beta = @(New-TestEvent) }
    Invoke-TestRefine
    @(Read-TvEventFile $eventsPath).title | Sort-Object | Should -Be @('Gamma Gig', 'Show')
  }

  It 'drops an event its source no longer reports' {
    Write-TestRaw @{ beta = @((New-TestEvent), (New-TestEvent -Title 'Canceled Later' -Url 'https://beta.test/later')) }
    Invoke-TestRefine
    Write-TestRaw @{ beta = @(New-TestEvent) }
    Invoke-TestRefine
    @(Read-TvEventFile $eventsPath).title | Should -Be @('Show')
  }

  It 'gives the same files when run twice' {
    Write-TestRaw @{ beta = @((New-TestEvent), (New-TestEvent -Title 'Last Week' -Start '2026-11-10T19:30:00-07:00' -Url 'https://beta.test/old')) }
    Invoke-TestRefine
    $first = Get-ChildItem -LiteralPath $dir -Recurse -File -Exclude 'refine.json', 'links.json' | Where-Object FullName -notlike '*out*' | ForEach-Object { "$($_.Name):$((Get-FileHash $_.FullName).Hash)" }
    Invoke-TestRefine
    $second = Get-ChildItem -LiteralPath $dir -Recurse -File -Exclude 'refine.json', 'links.json' | Where-Object FullName -notlike '*out*' | ForEach-Object { "$($_.Name):$((Get-FileHash $_.FullName).Hash)" }
    $second | Should -Be $first
  }

  It 'still applies known link results with -SkipLinkCheck' {
    $state = @{ 'https://beta.test/show' = [ordered]@{ verdict = 'broken'; status = 404; checkedAt = '2026-11-15T07:05:00Z'; failures = 0; brokenSince = '2026-11-14T07:05:00Z' } }
    Write-TvLinkState (Join-Path $dir 'links.json') $state
    Write-TestRaw @{ beta = @(New-TestEvent) }
    Invoke-TestRefine
    (Read-TvEventFile $eventsPath)[0].linkBroken | Should -BeTrue
  }

  It 'writes a run report to OutDir' {
    Write-TestRaw @{ beta = @(New-TestEvent) }
    Invoke-TestRefine
    $report = Get-Content (Join-Path $dir 'out' 'refine.json') -Raw | ConvertFrom-Json -DateKind String
    $report.asOf | Should -BeExactly '2026-11-15T07:00:00Z'
    $report.upcoming | Should -Be 1
  }

  It 'applies a city remembered in city-lookup.json and keeps the file' {
    $other = New-TvEvent -Title 'Nature Journaling' -Start '2026-11-20T13:30:00-07:00' -Venue 'Various Treasure Valley locations' -City 'Other' `
      -Category 'learning-business' -Url 'https://beta.test/journal' -Sources @(@{ name = 'beta'; url = 'https://beta.test/journal'; fetchedAt = '2026-11-15T07:01:00Z' })
    Write-TestRaw @{ beta = @($other) }
    $lookupPath = Join-Path $dir 'city-lookup.json'
    '{ "https://beta.test/journal": { "city": "Garden City", "website": "https://library.test/", "checkedAt": "2026-11-14T08:00:00Z" } }' | Set-Content -LiteralPath $lookupPath
    Invoke-TestRefine
    (Read-TvEventFile $eventsPath)[0].city | Should -Be 'Garden City'
    (Get-Content $lookupPath -Raw | ConvertFrom-Json).'https://beta.test/journal'.city | Should -Be 'Garden City'
    $report = Get-Content (Join-Path $dir 'out' 'refine.json') -Raw | ConvertFrom-Json
    $report.cityLookup.found | Should -Be 1
  }

  It 'records start, finish, the raw totals, and whether links were skipped, for the email' {
    Write-TestRaw @{ beta = @((New-TestEvent), (New-TestEvent -Title 'Second Show' -Url 'https://beta.test/2')) }
    Invoke-TestRefine
    $report = Get-Content (Join-Path $dir 'out' 'refine.json') -Raw | ConvertFrom-Json -DateKind String
    $report.startedAt | Should -Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
    $report.finishedAt | Should -Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
    $report.rawSources | Should -Be 1
    $report.rawEvents | Should -Be 2
    $report.skipLinkCheck | Should -BeTrue
  }

  It 'writes nothing with -NoWrite' {
    Write-TestRaw @{ beta = @(New-TestEvent) }
    Invoke-TestRefine @{ NoWrite = $true }
    Test-Path -LiteralPath $eventsPath | Should -BeFalse
    Test-Path -LiteralPath (Join-Path $dir 'meta.json') | Should -BeFalse
  }
}
