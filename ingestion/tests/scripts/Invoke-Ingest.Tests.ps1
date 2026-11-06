BeforeAll {
  $script:ingest = Join-Path $PSScriptRoot '..' '..' 'scripts' 'Invoke-Ingest.ps1'
  . "$PSScriptRoot/../../scripts/lib/Raw.ps1"
  $schemaLib = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'scripts' 'lib' 'Schema.ps1')).Path

  # A stub ics adapter: one event per source, and a failure for any source whose url says fail.
  $script:adapterDir = Join-Path $TestDrive 'adapters'
  $null = New-Item -ItemType Directory -Force -Path $adapterDir
  Set-Content -LiteralPath (Join-Path $adapterDir 'ics.ps1') -Value @"
param([pscustomobject]`$Source, [string]`$FetchedAt)
. '$schemaLib'
if (`$Source.url -match 'fail') { throw 'feed is down' }
New-TvEvent -Title "`$(`$Source.displayName) Night" -Start '2026-11-20T19:00:00-07:00' -Venue `$Source.venue -City `$Source.city ``
  -Category `$Source.category -Url "`$(`$Source.url)/e" -Sources @(@{ name = `$Source.name; url = "`$(`$Source.url)/e"; fetchedAt = `$FetchedAt })
"@

  function Write-Sources {
    param([hashtable[]]$Entries)
    $path = Join-Path $TestDrive 'sources.json'
    $list = foreach ($entry in $Entries) {
      [ordered]@{
        name = $entry.name; displayName = $entry.name.ToUpperInvariant(); status = $entry.status ?? 'running'; adapter = 'ics'
        url = $entry.url ?? "https://$($entry.name).test"; category = 'music'; city = 'Boise'; venue = 'Hall'; venueKey = 'hall'
      }
    }
    [ordered]@{ sources = @($list) } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path
    $path
  }

  function Invoke-TestIngest {
    param([hashtable]$Options = @{})
    $global:LASTEXITCODE = 0
    $null = & $ingest -SourcesPath $script:sourcesPath -AdapterDir $adapterDir -RawPath $script:rawPath -OutDir (Join-Path $TestDrive 'out') @Options *>&1
    $LASTEXITCODE
  }
}

Describe 'Invoke-Ingest' {
  BeforeEach {
    $script:rawPath = Join-Path $TestDrive 'raw-events.json'
    Remove-Item -LiteralPath $rawPath -ErrorAction Ignore
    $script:sourcesPath = Write-Sources @(@{ name = 'alpha' }, @{ name = 'beta' })
  }

  It 'writes every source and the scheduled asOf to the raw file' {
    Invoke-TestIngest @{ AsOf = '2026-11-06T07:00:00Z' } | Should -Be 0
    $raw = Read-TvRawFile $rawPath
    $raw.asOf | Should -BeExactly '2026-11-06T07:00:00Z'
    @($raw.sources.PSObject.Properties.Name) | Should -Be @('alpha', 'beta')
    $raw.sources.alpha.events[0].title | Should -Be 'ALPHA Night'
  }

  It 'records the run time as asOf for a manual run' {
    Invoke-TestIngest | Should -Be 0
    (Read-TvRawFile $rawPath).asOf | Should -Match '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
  }

  It 'merges a one-source run into the raw file and keeps its asOf' {
    Invoke-TestIngest @{ AsOf = '2026-11-06T07:00:00Z' } | Should -Be 0
    $script:sourcesPath = Write-Sources @(@{ name = 'alpha'; url = 'https://alpha2.test' }, @{ name = 'beta' })
    Invoke-TestIngest @{ Source = 'alpha' } | Should -Be 0
    $raw = Read-TvRawFile $rawPath
    $raw.asOf | Should -BeExactly '2026-11-06T07:00:00Z'
    $raw.sources.alpha.events[0].url | Should -Be 'https://alpha2.test/e'
    $raw.sources.beta.events[0].url | Should -Be 'https://beta.test/e'
  }

  It 'keeps a failed source''s last good fetch' {
    Invoke-TestIngest | Should -Be 0
    $script:sourcesPath = Write-Sources @(@{ name = 'alpha'; url = 'https://fail.test' }, @{ name = 'beta' })
    Invoke-TestIngest | Should -Be 0
    (Read-TvRawFile $rawPath).sources.alpha.events[0].url | Should -Be 'https://alpha.test/e'
    $run = Get-Content (Join-Path $TestDrive 'out' 'run.json') -Raw | ConvertFrom-Json
    ($run.sources | Where-Object name -eq 'alpha').status | Should -Be 'failed'
  }

  It 'fails and writes nothing when no source succeeds' {
    $script:sourcesPath = Write-Sources @(@{ name = 'alpha'; url = 'https://fail.test' })
    Invoke-TestIngest | Should -Be 1
    Test-Path -LiteralPath $rawPath | Should -BeFalse
  }

  It 'drops a source that is no longer running' {
    Invoke-TestIngest | Should -Be 0
    $script:sourcesPath = Write-Sources @(@{ name = 'alpha' }, @{ name = 'beta'; status = 'investigating' })
    Invoke-TestIngest | Should -Be 0
    @((Read-TvRawFile $rawPath).sources.PSObject.Properties.Name) | Should -Be @('alpha')
  }

  It 'writes nothing with -NoWrite' {
    Invoke-TestIngest @{ NoWrite = $true } | Should -Be 0
    Test-Path -LiteralPath $rawPath | Should -BeFalse
  }
}
