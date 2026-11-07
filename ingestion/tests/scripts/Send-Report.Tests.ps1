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
    Get-Content "$preview.txt" -TotalCount 1 | Should -BeExactly 'WeekendBoise Ingest: 1 of 1 sources ok, 3 events'
    Get-Content "$preview.html" -Raw | Should -Match 'Alpha Hall \(alpha\)'
  }

  It 'zips the output folder as the attachment, named like the workflow artifact' {
    @{ startedAt = '2026-11-07T07:00:05Z'; finishedAt = '2026-11-07T07:01:05Z'; sources = @() } |
      ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $out 'run.json')
    'x' | Set-Content -LiteralPath (Join-Path $out 'alpha.json')
    $zipDir = Join-Path $TestDrive "zip-$([guid]::NewGuid().ToString('n'))"
    $preview = Join-Path $TestDrive 'preview-zip'
    & $send -Kind refine -OutDir $out -SourcesPath $sourcesPath -PreviewPath $preview -ZipDir $zipDir -WarningAction SilentlyContinue
    $zip = Join-Path $zipDir 'refine-out.zip'
    Test-Path -LiteralPath $zip | Should -BeTrue
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $entries = [IO.Compression.ZipFile]::OpenRead($zip)
    try { @($entries.Entries.FullName | Sort-Object) | Should -Be @('alpha.json', 'run.json') } finally { $entries.Dispose() }
    Get-Content "$preview.txt" -Raw | Should -Match 'Attached: +refine-out\.zip'
  }

  It 'leaves the attachment off, and says so, when the zip is over the limit' {
    'x' | Set-Content -LiteralPath (Join-Path $out 'alpha.json')
    $preview = Join-Path $TestDrive 'preview-big'
    & $send -Kind ingest -OutDir $out -SourcesPath $sourcesPath -PreviewPath $preview -ZipDir (Join-Path $TestDrive 'zip-big') -MaxAttachmentBytes 1 -WarningAction SilentlyContinue
    Get-Content "$preview.txt" -Raw | Should -Match 'Attached: +none, out\.zip is .* over the .* limit; download it from the workflow run'
  }

  It 'zips the job logs as a second attachment' {
    'x' | Set-Content -LiteralPath (Join-Path $out 'alpha.json')
    $logs = Join-Path $TestDrive "logs-$([guid]::NewGuid().ToString('n'))"
    $null = New-Item -ItemType Directory -Path $logs
    'step output' | Set-Content -LiteralPath (Join-Path $logs 'ingest.log')
    $zipDir = Join-Path $TestDrive "zip-$([guid]::NewGuid().ToString('n'))"
    $preview = Join-Path $TestDrive 'preview-logs'
    & $send -Kind ingest -OutDir $out -LogDir $logs -SourcesPath $sourcesPath -PreviewPath $preview -ZipDir $zipDir -WarningAction SilentlyContinue
    Test-Path -LiteralPath (Join-Path $zipDir 'ingest-logs.zip') | Should -BeTrue
    Get-Content "$preview.txt" -Raw | Should -Match 'Attached: +out\.zip \([^)]*\), ingest-logs\.zip \([^)]*\)'
  }

  It 'says so when there are no job logs' {
    'x' | Set-Content -LiteralPath (Join-Path $out 'alpha.json')
    $preview = Join-Path $TestDrive 'preview-nologs'
    & $send -Kind refine -OutDir $out -LogDir (Join-Path $TestDrive 'missing-logs') -SourcesPath $sourcesPath -PreviewPath $preview -ZipDir (Join-Path $TestDrive 'zip-nologs') -WarningAction SilentlyContinue
    Get-Content "$preview.txt" -Raw | Should -Match 'Attached: +refine-out\.zip \([^)]*\); no job logs'
  }

  It 'reports a refine that wrote no refine.json' {
    $preview = Join-Path $TestDrive 'preview-refine'
    & $send -Kind refine -OutDir $out -SourcesPath $sourcesPath -PreviewPath $preview -Outcome failure -WarningAction SilentlyContinue
    Get-Content "$preview.txt" -TotalCount 1 | Should -BeExactly 'WeekendBoise Refine FAILED: no refine.json'
  }
}
