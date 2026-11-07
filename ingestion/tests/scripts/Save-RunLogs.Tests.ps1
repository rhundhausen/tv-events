BeforeAll {
  $script:save = Join-Path $PSScriptRoot '..' '..' 'scripts' 'Save-RunLogs.ps1'

  # Answers like the GitHub API: the run's jobs, then each job's log text. A URL it doesn't know throws.
  function New-Fetcher([hashtable]$Answers) {
    $log = [Collections.Generic.List[string]]::new()
    $script:requests = $log
    {
      param([string]$Endpoint)
      $log.Add($Endpoint)
      if ($Answers.ContainsKey($Endpoint)) { return $Answers[$Endpoint] }
      throw "HTTP 404 from $Endpoint"
    }.GetNewClosure()
  }

  $script:jobs = '{"jobs":[{"id":11,"name":"when"},{"id":22,"name":"ingest"},{"id":33,"name":"report"}]}'
}

Describe 'Save-RunLogs' {
  BeforeEach {
    $script:dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
  }

  It 'saves each finished job''s log, named after the job, and skips the report job itself' {
    $fetch = New-Fetcher @{
      'repos/o/r/actions/runs/7/jobs' = $jobs
      'repos/o/r/actions/jobs/11/logs' = 'when log'
      'repos/o/r/actions/jobs/22/logs' = "ingest log`nline 2"
    }
    & $save -RunId 7 -Repository 'o/r' -OutDir $dir -Fetch $fetch
    @(Get-ChildItem $dir | ForEach-Object Name | Sort-Object) | Should -Be @('ingest.log', 'when.log')
    Get-Content (Join-Path $dir 'ingest.log') -Raw | Should -Match 'line 2'
    $requests | Should -Not -Contain 'repos/o/r/actions/jobs/33/logs'
  }

  It 'strips the terminal color codes GitHub puts in its logs' {
    $esc = [char]27
    $fetch = New-Fetcher @{
      'repos/o/r/actions/runs/7/jobs' = $jobs
      'repos/o/r/actions/jobs/11/logs' = 'x'
      'repos/o/r/actions/jobs/22/logs' = "$esc[36;1m./ingestion/scripts/Invoke-Refine.ps1$esc[0m done"
    }
    & $save -RunId 7 -Repository 'o/r' -OutDir $dir -Fetch $fetch
    Get-Content (Join-Path $dir 'ingest.log') -Raw | Should -Match '^\./ingestion/scripts/Invoke-Refine\.ps1 done'
  }

  It 'ends with exit code 0 even when a failed request left a failing exit code behind' {
    $fetch = {
      param([string]$Endpoint)
      $global:LASTEXITCODE = 1
      throw "failed $Endpoint"
    }
    & $save -RunId 7 -Repository 'o/r' -OutDir $dir -Fetch $fetch -WarningAction SilentlyContinue
    $LASTEXITCODE | Should -Be 0
  }

  It 'warns and keeps going when one job''s log can''t be read' {
    $fetch = New-Fetcher @{
      'repos/o/r/actions/runs/7/jobs' = $jobs
      'repos/o/r/actions/jobs/22/logs' = 'ingest log'
    }
    $warnings = $null
    & $save -RunId 7 -Repository 'o/r' -OutDir $dir -Fetch $fetch -WarningVariable warnings -WarningAction SilentlyContinue
    @(Get-ChildItem $dir | ForEach-Object Name) | Should -Be @('ingest.log')
    "$warnings" | Should -Match 'when'
  }

  It 'warns, and never fails, when the job list can''t be read' {
    $warnings = & $save -RunId 7 -Repository 'o/r' -OutDir $dir -Fetch (New-Fetcher @{}) 3>&1 | Out-String
    $warnings | Should -Match 'jobs'
    @(Get-ChildItem $dir).Count | Should -Be 0
  }
}
