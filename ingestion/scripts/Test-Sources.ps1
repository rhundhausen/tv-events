#Requires -Version 7.4
<#
.SYNOPSIS
  Validates sources.json against schema/sources.schema.json.
.DESCRIPTION
  Every entry is checked on its own. A problem in a running entry, a duplicate name, or a file
  that doesn't parse fails with a non-zero exit, because ingest can't run safely. A problem in
  any other entry (an idea, a candidate, a ruled-out site) is a warning, so a half-written idea
  never stops the nightly run.
.PARAMETER Path
  Sources file to validate. Defaults to sources.json in the ingestion root.
#>
[CmdletBinding()]
param(
  [string]$Path = (Join-Path $PSScriptRoot '..' 'sources.json')
)

$schemaPath = Join-Path $PSScriptRoot '..' 'schema' 'sources.schema.json'

if (-not (Test-Path -LiteralPath $Path)) {
  Write-Error "Sources file not found: $Path" -ErrorAction Continue
  exit 1
}

$json = Get-Content -LiteralPath $Path -Raw
$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

$document = $null
try {
  $document = $json | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Host "FAIL: Could not parse JSON: $($_.Exception.Message)"
  exit 1
}
$sources = @($document.sources | Where-Object { $_ })

# The file wrapper (the sources array and _comment) must be right before entries are worth checking.
$wrapper = [ordered]@{ sources = @() }
if ($null -ne $document._comment) { $wrapper._comment = $document._comment }
foreach ($property in $document.PSObject.Properties.Name | Where-Object { $_ -notin 'sources', '_comment' }) {
  $wrapper[$property] = $document.$property
}
if (-not ($wrapper | ConvertTo-Json -Depth 3 | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) {
  Write-Host 'FAIL: File does not match schema/sources.schema.json outside the sources list'
  exit 1
}

function Get-SourceLabel {
  param([object]$Entry, [int]$Index)
  $label = if ($Entry.name) { $Entry.name } elseif ($Entry.displayName) { $Entry.displayName } else { '(no displayName)' }
  "entry $Index ($label)"
}

for ($i = 0; $i -lt $sources.Count; $i++) {
  $entry = $sources[$i]
  $single = @{ sources = @($entry) } | ConvertTo-Json -Depth 10
  if ($single | Test-Json -SchemaFile $schemaPath -ErrorAction SilentlyContinue) { continue }

  $message = "$(Get-SourceLabel $entry $i) does not match schema/sources.schema.json"
  if ($entry.status -eq 'running') { $failures.Add($message) } else { $warnings.Add($message) }
}

$sources | Where-Object { $_.name } | Group-Object -Property name | Where-Object Count -gt 1 | ForEach-Object {
  $failures.Add("Duplicate source name: $($_.Name) ($($_.Count) entries)")
}

$sources | Where-Object { $_.displayName -is [string] } | Group-Object { $_.displayName.ToLowerInvariant() } | Where-Object Count -gt 1 | ForEach-Object {
  $warnings.Add("Duplicate displayName, ignoring case: $($_.Group[0].displayName) ($($_.Count) entries)")
}

$warnings | ForEach-Object { Write-Host "WARN: $_" }
if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Host "FAIL: $_" }
  exit 1
}

$byStatus = @($sources | ForEach-Object { if ($_.status) { $_.status } else { 'idea' } } | Group-Object | Sort-Object Name | ForEach-Object { "$($_.Count) $($_.Name)" }) -join ', '
$running = @($sources | Where-Object status -eq 'running').Count
Write-Host "OK: $($sources.Count) sources, $running running ($byStatus)$($warnings.Count ? ", $($warnings.Count) warnings" : '')"
exit 0
