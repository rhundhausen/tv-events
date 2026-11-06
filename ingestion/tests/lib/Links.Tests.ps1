BeforeAll {
  . "$PSScriptRoot/../../scripts/lib/Links.ps1"

  $script:now = [DateTimeOffset]::Parse('2026-11-06T07:05:00Z')

  function New-TestEvent {
    param(
      [string]$Title = 'Test Show',
      [string]$Url = 'https://a.test/e',
      [string[]]$OtherUrls = @(),
      [string]$Start = '2026-11-14T19:30:00-07:00'
    )
    $sources = @([pscustomobject]@{ name = 'a'; url = $Url; fetchedAt = '2026-11-01T10:00:00Z' })
    $i = 0
    foreach ($other in $OtherUrls) {
      $i++
      $sources += [pscustomobject]@{ name = "other$i"; url = $other; fetchedAt = '2026-11-01T10:00:00Z' }
    }
    [pscustomobject]@{ id = '0123456789ab'; title = $Title; start = $Start; url = $Url; sources = $sources }
  }

  function New-FakeResponse {
    param([int]$Status, [string]$Body = '')
    [pscustomobject]@{
      StatusCode       = $Status
      RawContentStream = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($Body))
    }
  }

  # Every host serves an empty robots.txt unless a test says otherwise.
  function Set-Responses {
    param([hashtable]$ByUrl, [string]$Robots = '')
    $script:responses = $ByUrl
    $script:robotsText = $Robots
    Mock Start-Sleep {}
    Mock Invoke-WebRequest {
      if ($Uri -like '*/robots.txt') { return New-FakeResponse 200 $script:robotsText }
      $answer = $script:responses["$Uri"]
      if ($answer -is [scriptblock]) { & $answer }
      elseif ($null -ne $answer) { New-FakeResponse $answer }
      else { New-FakeResponse 200 }
    }
  }
}

Describe 'Get-TvLinkVerdict' {
  It 'calls <status> <kind> <want>' -ForEach @(
    @{ status = 200; kind = ''; want = 'ok' }
    @{ status = 301; kind = ''; want = 'ok' }
    @{ status = 404; kind = ''; want = 'broken' }
    @{ status = 410; kind = ''; want = 'broken' }
    @{ status = 401; kind = ''; want = 'blocked' }
    @{ status = 403; kind = ''; want = 'blocked' }
    @{ status = 429; kind = ''; want = 'blocked' }
    @{ status = 500; kind = ''; want = 'transient' }
    @{ status = 503; kind = ''; want = 'transient' }
    @{ status = 0; kind = 'timeout'; want = 'transient' }
    @{ status = 0; kind = 'dns'; want = 'transient' }
    @{ status = 0; kind = 'refused'; want = 'transient' }
    @{ status = 0; kind = 'error'; want = 'blocked' }
    @{ status = 400; kind = ''; want = 'blocked' }
    @{ status = 406; kind = ''; want = 'blocked' }
    @{ status = 451; kind = ''; want = 'blocked' }
    @{ status = 999; kind = ''; want = 'blocked' }
  ) {
    Get-TvLinkVerdict -Status $status -ErrorKind $kind | Should -BeExactly $want
  }
}

Describe 'Test-TvLink' {
  It 'reads a host that does not resolve as dns' {
    Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('No such host is known.', [System.Net.Sockets.SocketException]::new(11001)) }
    $result = Test-TvLink 'https://gone.test/e'
    $result.ErrorKind | Should -Be 'dns'
    $result.Verdict | Should -Be 'transient'
  }

  It 'reads a refused connection as refused' {
    Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('No connection could be made because the target machine actively refused it.', [System.Net.Sockets.SocketException]::new(10061)) }
    (Test-TvLink 'https://down.test/e').ErrorKind | Should -Be 'refused'
  }

  It 'reads a timeout as timeout' {
    Mock Invoke-WebRequest { throw [System.Threading.Tasks.TaskCanceledException]::new('The request was canceled due to the configured HttpClient.Timeout of 20 seconds elapsing.') }
    (Test-TvLink 'https://slow.test/e').ErrorKind | Should -Be 'timeout'
  }

  It 'sends the project User-Agent and follows redirects' {
    Mock Invoke-WebRequest { New-FakeResponse 200 }
    $null = Test-TvLink 'https://a.test/e'
    Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $UserAgent -eq (Get-TvUserAgent) -and $MaximumRedirection -ge 5 }
  }

  It 'follows a redirect from https to http, as a browser does' {
    Mock Invoke-WebRequest { New-FakeResponse 200 }
    $null = Test-TvLink 'https://a.test/e'
    Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $AllowInsecureRedirect }
  }
}

Describe 'Invoke-TvLinkCheck' {
  It 'never unlinks an event whose site blocks scripts' {
    Set-Responses @{ 'https://a.test/e' = 403 }
    $event = New-TestEvent
    $result = Invoke-TvLinkCheck @($event) -State @{} -Now $now -BudgetSeconds 60
    $event.PSObject.Properties.Name | Should -Not -Contain 'linkBroken'
    $result.Broken.Count | Should -Be 0
    $result.State['https://a.test/e'].verdict | Should -Be 'blocked'
  }

  It 'unlinks an event on the first 404 and lists it' {
    Set-Responses @{ 'https://a.test/e' = 404 }
    $event = New-TestEvent
    $result = Invoke-TvLinkCheck @($event) -State @{} -Now $now -BudgetSeconds 60
    $event.linkBroken | Should -BeTrue
    $result.Broken.Count | Should -Be 1
    $result.Broken[0].reason | Should -Be 'HTTP 404'
    $result.Broken[0].new | Should -BeTrue
    $result.State['https://a.test/e'].brokenSince | Should -Be '2026-11-06T07:05:00Z'
  }

  It 'needs two nights of timeouts before unlinking' {
    Set-Responses @{ 'https://a.test/e' = { throw [System.Threading.Tasks.TaskCanceledException]::new('timed out') } }
    $event = New-TestEvent
    $first = Invoke-TvLinkCheck @($event) -State @{} -Now $now -BudgetSeconds 60
    $event.PSObject.Properties.Name | Should -Not -Contain 'linkBroken'

    $again = New-TestEvent
    $second = Invoke-TvLinkCheck @($again) -State $first.State -Now $now.AddHours(24) -BudgetSeconds 60
    $again.linkBroken | Should -BeTrue
    $second.Broken[0].reason | Should -Be 'timeout, 2 nights in a row'
  }

  It 'catches a host that no longer resolves, even though its robots.txt fails first' {
    Mock Start-Sleep {}
    Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('No such host is known.', [System.Net.Sockets.SocketException]::new(11001)) }
    $event = New-TestEvent
    $first = Invoke-TvLinkCheck @($event) -State @{} -Now $now -BudgetSeconds 60
    $event.PSObject.Properties.Name | Should -Not -Contain 'linkBroken'
    $first.State['https://a.test/e'].error | Should -Be 'dns'

    $again = New-TestEvent
    $second = Invoke-TvLinkCheck @($again) -State $first.State -Now $now.AddHours(24) -BudgetSeconds 60
    $again.linkBroken | Should -BeTrue
    $second.Broken[0].reason | Should -Be 'dns, 2 nights in a row'
  }

  It 'treats a damaged state entry as due instead of failing the run' {
    Set-Responses @{}
    $state = @{ 'https://a.test/e' = @{ verdict = 'ok'; status = 200; failures = 0 } }
    $result = Invoke-TvLinkCheck @(New-TestEvent) -State $state -Now $now -BudgetSeconds 60
    $result.Checked.Count | Should -Be 1
  }

  It 'switches to another source''s working link instead of unlinking' {
    Set-Responses @{ 'https://a.test/e' = 404; 'https://b.test/e' = 200 }
    $event = New-TestEvent -OtherUrls 'https://b.test/e'
    $result = Invoke-TvLinkCheck @($event) -State @{} -Now $now -BudgetSeconds 60
    $event.url | Should -Be 'https://b.test/e'
    $event.PSObject.Properties.Name | Should -Not -Contain 'linkBroken'
    $result.Broken.Count | Should -Be 0
  }

  It 'does not switch to another link that is unchecked or broken' {
    Set-Responses @{ 'https://a.test/e' = 404; 'https://b.test/e' = 404 }
    $event = New-TestEvent -OtherUrls 'https://b.test/e'
    $null = Invoke-TvLinkCheck @($event) -State @{} -Now $now -BudgetSeconds 60
    $event.url | Should -Be 'https://a.test/e'
    $event.linkBroken | Should -BeTrue
  }

  It 'does not recheck a link that worked 2 days ago' {
    Set-Responses @{}
    $state = @{ 'https://a.test/e' = @{ verdict = 'ok'; status = 200; checkedAt = '2026-11-04T07:00:00Z'; failures = 0 } }
    $result = Invoke-TvLinkCheck @(New-TestEvent) -State $state -Now $now -BudgetSeconds 60
    Should -Invoke Invoke-WebRequest -Times 0
    $result.Checked.Count | Should -Be 0
  }

  It 'rechecks a link that worked 8 days ago' {
    Set-Responses @{}
    $state = @{ 'https://a.test/e' = @{ verdict = 'ok'; status = 200; checkedAt = '2026-10-29T07:00:00Z'; failures = 0 } }
    $result = Invoke-TvLinkCheck @(New-TestEvent) -State $state -Now $now -BudgetSeconds 60
    $result.Checked.Count | Should -Be 1
  }

  It 'gives a broken link back when it works again' {
    Set-Responses @{ 'https://a.test/e' = 200 }
    $state = @{ 'https://a.test/e' = @{ verdict = 'broken'; status = 404; checkedAt = '2026-11-05T07:00:00Z'; brokenSince = '2026-11-01T07:00:00Z'; failures = 0 } }
    $event = New-TestEvent
    $event | Add-Member -NotePropertyName linkBroken -NotePropertyValue $true
    $result = Invoke-TvLinkCheck @($event) -State $state -Now $now -BudgetSeconds 60
    $event.PSObject.Properties.Name | Should -Not -Contain 'linkBroken'
    $result.State['https://a.test/e'].Keys | Should -Not -Contain 'brokenSince'
  }

  It 'checks nothing with no budget, and still applies what it already knows' {
    Set-Responses @{}
    $state = @{ 'https://b.test/x' = @{ verdict = 'broken'; status = 404; checkedAt = '2026-11-06T06:00:00Z'; brokenSince = '2026-11-06T06:00:00Z'; failures = 0 } }
    $fresh = New-TestEvent
    $known = New-TestEvent -Url 'https://b.test/x'
    $result = Invoke-TvLinkCheck @($fresh, $known) -State $state -Now $now -BudgetSeconds 0
    Should -Invoke Invoke-WebRequest -Times 0
    $fresh.PSObject.Properties.Name | Should -Not -Contain 'linkBroken'
    $known.linkBroken | Should -BeTrue
    $result.Broken[0].new | Should -BeFalse
  }

  It 'never requests a path robots.txt disallows' {
    Set-Responses @{ 'https://a.test/private/e' = 404 } -Robots "User-agent: *`nDisallow: /private/"
    $event = New-TestEvent -Url 'https://a.test/private/e'
    $result = Invoke-TvLinkCheck @($event) -State @{} -Now $now -BudgetSeconds 60
    Should -Invoke Invoke-WebRequest -Times 0 -ParameterFilter { $Uri -eq 'https://a.test/private/e' }
    $event.PSObject.Properties.Name | Should -Not -Contain 'linkBroken'
    $result.State['https://a.test/private/e'].verdict | Should -Be 'skipped'
  }

  It 'checks the soonest events first and fetches robots.txt once per host' {
    Set-Responses @{}
    $late = New-TestEvent -Url 'https://a.test/late' -Start '2026-12-20T19:00:00-07:00'
    $soon = New-TestEvent -Url 'https://a.test/soon' -Start '2026-11-07T19:00:00-07:00'
    $result = Invoke-TvLinkCheck @($late, $soon) -State @{} -Now $now -BudgetSeconds 60
    $result.Checked.url | Should -Be @('https://a.test/soon', 'https://a.test/late')
    Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter { $Uri -like '*/robots.txt' }
  }

  It 'only checks the links of the named source' {
    Set-Responses @{}
    $mine = New-TestEvent -Url 'https://a.test/mine'
    $theirs = New-TestEvent -Url 'https://a.test/theirs'
    $theirs.sources[0].name = 'b'
    $result = Invoke-TvLinkCheck @($mine, $theirs) -State @{} -Now $now -BudgetSeconds 60 -OnlySource 'a'
    $result.Checked.url | Should -Be @('https://a.test/mine')
  }

  It 'forgets links no event has used for 30 days' {
    Set-Responses @{}
    $state = @{
      'https://old.test/e' = @{ verdict = 'ok'; status = 200; checkedAt = '2026-10-01T07:00:00Z'; failures = 0 }
      'https://recent.test/e' = @{ verdict = 'ok'; status = 200; checkedAt = '2026-11-01T07:00:00Z'; failures = 0 }
    }
    $result = Invoke-TvLinkCheck @() -State $state -Now $now -BudgetSeconds 0
    $result.State.Keys | Should -Not -Contain 'https://old.test/e'
    $result.State.Keys | Should -Contain 'https://recent.test/e'
  }
}

Describe 'Write-TvLinkState and Read-TvLinkState' {
  It 'round-trips with sorted keys' {
    $path = Join-Path $TestDrive 'links.json'
    $state = @{
      'https://b.test/e' = @{ verdict = 'ok'; status = 200; checkedAt = '2026-11-06T07:00:00Z'; failures = 0 }
      'https://a.test/e' = @{ verdict = 'broken'; status = 404; checkedAt = '2026-11-06T07:00:00Z'; brokenSince = '2026-11-06T07:00:00Z'; failures = 0 }
    }
    Write-TvLinkState $path $state
    $text = Get-Content $path -Raw
    $text.IndexOf('https://a.test/e') | Should -BeLessThan $text.IndexOf('https://b.test/e')
    $text | Should -Not -Match "`r"
    $back = Read-TvLinkState $path
    $back['https://a.test/e'].brokenSince | Should -Be '2026-11-06T07:00:00Z'
  }

  It 'reads a missing file as empty' {
    (Read-TvLinkState (Join-Path $TestDrive 'nope.json')).Count | Should -Be 0
  }
}

Describe 'ConvertTo-TvLinkSummary' {
  It 'groups broken links by source, new ones first' {
    $broken = @(
      [pscustomobject]@{ title = 'Old Break'; start = '2026-11-10'; url = 'https://a.test/1'; sources = 'a'; reason = 'HTTP 404'; brokenSince = '2026-11-01T07:00:00Z'; new = $false }
      [pscustomobject]@{ title = 'New Break'; start = '2026-11-12'; url = 'https://a.test/2'; sources = 'a'; reason = 'HTTP 410'; brokenSince = '2026-11-06T07:00:00Z'; new = $true }
      [pscustomobject]@{ title = 'Other'; start = '2026-11-11'; url = 'https://b.test/1'; sources = 'b'; reason = 'HTTP 404'; brokenSince = '2026-11-06T07:00:00Z'; new = $true }
    )
    $text = ConvertTo-TvLinkSummary $broken -Checked 40
    $text | Should -Match '## Broken links'
    $text | Should -Match '### a'
    $text.IndexOf('New Break') | Should -BeLessThan $text.IndexOf('Old Break')
    $text | Should -Match '40 links checked'
  }

  It 'says so when nothing is broken' {
    ConvertTo-TvLinkSummary @() -Checked 3 | Should -Match 'No broken links'
  }
}
