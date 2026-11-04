BeforeAll {
  $script:testSources = Join-Path $PSScriptRoot '..' '..' 'scripts' 'Test-Sources.ps1'
  $script:repoSources = Join-Path $PSScriptRoot '..' '..' 'sources.json'

  # A complete running entry. Tests copy it and change one thing.
  function New-RunningEntry {
    param([hashtable]$Change = @{}, [string[]]$Remove = @())
    $entry = [ordered]@{
      name = 'example-hall'; displayName = 'Example Hall'; status = 'running'; adapter = 'ics'
      url = 'https://example.com/calendar.ics'; category = 'music'; city = 'Boise'
      venue = 'Example Hall'; venueKey = 'example-hall'
    }
    foreach ($key in $Change.Keys) { $entry[$key] = $Change[$key] }
    foreach ($key in $Remove) { $entry.Remove($key) }
    $entry
  }

  # Runs Test-Sources.ps1 on a temporary file and returns its exit code and output.
  function Invoke-TestSources {
    param([object[]]$Sources, [string]$Json)
    if (-not $Json) { $Json = @{ sources = @($Sources) } | ConvertTo-Json -Depth 10 }
    $path = Join-Path $TestDrive 'sources.json'
    Set-Content -LiteralPath $path -Value $Json
    $global:LASTEXITCODE = 0
    $output = (& $script:testSources -Path $path *>&1 | Out-String)
    [pscustomobject]@{ Exit = $LASTEXITCODE; Output = $output }
  }
}

Describe 'Test-Sources.ps1' {
  Context 'ideas' {
    It 'accepts an entry with nothing but a displayName' {
      $r = Invoke-TestSources @(@{ displayName = 'Egyptian Theatre' })
      $r.Exit | Should -Be 0
      $r.Output | Should -Not -Match 'WARN'
      $r.Output | Should -Match '1 idea'
    }

    It 'accepts an empty list' {
      (Invoke-TestSources @()).Exit | Should -Be 0
    }

    It 'warns, without failing, about an idea with no displayName' {
      $r = Invoke-TestSources @(@{ notes = 'no title' })
      $r.Exit | Should -Be 0
      $r.Output | Should -Match 'WARN: entry 0'
    }

    It 'warns about an unknown field on an idea' {
      $r = Invoke-TestSources @(@{ displayName = 'x'; enabled = $true })
      $r.Exit | Should -Be 0
      $r.Output | Should -Match 'WARN: entry 0'
    }

    It 'warns about an unknown status' {
      (Invoke-TestSources @(@{ displayName = 'x'; status = 'maybe' })).Output | Should -Match 'WARN: entry 0'
    }

    It 'warns about a ruled-out entry with no reason' {
      (Invoke-TestSources @(@{ displayName = 'x'; status = 'ruled-out' })).Output | Should -Match 'WARN: entry 0'
    }

    It 'accepts a ruled-out entry with a reason' {
      (Invoke-TestSources @(@{ displayName = 'x'; status = 'ruled-out'; reason = 'HTTP 403' })).Output | Should -Not -Match 'WARN'
    }

    It 'warns about a feed-found entry with no url' {
      (Invoke-TestSources @(@{ displayName = 'x'; status = 'feed-found' })).Output | Should -Match 'WARN: entry 0'
    }

    It 'warns about a ready entry with no adapter' {
      (Invoke-TestSources @(@{ displayName = 'x'; status = 'ready'; url = 'https://example.com' })).Output | Should -Match 'WARN: entry 0'
    }

    It 'accepts a ticketmaster candidate without a venueId while it has no name' {
      $r = Invoke-TestSources @(@{ displayName = 'x'; status = 'feed-found'; adapter = 'ticketmaster'; url = 'https://app.ticketmaster.com/discovery/v2/events.json' })
      $r.Output | Should -Not -Match 'WARN'
    }

    It 'accepts adapter other on an unconfigured entry' {
      (Invoke-TestSources @(@{ displayName = 'x'; status = 'ready'; adapter = 'other'; url = 'https://example.com' })).Output | Should -Not -Match 'WARN'
    }

    It 'rejects a bad robotsChecked date' {
      (Invoke-TestSources @(@{ displayName = 'x'; robotsChecked = '3 Nov 2026' })).Output | Should -Match 'WARN: entry 0'
    }

    It 'warns about displayNames that differ only in case' {
      $r = Invoke-TestSources @(@{ displayName = 'Boise Hawks' }, @{ displayName = 'boise hawks' })
      $r.Exit | Should -Be 0
      $r.Output | Should -Match 'WARN: Duplicate displayName'
    }
  }

  Context 'configured and running entries' {
    It 'accepts a complete running entry' {
      $r = Invoke-TestSources @(New-RunningEntry)
      $r.Exit | Should -Be 0
      $r.Output | Should -Match '1 running'
    }

    It 'fails a running entry with no name' {
      $r = Invoke-TestSources @(New-RunningEntry -Remove 'name')
      $r.Exit | Should -Be 1
      $r.Output | Should -Match 'FAIL: entry 0'
    }

    It 'fails a running entry missing part of its configuration' {
      (Invoke-TestSources @(New-RunningEntry -Remove 'venueKey')).Exit | Should -Be 1
    }

    It 'fails a running entry that still has enabled' {
      (Invoke-TestSources @(New-RunningEntry -Change @{ enabled = $true })).Exit | Should -Be 1
    }

    It 'only warns when a configured entry that is not running is incomplete' {
      $r = Invoke-TestSources @(New-RunningEntry -Change @{ status = 'ready' } -Remove 'venueKey')
      $r.Exit | Should -Be 0
      $r.Output | Should -Match 'WARN: entry 0 \(example-hall\)'
    }

    It 'fails adapter other on a running entry' {
      (Invoke-TestSources @(New-RunningEntry -Change @{ adapter = 'other' })).Exit | Should -Be 1
    }

    It 'fails a running ticketmaster entry with no venueId or area' {
      (Invoke-TestSources @(New-RunningEntry -Change @{ adapter = 'ticketmaster' })).Exit | Should -Be 1
    }

    It 'fails a running cards scrape with no itemPattern' {
      (Invoke-TestSources @(New-RunningEntry -Change @{ adapter = 'scrape'; scrapeMode = 'cards' })).Exit | Should -Be 1
    }

    It 'accepts the calendarapp scrape mode' {
      (Invoke-TestSources @(New-RunningEntry -Change @{ adapter = 'scrape'; scrapeMode = 'calendarapp' })).Exit | Should -Be 0
    }

    It 'fails duplicate names' {
      $r = Invoke-TestSources @((New-RunningEntry), (New-RunningEntry -Change @{ displayName = 'Other' }))
      $r.Exit | Should -Be 1
      $r.Output | Should -Match 'Duplicate source name'
    }
  }

  Context 'the file' {
    It 'fails JSON that does not parse' {
      (Invoke-TestSources -Json '{ "sources": [').Exit | Should -Be 1
    }

    It 'fails an unknown top-level property' {
      (Invoke-TestSources -Json '{ "sources": [], "extra": 1 }').Exit | Should -Be 1
    }

    It 'accepts a _comment' {
      (Invoke-TestSources -Json '{ "_comment": "hi", "sources": [] }').Exit | Should -Be 0
    }

    It 'passes the repo sources.json with no warnings' {
      $global:LASTEXITCODE = 0
      $output = & $script:testSources -Path $script:repoSources *>&1 | Out-String
      $LASTEXITCODE | Should -Be 0
      $output | Should -Not -Match 'WARN'
    }
  }
}
