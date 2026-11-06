BeforeAll {
  $script:publish = (Resolve-Path (Join-Path $PSScriptRoot '..' '..' 'scripts' 'Publish-Data.ps1')).Path

  function Invoke-InRepo {
    param([string]$Path, [scriptblock]$Script)
    Push-Location $Path
    try { & $Script } finally { Pop-Location }
  }

  function New-Commit {
    # Writes a file and commits it as a person, as a code push would.
    param([string]$Repo, [string]$File, [string]$Text)
    Invoke-InRepo $Repo {
      $parent = Split-Path -Parent $File
      if ($parent) { $null = New-Item -ItemType Directory -Force -Path $parent }
      Set-Content -LiteralPath $File -Value $Text
      git add -- $File 2>&1 | Out-Null
      git -c user.name=Person -c user.email=person@test.invalid commit -q -m "change $File" 2>&1 | Out-Null
    }
  }
}

Describe 'Publish-Data' {
  BeforeEach {
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
    $script:remote = Join-Path $root 'remote.git'
    $script:runner = Join-Path $root 'runner'
    $script:person = Join-Path $root 'person'
    git init -q --bare -b main $remote 2>&1 | Out-Null
    git clone -q $remote $person 2>&1 | Out-Null
    New-Commit $person 'README.md' 'start'
    Invoke-InRepo $person { git push -q origin main 2>&1 | Out-Null }
    # The workflow's checkout: one commit deep, like actions/checkout with fetch-depth 1.
    git clone -q --depth 1 "file://$remote" $runner 2>&1 | Out-Null
    $script:savedRef = $env:GITHUB_REF
    $env:GITHUB_REF = 'refs/heads/main'
  }

  AfterEach {
    $env:GITHUB_REF = $savedRef
  }

  It 'commits and pushes only the given paths' {
    New-Item -ItemType Directory -Path (Join-Path $runner 'data') | Out-Null
    Set-Content (Join-Path $runner 'data/events.json') '[]'
    Set-Content (Join-Path $runner 'notes.txt') 'not data'
    Invoke-InRepo $runner { & $publish -Path data/events.json -Message 'data: test' } | Out-Null
    $files = Invoke-InRepo $person { git pull -q 2>&1 | Out-Null; git show --name-only --format= HEAD }
    $files | Should -Be @('data/events.json')
  }

  It 'replays its commit on top when someone pushed code during the run, and pushes' {
    New-Item -ItemType Directory -Path (Join-Path $runner 'data') | Out-Null
    Set-Content (Join-Path $runner 'data/events.json') '[1]'
    # While the run works, a person pushes a code change.
    New-Commit $person 'website/site.css' 'body {}'
    Invoke-InRepo $person { git push -q origin main 2>&1 | Out-Null }

    Invoke-InRepo $runner { & $publish -Path data/events.json -Message 'data: test' } | Out-Null

    $log = Invoke-InRepo $person { git pull -q 2>&1 | Out-Null; git log --format=%s }
    $log[0] | Should -BeLike 'data: test *'
    $log[1] | Should -Be 'change website/site.css'
    Get-Content (Join-Path $person 'data/events.json') | Should -Be '[1]'
  }

  It 'fails clearly, without pushing, when someone changed the same data file' {
    New-Item -ItemType Directory -Path (Join-Path $runner 'data') | Out-Null
    Set-Content (Join-Path $runner 'data/events.json') '[1]'
    New-Commit $person 'data/events.json' '[2]'
    Invoke-InRepo $person { git push -q origin main 2>&1 | Out-Null }

    { Invoke-InRepo $runner { & $publish -Path data/events.json -Message 'data: test' } } | Should -Throw '*changed the same files*'
    Invoke-InRepo $person { git pull -q 2>&1 | Out-Null; (git log -1 --format=%s) } | Should -Be 'change data/events.json'
  }
}
