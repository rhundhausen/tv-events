# Cost tiers: free, $, $$, $$$, or unknown. See docs/cost-tiers.md.
#
# Adapters work out priceMin (the cheapest adult ticket, face value) and pass it to New-TvEvent,
# which derives costTier with Get-CostTier. Only the tier is stored, never the price.

# The one place the breakpoints live. Retune them here: free is $0, $ is under Low, $$ is Low up
# to High, $$$ is High or more. Refine copies them into data/meta.json for the site's legend.
$script:CostTierBreakpoints = @{ Low = 15; High = 40 }

function Get-CostTier {
  <#
  .SYNOPSIS
    The cost tier for a price: 'free', '$', '$$', '$$$', or $null when the price is unknown.
  .DESCRIPTION
    The only function that turns a price into a tier. A negative price is unknown.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param([Parameter(Position = 0)][AllowNull()][Nullable[decimal]]$PriceMin)

  if ($null -eq $PriceMin -or $PriceMin -lt 0) { return $null }
  if ($PriceMin -eq 0) { return 'free' }
  if ($PriceMin -lt $script:CostTierBreakpoints.Low) { return '$' }
  if ($PriceMin -lt $script:CostTierBreakpoints.High) { return '$$' }
  '$$$'
}

function ConvertFrom-TvPriceText {
  <#
  .SYNOPSIS
    The cheapest adult ticket in a source's price text, as priceMin, or $null.
  .DESCRIPTION
    Applies the rules in docs/cost-tiers.md:
    - Suggested donation or pay-what-you-can is 0.
    - The word free is 0, so free entry with paid parking or food is free.
    - The text is split into parts at commas, slashes, plus signs, "and", and " - "; a part that
      names kids, children, seniors, students, members, or a fee, parking, or food is not the
      adult ticket. The lowest remaining amount wins, so a range gives its low end.
    - When every amount is a kids, senior, student, or member price, the lowest of those wins.
      Fees and parking never count.
    - A bare number such as "25" is dollars. Text with no amount ("Tickets at the door") is $null.
  .PARAMETER Prose
    The text is an event description, not a price field: the word free counts only as "free
    admission" or "free entry" and similar, because prose says "feel free" and "gluten free".
  #>
  [CmdletBinding()]
  param(
    [Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$Text,
    [switch]$Prose
  )

  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  if ($Text -match '(?i)\b(suggested donation|by donation|donation only|donations? at the door|pay[- ]what[- ]you[- ](can|wish|want))\b') {
    return [decimal]0
  }

  $audience = '(?i)\b(kids?|child(ren)?|youth|teens?|seniors?|students?|members?|military|veterans?|under \d+|ages? \d+)\b'
  $notTicket = '(?i)\b(fees?|service charge|parking|food|drinks?|beer|merch|vendors?)\b'
  $freeWord = if ($Prose) { '(?i)\bfree\s+(admission|entry|entrance|event|to attend|to the public|and open to)\b|\badmission is free\b|\bfree of charge\b' } else { '(?i)\bfree\b' }

  $general = [Collections.Generic.List[decimal]]::new()
  $reduced = [Collections.Generic.List[decimal]]::new()
  # A comma inside a number ("$1,250") is not a separator.
  foreach ($part in ($Text -split '(?i),(?!\d{3}\b)|[;|/()\n+]| - | to |\band\b|\bplus\b|&')) {
    if ($part -match $notTicket) { continue }
    $amounts = [Collections.Generic.List[decimal]]::new()
    foreach ($match in [regex]::Matches($part, '\$\s?(\d[\d,]*(?:\.\d+)?)')) {
      $amounts.Add([decimal]::Parse(($match.Groups[1].Value -replace ',', ''), [Globalization.CultureInfo]::InvariantCulture))
    }
    if ($part -match $freeWord) { $amounts.Add([decimal]0) }
    $isReduced = $part -match $audience
    foreach ($amount in $amounts) {
      if ($isReduced) { $reduced.Add($amount) } else { $general.Add($amount) }
    }
  }

  if ($general.Count) { return ($general | Measure-Object -Minimum).Minimum }
  if ($reduced.Count) { return ($reduced | Measure-Object -Minimum).Minimum }
  if (-not $Prose -and $Text -match '^\s*\$?\s*(\d+(?:\.\d+)?)\s*$') {
    return [decimal]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
  }
  $null
}

function Update-TvLegacyCost {
  <#
  .SYNOPSIS
    Moves events stored before 2026-11-06 to costTier. Returns how many changed.
  .DESCRIPTION
    Older events carry cost (tiers at $25 and $100) and costGuess. Prices were never stored, so
    only the old tiers that mean the same now carry over: free, and $$$ ($100 or more is also $40
    or more). Old $ and $$ and every guess are dropped; the next ingest gives upcoming events
    their tier again.
  #>
  [CmdletBinding()]
  [OutputType([int])]
  param([Parameter(Mandatory, Position = 0)][AllowEmptyCollection()][object[]]$Events)

  $changed = 0
  foreach ($event in $Events) {
    $old = $event.PSObject.Properties['cost']
    $guess = $event.PSObject.Properties['costGuess']
    if (-not $old -and -not $guess) { continue }
    $changed++
    if ($old -and $old.Value -in 'free', '$$$' -and -not $event.PSObject.Properties['costTier']) {
      $event | Add-Member -NotePropertyName costTier -NotePropertyValue $old.Value -Force
    }
    if ($old) { $event.PSObject.Properties.Remove('cost') }
    if ($guess) { $event.PSObject.Properties.Remove('costGuess') }
  }
  $changed
}

function Get-TvCostTierCounts {
  # How many events are in each tier, plus unknown, for refine's report.
  param([Parameter(Mandatory, Position = 0)][AllowEmptyCollection()][object[]]$Events)

  $counts = [ordered]@{ free = 0; '$' = 0; '$$' = 0; '$$$' = 0; unknown = 0 }
  foreach ($event in $Events) {
    $tier = "$($event.costTier)"
    if ($tier -and $counts.Contains($tier)) { $counts[$tier]++ } else { $counts.unknown++ }
  }
  $counts
}
