BeforeAll {
  $script:gate = Join-Path $PSScriptRoot '..' '..' 'scripts' 'Test-IngestRan.ps1'

  function New-Job([string]$Name, [string]$Conclusion) {
    [pscustomobject]@{ name = $Name; conclusion = $Conclusion }
  }
}

Describe 'Test-IngestRan' {
  BeforeEach {
    $script:savedOutput = $env:GITHUB_OUTPUT
    $env:GITHUB_OUTPUT = ''
  }

  AfterEach {
    $env:GITHUB_OUTPUT = $script:savedOutput
  }

  It 'refines after an ingest whose job ended <conclusion>' -ForEach @(
    @{ conclusion = 'success' }
    @{ conclusion = 'failure' }
    @{ conclusion = 'cancelled' }
    @{ conclusion = 'timed_out' }
  ) {
    $jobs = @((New-Job when success), (New-Job ingest $conclusion))
    (& $gate -EventName workflow_run -Jobs $jobs).Run | Should -BeTrue
  }

  It 'skips the ingest run whose cron line was not midnight' {
    $jobs = @((New-Job when success), (New-Job ingest skipped))
    (& $gate -EventName workflow_run -Jobs $jobs).Run | Should -BeFalse
  }

  It 'skips an ingest run that never got to its ingest job' {
    $jobs = @((New-Job when failure))
    (& $gate -EventName workflow_run -Jobs $jobs).Run | Should -BeFalse
  }

  It 'always runs a manual run' {
    (& $gate -EventName workflow_dispatch).Run | Should -BeTrue
  }

  It 'writes run to GITHUB_OUTPUT' {
    $env:GITHUB_OUTPUT = Join-Path $TestDrive 'output.txt'
    $null = & $gate -EventName workflow_run -Jobs @((New-Job ingest skipped))
    Get-Content $env:GITHUB_OUTPUT | Should -Be @('run=false')
  }

  It 'fails when a workflow_run has no run id to look up' {
    { & $gate -EventName workflow_run -RunId '' } | Should -Throw '*run id*'
  }
}
