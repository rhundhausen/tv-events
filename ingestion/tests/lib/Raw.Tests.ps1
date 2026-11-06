BeforeAll {
  . "$PSScriptRoot/../../scripts/lib/Raw.ps1"

  function New-TestEvent {
    param(
      [string]$Title = 'Show',
      [string]$Source = 'a',
      [string]$FetchedAt = '2026-11-06T07:01:00Z'
    )
    New-TvEvent -Title $Title -Start '2026-11-14T19:30:00-07:00' -Venue 'Venue' -Category 'music' -Url "https://$Source.test/e" `
      -Sources @(@{ name = $Source; url = "https://$Source.test/e"; fetchedAt = $FetchedAt })
  }

  function New-TestRaw {
    param([string]$AsOf = '2026-11-05T07:00:00Z', [hashtable]$Sources)
    $map = [ordered]@{}
    foreach ($name in $Sources.Keys) {
      $map[$name] = [pscustomobject][ordered]@{ fetchedAt = '2026-11-05T07:01:00Z'; events = @($Sources[$name]) }
    }
    [pscustomobject][ordered]@{ asOf = $AsOf; sources = [pscustomobject]$map }
  }

  function New-Result {
    param([string]$Name, [object[]]$Events, [string]$Status = 'ok')
    [pscustomobject]@{ Name = $Name; Status = $Status; Events = $Events }
  }
}

Describe 'Update-TvRawFile' {
  It 'starts a raw file from nothing' {
    $raw = Update-TvRawFile $null -Results @(New-Result a @(New-TestEvent)) -Keep @('a') -AsOf '2026-11-06T07:00:00Z' -FetchedAt '2026-11-06T07:01:00Z'
    $raw.asOf | Should -BeExactly '2026-11-06T07:00:00Z'
    @($raw.sources.PSObject.Properties.Name) | Should -Be @('a')
    $raw.sources.a.fetchedAt | Should -BeExactly '2026-11-06T07:01:00Z'
    @($raw.sources.a.events).Count | Should -Be 1
  }

  It 'replaces only the sources that were fetched, and keeps the others' {
    $previous = New-TestRaw -Sources @{ a = @(New-TestEvent -Title 'Old A'); b = @(New-TestEvent -Title 'Old B' -Source b) }
    $raw = Update-TvRawFile $previous -Results @(New-Result a @(New-TestEvent -Title 'New A')) -Keep @('a', 'b') -AsOf '2026-11-06T07:00:00Z' -FetchedAt '2026-11-06T07:01:00Z'
    $raw.sources.a.events.title | Should -Be 'New A'
    $raw.sources.b.events.title | Should -Be 'Old B'
    $raw.sources.b.fetchedAt | Should -BeExactly '2026-11-05T07:01:00Z'
  }

  It 'keeps a failed source''s last good fetch' {
    $previous = New-TestRaw -Sources @{ a = @(New-TestEvent -Title 'Old A') }
    $raw = Update-TvRawFile $previous -Results @(New-Result a @() -Status failed) -Keep @('a') -AsOf '2026-11-06T07:00:00Z' -FetchedAt '2026-11-06T07:01:00Z'
    $raw.sources.a.events.title | Should -Be 'Old A'
  }

  It 'records a source that succeeded with no events' {
    $previous = New-TestRaw -Sources @{ a = @(New-TestEvent -Title 'Old A') }
    $raw = Update-TvRawFile $previous -Results @(New-Result a @()) -Keep @('a') -AsOf '2026-11-06T07:00:00Z' -FetchedAt '2026-11-06T07:01:00Z'
    @($raw.sources.a.events).Count | Should -Be 0
  }

  It 'drops sources that are no longer kept' {
    $previous = New-TestRaw -Sources @{ a = @(New-TestEvent); gone = @(New-TestEvent -Source gone) }
    $raw = Update-TvRawFile $previous -Results @(New-Result a @(New-TestEvent)) -Keep @('a') -AsOf '2026-11-06T07:00:00Z' -FetchedAt '2026-11-06T07:01:00Z'
    @($raw.sources.PSObject.Properties.Name) | Should -Be @('a')
  }

  It 'keeps the first fetchedAt of an event it already had, so the file only changes when events do' {
    $previous = New-TestRaw -Sources @{ a = @(New-TestEvent -FetchedAt '2026-11-01T07:00:00Z') }
    $raw = Update-TvRawFile $previous -Results @(New-Result a @(New-TestEvent -FetchedAt '2026-11-06T07:01:00Z')) -Keep @('a') -AsOf '2026-11-06T07:00:00Z' -FetchedAt '2026-11-06T07:01:00Z'
    $raw.sources.a.events[0].sources[0].fetchedAt | Should -BeExactly '2026-11-01T07:00:00Z'
  }

  It 'lists sources in name order' {
    $raw = Update-TvRawFile $null -Results @((New-Result c @()), (New-Result a @()), (New-Result b @())) -Keep @('a', 'b', 'c') -AsOf '2026-11-06T07:00:00Z' -FetchedAt '2026-11-06T07:01:00Z'
    @($raw.sources.PSObject.Properties.Name) | Should -Be @('a', 'b', 'c')
  }
}

Describe 'Read-TvRawFile and Write-TvRawFile' {
  It 'round-trips a raw file with LF line endings and 2-space indents' {
    $path = Join-Path $TestDrive 'raw-events.json'
    Write-TvRawFile $path (New-TestRaw -Sources @{ a = @(New-TestEvent) })
    $text = [IO.File]::ReadAllText($path)
    $text | Should -Not -Match "`r"
    $text | Should -Match "`n  `"asOf`""
    $raw = Read-TvRawFile $path
    $raw.asOf | Should -BeExactly '2026-11-05T07:00:00Z'
    $raw.sources.a.events[0].title | Should -Be 'Show'
  }

  It 'gives nothing for a missing file' {
    Read-TvRawFile (Join-Path $TestDrive 'missing.json') | Should -BeNullOrEmpty
  }

  It 'fails on a file without asOf or sources' {
    $path = Join-Path $TestDrive 'bad.json'
    Set-Content -LiteralPath $path -Value '[]'
    { Read-TvRawFile $path } | Should -Throw '*asOf*'
  }
}

Describe 'Get-TvRawEvents' {
  It 'lists every source''s events, one copy per source' {
    $raw = New-TestRaw -Sources @{ a = @((New-TestEvent -Title 'One'), (New-TestEvent -Title 'Two')); b = @(New-TestEvent -Title 'One' -Source b) }
    @(Get-TvRawEvents $raw).Count | Should -Be 3
  }
}
