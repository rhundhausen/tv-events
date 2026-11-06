#Requires -Version 7.4
<#
.SYNOPSIS
  Emails the summary of an ingest or refine run, with Resend. Run from the repo root.
.DESCRIPTION
  Builds the report from OutDir (run.json for ingest; refine.json and links.json for refine)
  and sources.json, then sends it to REPORT_EMAIL with the RESEND_API_KEY key. Both come from
  environment variables (repository secrets in GitHub Actions), so the address stays out of
  this public repo. When either is unset it warns and sends nothing, so local runs and forks
  still work. A failed send fails the script, so the workflow step shows it.

  A run that stopped before writing its file still gets a short report that says so.

  The OutDir folder is zipped and attached, named like the workflow's artifact: out.zip for ingest,
  refine-out.zip for refine. A zip over MaxAttachmentBytes is left off, and the email says so.
.PARAMETER Kind
  ingest or refine.
.PARAMETER PreviewPath
  Also write the report to <PreviewPath>.txt and <PreviewPath>.html, to look at locally.
.PARAMETER Outcome
  The job status: success, failure, or cancelled. Defaults to the JOB_STATUS environment variable.
.PARAMETER RunUrl
  The workflow run's page. Defaults to the RUN_URL environment variable.
.PARAMETER Trigger
  What started the run (schedule, workflow_dispatch, workflow_run). Defaults to EVENT.
.PARAMETER Source
  The one source an ingest ran, if any. Defaults to SOURCE.
.PARAMETER ZipDir
  Where the attachment zip is written. Defaults to a new temp folder.
.PARAMETER MaxAttachmentBytes
  The largest zip to attach. Resend allows 40 MB per email after base64, which adds a third.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('ingest', 'refine')][string]$Kind,
  [string]$OutDir = './out',
  [string]$SourcesPath = (Join-Path $PSScriptRoot '..' 'sources.json'),
  [string]$PreviewPath,
  [string]$Outcome = $env:JOB_STATUS,
  [string]$RunUrl = $env:RUN_URL,
  [string]$Trigger = $env:EVENT,
  [string]$Source = $env:SOURCE,
  [string]$ZipDir = (Join-Path ([IO.Path]::GetTempPath()) "weekendboise-report-$([guid]::NewGuid().ToString('n'))"),
  [long]$MaxAttachmentBytes = 28MB
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib' 'Report.ps1')

$read = {
  param([string]$Name)
  $path = Join-Path $OutDir $Name
  if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String }
}
$sources = @((Get-Content -LiteralPath $SourcesPath -Raw | ConvertFrom-Json -DateKind String).sources)
$context = @{ Outcome = $Outcome; RunUrl = $RunUrl; Trigger = $Trigger; Source = "$Source".Trim() }

# Zip the output folder, named like the workflow artifact.
$zipName = if ($Kind -eq 'ingest') { 'out.zip' } else { 'refine-out.zip' }
$attachment = $null
$files = @(if (Test-Path -LiteralPath $OutDir) { Get-ChildItem -LiteralPath $OutDir -File -Recurse })
if ($files.Count -eq 0) {
  $context.Attachment = "none, $OutDir has no files"
} else {
  $null = New-Item -ItemType Directory -Force -Path $ZipDir
  $zipPath = Join-Path $ZipDir $zipName
  Compress-Archive -Path (Join-Path $OutDir '*') -DestinationPath $zipPath -Force
  $size = (Get-Item -LiteralPath $zipPath).Length
  $sizeText = if ($size -ge 1MB) { '{0:n1} MB' -f ($size / 1MB) } else { '{0:n0} KB' -f [Math]::Ceiling($size / 1KB) }
  if ($size -gt $MaxAttachmentBytes) {
    $context.Attachment = "none, $zipName is $sizeText, over the $('{0:n0} MB' -f ($MaxAttachmentBytes / 1MB)) limit; download the artifact from the workflow run"
  } else {
    $attachment = $zipPath
    $context.Attachment = "$zipName ($sizeText)"
  }
}

$report = if ($Kind -eq 'ingest') {
  New-TvIngestReport -Run (& $read 'run.json') -Sources $sources -Context $context
} else {
  New-TvRefineReport -Refine (& $read 'refine.json') -Links (& $read 'links.json') -Sources $sources -Context $context
}

if ($PreviewPath) {
  [IO.File]::WriteAllText("$PreviewPath.txt", $report.Text)
  [IO.File]::WriteAllText("$PreviewPath.html", $report.Html)
  Write-Host "Report preview: $PreviewPath.txt and $PreviewPath.html"
}

if (-not $env:RESEND_API_KEY -or -not $env:REPORT_EMAIL) {
  Write-Warning 'RESEND_API_KEY or REPORT_EMAIL is not set, so the report was not emailed'
  exit 0
}

# REPORT_FROM, such as 'WeekendBoise <reports@example.com>', needs a domain verified in Resend.
$from = @{}
if ($env:REPORT_FROM) { $from.From = $env:REPORT_FROM }
$sent = Send-TvReport -Report $report -To $env:REPORT_EMAIL -ApiKey $env:RESEND_API_KEY -Attachment $attachment @from
Write-Host "Emailed '$($report.Subject)' (Resend id $($sent.id))"
