# Nightly check that event links still work. State lives in data/links.json. See docs/development.md.

. "$PSScriptRoot/Schema.ps1"
. "$PSScriptRoot/Http.ps1"
. "$PSScriptRoot/Scrape.ps1"

$script:LinkStamp = "yyyy-MM-dd'T'HH:mm:ss'Z'"

function Get-TvLinkVerdict {
  <#
  .SYNOPSIS
    ok, broken, blocked, or transient.
  .DESCRIPTION
    Only 404 and 410 say a page is gone. 401, 403 and 429 are a site turning away scripts, which says
    nothing about the page, so they never break a link. Timeouts, 5xx, DNS failures and refused
    connections look the same as a host having a bad hour.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [int]$Status,
    [AllowEmptyString()][string]$ErrorKind
  )

  if ($ErrorKind) { return 'transient' }
  if ($Status -ge 200 -and $Status -lt 400) { return 'ok' }
  if ($Status -in 404, 410) { return 'broken' }
  if ($Status -in 401, 403, 429) { return 'blocked' }
  'transient'
}

function Get-TvLinkErrorKind {
  # dns, refused, timeout, or error, from a request exception and its inner exceptions.
  param([Exception]$Exception)

  for ($e = $Exception; $e; $e = $e.InnerException) {
    if ($e -is [System.Net.Sockets.SocketException]) {
      switch ($e.SocketErrorCode.ToString()) {
        { $_ -in 'HostNotFound', 'TryAgain', 'NoData' } { return 'dns' }
        'ConnectionRefused' { return 'refused' }
        'TimedOut' { return 'timeout' }
      }
    }
    if ($e -is [System.Threading.Tasks.TaskCanceledException] -or $e -is [TimeoutException]) { return 'timeout' }
  }
  $message = "$($Exception.Message)"
  if ($message -match '(?i)no such host|name or service not known|nodename nor servname') { return 'dns' }
  if ($message -match '(?i)refused') { return 'refused' }
  if ($message -match '(?i)timed? ?out|timeout') { return 'timeout' }
  'error'
}

function Test-TvLink {
  # One GET with the project User-Agent, following redirects. Returns Status, ErrorKind and Verdict.
  [CmdletBinding()]
  param([Parameter(Mandatory, Position = 0)][string]$Url)

  $status = 0
  $kind = ''
  try {
    $response = Invoke-WebRequest -Uri $Url -UserAgent (Get-TvUserAgent) -MaximumRedirection 10 -TimeoutSec 20 -SkipHttpErrorCheck -ErrorAction Stop
    $status = [int]$response.StatusCode
  } catch {
    $kind = Get-TvLinkErrorKind $_.Exception
  }
  @{ Status = $status; ErrorKind = $kind; Verdict = (Get-TvLinkVerdict -Status $status -ErrorKind $kind) }
}

function Test-TvLinkEntryBroken {
  # A 404 or 410, or a transient failure 2 nights in a row. A broken link stays broken through a
  # transient failure, since that says nothing new.
  param([object]$Entry)

  if (-not $Entry) { return $false }
  $Entry.verdict -eq 'broken' -or ($Entry.verdict -eq 'transient' -and ([int]$Entry.failures -ge 2 -or $Entry.brokenSince))
}

function Get-TvLinkReason {
  param([object]$Entry)

  $what = if ($Entry.error) { $Entry.error } else { "HTTP $($Entry.status)" }
  if ($Entry.verdict -eq 'broken') { return $what }
  "$what, $([Math]::Max(2, [int]$Entry.failures)) nights in a row"
}

function Invoke-TvLinkCheck {
  <#
  .SYNOPSIS
    Checks the event links that are due, then marks events whose link is broken.
  .DESCRIPTION
    A link is due the first night it appears; 7 days after it last worked (or was blocked or
    disallowed); and every night while it is broken or failing. Due links are checked soonest event
    first until BudgetSeconds run out; the rest wait for another night and count as working.

    Each host's robots.txt is read once per run, and a disallowed path is never requested. Requests
    to one host are at least 1 second apart, or the host's Crawl-delay.

    An event whose link is broken switches to another of its sources' links if that one has been
    checked and works. Otherwise it gets linkBroken = true. Entries for links no event has used
    for 30 days are dropped.
  .PARAMETER State
    URL to entry (verdict, status, error, checkedAt, brokenSince, failures), from Read-TvLinkState.
    It is updated in place and returned.
  .PARAMETER OnlySource
    Check only links of events this source reported. Known results still apply to every event.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)][AllowEmptyCollection()][object[]]$Events,
    [Parameter(Mandatory)][hashtable]$State,
    [Parameter(Mandatory)][DateTimeOffset]$Now,
    [int]$BudgetSeconds = 900,
    [string]$OnlySource
  )

  $invariant = [Globalization.CultureInfo]::InvariantCulture
  $nowText = $Now.UtcDateTime.ToString($script:LinkStamp, $invariant)
  $timer = [Diagnostics.Stopwatch]::StartNew()
  $robots = @{}
  $delays = @{}
  $lastRequest = @{}
  $checked = [Collections.Generic.List[object]]::new()

  function Test-Due([string]$Url) {
    $entry = $State[$Url]
    if (-not $entry) { return $true }
    $age = $Now - [DateTimeOffset]::Parse($entry.checkedAt, $invariant)
    if ($entry.verdict -in 'ok', 'blocked', 'skipped') { return $age.TotalDays -ge 7 }
    $age.TotalHours -ge 20
  }

  function Wait-Host([string]$Origin) {
    if ($lastRequest.ContainsKey($Origin)) {
      $gap = $delays[$Origin] * 1000 - ($timer.ElapsedMilliseconds - $lastRequest[$Origin])
      if ($gap -gt 0) { Start-Sleep -Milliseconds $gap }
    }
    $lastRequest[$Origin] = $timer.ElapsedMilliseconds
  }

  function Invoke-Probe([string]$Url, [string]$Names, [string]$Title) {
    # Returns $false once the budget is spent, so the caller stops.
    if ($timer.Elapsed.TotalSeconds -ge $BudgetSeconds) { return $false }
    $uri = $null
    if (-not [uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { return $true }
    $origin = $uri.GetLeftPart('Authority')

    if (-not $robots.ContainsKey($origin)) {
      $delays[$origin] = 1
      Wait-Host $origin
      $text = try { Invoke-TvRequest "$origin/robots.txt" -Raw } catch {
        # No robots.txt means no rules. Any other failure means we can't tell, so leave the host alone.
        if ("$_" -match 'HTTP 40[14]|HTTP 410') { '' } else { $null }
      }
      $robots[$origin] = $text
      if ($null -ne $text) { $delays[$origin] = [Math]::Max(1, [int](Get-TvRobotsGroup $text).Delay) }
    }
    $rules = $robots[$origin]
    if ($null -eq $rules -or $delays[$origin] -gt 60) { return $true }

    $previous = $State[$Url]
    if (-not (Test-TvRobotsAllowed $rules $uri.PathAndQuery)) {
      $State[$Url] = [ordered]@{ verdict = 'skipped'; status = 0; checkedAt = $nowText; failures = 0 }
      $checked.Add([pscustomobject]@{ url = $Url; verdict = 'skipped'; status = 0; error = 'robots.txt disallows'; sources = $Names; title = $Title })
      return $true
    }

    Wait-Host $origin
    $result = Test-TvLink $Url
    $entry = [ordered]@{
      verdict   = $result.Verdict
      status    = $result.Status
      checkedAt = $nowText
      failures  = if ($result.Verdict -eq 'transient') { [int]$previous.failures + 1 } else { 0 }
    }
    if ($result.ErrorKind) { $entry.error = $result.ErrorKind }
    if ($result.Verdict -eq 'transient' -and $previous.brokenSince) { $entry.brokenSince = $previous.brokenSince }
    if (Test-TvLinkEntryBroken $entry) {
      $entry.brokenSince = if ($previous.brokenSince) { $previous.brokenSince } else { $nowText }
    }
    $State[$Url] = $entry
    $checked.Add([pscustomobject]@{ url = $Url; verdict = $result.Verdict; status = $result.Status; error = $result.ErrorKind; sources = $Names; title = $Title })
    $true
  }

  # One entry per link, holding the soonest event that uses it.
  $byUrl = @{}
  foreach ($event in $Events) {
    if (-not $event.url) { continue }
    $names = @($event.sources | ForEach-Object name)
    if ($OnlySource -and $OnlySource -notin $names) { continue }
    $instant = Get-TvEventInstant $event.start
    $known = $byUrl[$event.url]
    if (-not $known -or $instant -lt $known.Instant) {
      $byUrl[$event.url] = [pscustomobject]@{ Url = $event.url; Instant = $instant; Names = ($names -join ', '); Title = $event.title }
    }
  }

  $due = @($byUrl.Values | Where-Object { Test-Due $_.Url } | Sort-Object Instant, Url)
  foreach ($link in $due) {
    if (-not (Invoke-Probe $link.Url $link.Names $link.Title)) { break }
  }

  $broken = [Collections.Generic.List[object]]::new()
  foreach ($event in $Events) {
    $entry = $State[$event.url]
    if (-not (Test-TvLinkEntryBroken $entry)) {
      if ($event.PSObject.Properties['linkBroken']) { $event.PSObject.Properties.Remove('linkBroken') }
      continue
    }

    $names = @($event.sources | ForEach-Object name) -join ', '
    $switched = $false
    foreach ($other in @($event.sources | ForEach-Object url | Where-Object { $_ -and $_ -ne $event.url } | Select-Object -Unique)) {
      if (Test-Due $other) { $null = Invoke-Probe $other $names $event.title }
      if ($State[$other].verdict -eq 'ok') {
        $event.url = $other
        $switched = $true
        break
      }
    }
    if ($switched) {
      if ($event.PSObject.Properties['linkBroken']) { $event.PSObject.Properties.Remove('linkBroken') }
      continue
    }

    $event | Add-Member -NotePropertyName linkBroken -NotePropertyValue $true -Force
    $broken.Add([pscustomobject]@{
        title       = $event.title
        start       = $event.start
        url         = $event.url
        sources     = $names
        reason      = Get-TvLinkReason $entry
        brokenSince = $entry.brokenSince
        new         = $entry.brokenSince -eq $nowText
      })
  }

  # Forget links nothing has used for 30 days.
  $used = [Collections.Generic.HashSet[string]]::new()
  foreach ($event in $Events) {
    $null = $used.Add("$($event.url)")
    foreach ($source in @($event.sources)) { $null = $used.Add("$($source.url)") }
  }
  foreach ($url in @($State.Keys)) {
    if ($used.Contains($url)) { continue }
    if (($Now - [DateTimeOffset]::Parse($State[$url].checkedAt, $invariant)).TotalDays -ge 30) { $State.Remove($url) }
  }

  [pscustomobject]@{ State = $State; Checked = @($checked); Broken = @($broken) }
}

function Read-TvLinkState {
  # data/links.json as URL to entry. A missing file is an empty state.
  [CmdletBinding()]
  param([Parameter(Mandatory, Position = 0)][string]$Path)

  $state = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $state }
  $text = Get-Content -LiteralPath $Path -Raw
  if ([string]::IsNullOrWhiteSpace($text)) { return $state }
  $links = (ConvertFrom-TvJson $text).links
  foreach ($property in @($links.PSObject.Properties)) {
    $entry = [ordered]@{}
    foreach ($field in $property.Value.PSObject.Properties) { $entry[$field.Name] = $field.Value }
    $state[$property.Name] = $entry
  }
  $state
}

function Write-TvLinkState {
  # Sorted by URL, fields in a fixed order, 2-space JSON with LF, so nightly diffs stay small.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)][string]$Path,
    [Parameter(Mandatory, Position = 1)][AllowEmptyCollection()][hashtable]$State
  )

  $links = [ordered]@{}
  foreach ($url in ([string[]]@($State.Keys) | Sort-Object { $_ } -Culture ([Globalization.CultureInfo]::InvariantCulture))) {
    $entry = $State[$url]
    $out = [ordered]@{}
    foreach ($field in 'verdict', 'status', 'error', 'checkedAt', 'brokenSince', 'failures') {
      if ($null -ne $entry[$field] -and "$($entry[$field])" -ne '') { $out[$field] = $entry[$field] }
    }
    $out.failures = [int]$entry.failures
    $links[$url] = $out
  }
  $json = [ordered]@{ links = $links } | ConvertTo-Json -Depth 4
  [IO.File]::WriteAllText($Path, ($json -replace "`r`n", "`n") + "`n", [Text.UTF8Encoding]::new($false))
}

function ConvertTo-TvLinkSummary {
  # Markdown for the GitHub Actions run summary: broken links grouped by source, new ones first.
  [CmdletBinding()]
  [OutputType([string])]
  param(
    [Parameter(Mandatory, Position = 0)][AllowEmptyCollection()][object[]]$Broken,
    [int]$Checked
  )

  $lines = [Collections.Generic.List[string]]::new()
  $lines.Add('## Broken links')
  $lines.Add('')
  $newCount = @($Broken | Where-Object new).Count
  if ($Broken.Count -eq 0) {
    $lines.Add("$Checked links checked tonight. No broken links.")
    return ($lines -join "`n") + "`n"
  }
  $lines.Add("$Checked links checked tonight. $($Broken.Count) events have a broken link ($newCount new). Their titles show as plain text on the site.")
  $cell = { param($text) ("$text" -replace '\|', '\|' -replace '\s+', ' ').Trim() }
  foreach ($group in ($Broken | Group-Object sources | Sort-Object Name)) {
    $lines.Add('')
    $lines.Add("### $($group.Name)")
    $lines.Add('')
    $lines.Add('| | Event | Date | Link | Problem | Since |')
    $lines.Add('|---|---|---|---|---|---|')
    foreach ($item in ($group.Group | Sort-Object @{ e = { -not $_.new } }, start)) {
      $flag = if ($item.new) { 'New' } else { '' }
      $lines.Add("| $flag | $(& $cell $item.title) | $("$($item.start)".Substring(0, 10)) | $(& $cell $item.url) | $(& $cell $item.reason) | $("$($item.brokenSince)".Substring(0, 10)) |")
    }
  }
  ($lines -join "`n") + "`n"
}
