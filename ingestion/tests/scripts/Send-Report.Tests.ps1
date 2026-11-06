BeforeAll {
  $script:send = Join-Path $PSScriptRoot '..' '..' 'scripts' 'Send-Report.ps1'
  $script:sourcesPath = Join-Path $TestDrive 'sources.json'
  @{ sources = @(@{ name = 'alpha'; displayName = 'Alpha Hall'; status = 'running'; adapter = 'ics'; url = 'https://alpha.test/cal.ics' }) } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sourcesPath
}

Describe 'Send-Report' {
  BeforeEach {
    $script:out = Join-Path $TestDrive "out-$([guid]::NewGuid().ToString('n'))"
    $null = New-Item -ItemType Directory -Path $out
    $script:saved = @{ key = $env:RESEND_API_KEY; to = $env:REPORT_EMAIL }
    $env:RESEND_API_KEY = ''
    $env:REPORT_EMAIL = ''
  }

  AfterEach {
    $env:RESEND_API_KEY = $saved.key
    $env:REPORT_EMAIL = $saved.to
  }

  It 'skips sending, with a warning, when the Resend key or address is not set' {
    $warnings = $null
    & $send -Kind ingest -OutDir $out -SourcesPath $sourcesPath -WarningVariable warnings -WarningAction SilentlyContinue
    $LASTEXITCODE | Should -Be 0
    "$warnings" | Should -Match 'RESEND_API_KEY'
  }

  It 'writes a preview of the ingest report from run.json' {
    @{ startedAt = '2026-11-07T07:00:05Z'; finishedAt = '2026-11-07T07:01:05Z'; sources = @(@{ name = 'alpha'; status = 'ok'; fetched = 3; duration = '1s'; warnings = @() }) } |
      ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'run.json')
    $preview = Join-Path $TestDrive 'preview'
    & $send -Kind ingest -OutDir $out -SourcesPath $sourcesPath -PreviewPath $preview -Outcome success -WarningAction SilentlyContinue
    Get-Content "$preview.txt" -TotalCount 1 | Should -Be 'WeekendBoise ingest: 1 of 1 sources ok, 3 events'
    Get-Content "$preview.html" -Raw | Should -Match 'Alpha Hall \(alpha\)'
  }

  It 'reports a refine that wrote no refine.json' {
    $preview = Join-Path $TestDrive 'preview-refine'
    & $send -Kind refine -OutDir $out -SourcesPath $sourcesPath -PreviewPath $preview -Outcome failure -WarningAction SilentlyContinue
    Get-Content "$preview.txt" -TotalCount 1 | Should -Be 'WeekendBoise refine FAILED: no refine.json'
  }
}
