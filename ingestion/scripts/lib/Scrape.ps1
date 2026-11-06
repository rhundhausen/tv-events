# Helpers for reading event pages: robots.txt rules, and schema.org data embedded in HTML.

. "$PSScriptRoot/Http.ps1"

function Get-TvRobotsGroup {
  # Returns the rules that apply to us: a group naming WeekendBoise if there is one, otherwise *.
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [AllowEmptyString()]
    [string]$Robots
  )

  $groups = [System.Collections.Generic.List[object]]::new()
  $current = $null
  $inAgents = $false

  foreach ($raw in ($Robots -split '\r?\n')) {
    $line = ($raw -replace '#.*$', '').Trim()
    if ($line -notmatch '^(?<key>[A-Za-z-]+)\s*:\s*(?<value>.*)$') { continue }
    $key = $Matches.key.ToLowerInvariant()
    $value = $Matches.value.Trim()

    if ($key -eq 'user-agent') {
      if (-not $inAgents) {
        $current = [pscustomobject]@{ Agents = [System.Collections.Generic.List[string]]::new(); Rules = [System.Collections.Generic.List[object]]::new(); Delay = 0 }
        $groups.Add($current)
      }
      $current.Agents.Add($value.ToLowerInvariant())
      $inAgents = $true
      continue
    }

    $inAgents = $false
    if ($null -eq $current) { continue }
    if ($key -in 'allow', 'disallow' -and $value) {
      $current.Rules.Add([pscustomobject]@{ Allow = ($key -eq 'allow'); Path = $value })
    } elseif ($key -eq 'crawl-delay' -and $value -match '^\d+') {
      $current.Delay = [int]$Matches[0]
    }
  }

  $named = @($groups | Where-Object { $_.Agents -contains 'weekendboise' })
  $selected = if ($named.Count -gt 0) { $named } else { @($groups | Where-Object { $_.Agents -contains '*' }) }
  [pscustomobject]@{
    Rules = @($selected | ForEach-Object { $_.Rules })
    Delay = ($selected | ForEach-Object { $_.Delay } | Measure-Object -Maximum).Maximum
  }
}

function Test-TvRobotsAllowed {
  <#
  .SYNOPSIS
    Tests a path, with its query string, against robots.txt.
  .DESCRIPTION
    Follows RFC 9309: * matches anything, $ anchors the end, the longest matching rule wins, and
    Allow wins a tie. So /*?format=json blocks /calendar?format=json but not /calendar.
  #>
  [CmdletBinding()]
  [OutputType([bool])]
  param(
    [Parameter(Mandatory, Position = 0)]
    [AllowEmptyString()]
    [string]$Robots,

    [Parameter(Mandatory, Position = 1)]
    [string]$Path
  )

  $best = $null
  foreach ($rule in (Get-TvRobotsGroup $Robots).Rules) {
    $pattern = '^' + ([regex]::Escape($rule.Path) -replace '\\\*', '.*')
    if ($pattern.EndsWith('\$')) { $pattern = $pattern.Substring(0, $pattern.Length - 2) + '$' }
    if ($Path -notmatch $pattern) { continue }

    $better = -not $best -or $rule.Path.Length -gt $best.Path.Length -or
      ($rule.Path.Length -eq $best.Path.Length -and $rule.Allow -and -not $best.Allow)
    if ($better) { $best = $rule }
  }
  (-not $best) -or $best.Allow
}

function Get-TvJsonLdEvent {
  <#
  .SYNOPSIS
    Returns the schema.org Event objects embedded in a page as JSON-LD.
  .DESCRIPTION
    Handles a single object, an array, and @graph. A block that isn't valid JSON is skipped,
    because many pages carry unrelated broken blocks.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [AllowEmptyString()]
    [string]$Html
  )

  foreach ($block in [regex]::Matches($Html, '(?is)<script[^>]*application/ld\+json[^>]*>(.*?)</script>')) {
    try {
      $parsed = ConvertFrom-TvJson $block.Groups[1].Value.Trim()
    } catch {
      continue
    }

    $nodes = foreach ($item in @($parsed)) {
      if ($item.PSObject.Properties['@graph']) { @($item.'@graph') } else { $item }
    }
    foreach ($node in $nodes) {
      if (@($node.'@type') -match 'Event$') { $node }
    }
  }
}
