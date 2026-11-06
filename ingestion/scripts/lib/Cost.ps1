# Cost tiers: free, $, $$, $$$. Only the tier is stored, never the price. See data/schema/costs.json.

function Get-TvCostTier {
  # Free is $0, $ is under $25, $$ is $25 to $99, $$$ is $100 or more.
  [CmdletBinding()]
  [OutputType([string])]
  param([Parameter(Mandatory)][double]$Amount)

  if ($Amount -le 0) { return 'free' }
  if ($Amount -lt 25) { return '$' }
  if ($Amount -lt 100) { return '$$' }
  '$$$'
}

function Get-TvLowestAmount {
  # The lowest dollar amount written as $12 or $1,250.50 in the text, or $null.
  param([AllowNull()][AllowEmptyString()][string]$Text)

  $amounts = @([regex]::Matches("$Text", '\$\s?(\d[\d,]*(?:\.\d+)?)') | ForEach-Object {
      [double]::Parse(($_.Groups[1].Value -replace ',', ''), [Globalization.CultureInfo]::InvariantCulture)
    })
  if ($amounts.Count -eq 0) { return $null }
  ($amounts | Measure-Object -Minimum).Minimum
}

function ConvertFrom-TvCostText {
  <#
  .SYNOPSIS
    Reads a source's cost text, such as "$32.75", "$10 - $20", "Free - $20" or "Free", as a tier.
  .DESCRIPTION
    The lowest price decides, and the word free counts as $0. Text with no price, such as
    "Donation" or "Varies", gives $null. A bare number such as "25" is read as dollars.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param([Parameter(Position = 0)][AllowNull()][AllowEmptyString()][string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
  if ($Text -match '(?i)\bfree\b') { return 'free' }
  $lowest = Get-TvLowestAmount $Text
  if ($null -eq $lowest -and $Text -match '^\s*(\d+(?:\.\d+)?)\s*$') {
    $lowest = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
  }
  if ($null -eq $lowest) { return $null }
  Get-TvCostTier -Amount $lowest
}

function Get-TvCostRules {
  if (-not $script:TvCostRules) {
    $path = Join-Path $PSScriptRoot '..' '..' '..' 'data' 'schema' 'costs.json'
    $script:TvCostRules = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
  }
  $script:TvCostRules
}

function Get-TvCostGuess {
  <#
  .SYNOPSIS
    A rough tier from the rules in costs.json, or $null. The first rule that applies wins:
    the source, then the venue (optionally only for some categories), then a tag, then the category.
  #>
  [CmdletBinding()]
  [OutputType([string])]
  param([Parameter(Mandatory, Position = 0)][object]$Event)

  $rules = Get-TvCostRules
  foreach ($name in @($Event.sources | ForEach-Object name)) {
    if ($rules.sources.ContainsKey($name)) { return $rules.sources[$name] }
  }
  $venue = $rules.venues[$Event.venueKey]
  if ($venue -and (-not $venue.categories -or $Event.category -in $venue.categories)) { return $venue.tier }
  foreach ($tag in @($Event.tags)) {
    if ($tag -and $rules.tags.ContainsKey($tag)) { return $rules.tags[$tag] }
  }
  if ($rules.categories.ContainsKey("$($Event.category)")) { return $rules.categories[$Event.category] }
  $null
}

function Set-TvCostGuess {
  # Sets costGuess on events with no cost of their own, and removes it from events that have one.
  # Returns how many events changed.
  [CmdletBinding()]
  [OutputType([int])]
  param([Parameter(Mandatory, Position = 0)][AllowEmptyCollection()][object[]]$Events)

  $changed = 0
  foreach ($event in $Events) {
    $guess = if (-not $event.cost) { Get-TvCostGuess $event }
    $old = if ($event.PSObject.Properties['costGuess']) { $event.costGuess }
    if ($guess -ceq $old) { continue }
    $changed++
    if ($guess) {
      $event | Add-Member -NotePropertyName costGuess -NotePropertyValue $guess -Force
    } else {
      $event.PSObject.Properties.Remove('costGuess')
    }
  }
  $changed
}
