<#
Writes a traceable release metadata JSON file for Rain artifacts.
Use from repo root or a GitHub Actions checkout:
  pwsh -File scripts/write_release_metadata.ps1 -OutputPath artifacts\rain-release-metadata.json -TargetRef dev -TargetSha <sha> -Channel demo -BuildProfile demo -ArtifactPurpose test-artifact -ValidationWorkflow "Build Rain Apps" -ValidationRunUrl <url>
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$OutputPath,
  [string]$RepoRoot = '',
  [string]$TargetRef = '',
  [string]$TargetSha = '',
  [ValidateSet('demo', 'stable')]
  [string]$Channel = 'demo',
  [ValidateSet('demo', 'production')]
  [string]$BuildProfile = 'demo',
  [ValidateSet('test-artifact', 'fast-release', 'validated-release', 'stable-release')]
  [string]$ArtifactPurpose = 'test-artifact',
  [string]$ValidationWorkflow = '',
  [string]$ValidationRunUrl = '',
  [string]$RemoteConfigEvidenceUrl = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-GitValue([string[]]$Arguments) {
  $output = & git @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) {
    return ''
  }
  return ($output | Out-String).Trim()
}

function Resolve-AppVersion([string]$RepoRoot) {
  $pubspecPath = Join-Path $RepoRoot 'apps\rain\pubspec.yaml'
  if (-not (Test-Path -LiteralPath $pubspecPath)) {
    throw "App pubspec.yaml not found: $pubspecPath"
  }

  $pubspec = Get-Content -Raw -LiteralPath $pubspecPath
  $match = [regex]::Match(
    $pubspec,
    '(?m)^version:\s*(?<version>[0-9]+\.[0-9]+\.[0-9]+)\+(?<build>[0-9]+)\s*$'
  )
  if (-not $match.Success) {
    throw 'apps\rain\pubspec.yaml has no valid version: x.y.z+build'
  }

  return @{
    Version = $match.Groups['version'].Value
    Build = [int]$match.Groups['build'].Value
  }
}

Push-Location $RepoRoot
try {
  if ([string]::IsNullOrWhiteSpace($TargetSha)) {
    $TargetSha = Get-GitValue @('rev-parse', 'HEAD')
  }
  if ([string]::IsNullOrWhiteSpace($TargetRef)) {
    $TargetRef = Get-GitValue @('rev-parse', '--abbrev-ref', 'HEAD')
  }
} finally {
  Pop-Location
}

if ([string]::IsNullOrWhiteSpace($TargetSha)) {
  throw 'TargetSha is required when git HEAD cannot be resolved.'
}
if ([string]::IsNullOrWhiteSpace($TargetRef)) {
  throw 'TargetRef is required when git branch/ref cannot be resolved.'
}
if ([string]::IsNullOrWhiteSpace($ValidationWorkflow)) {
  throw 'ValidationWorkflow is required.'
}
if ([string]::IsNullOrWhiteSpace($ValidationRunUrl)) {
  throw 'ValidationRunUrl is required.'
}
if ($BuildProfile -eq 'production' -and $Channel -ne 'stable') {
  throw 'Production release metadata must use stable channel.'
}
if ($BuildProfile -eq 'demo' -and $Channel -ne 'demo') {
  throw 'Demo release metadata must use demo channel.'
}

$appVersion = Resolve-AppVersion $RepoRoot
$metadata = [ordered]@{
  schema = 'rain.release.metadata.v1'
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  targetRef = $TargetRef
  targetSha = $TargetSha
  appVersion = $appVersion.Version
  appBuild = $appVersion.Build
  updateChannel = $Channel
  buildProfile = $BuildProfile
  artifactPurpose = $ArtifactPurpose
  validationWorkflow = $ValidationWorkflow
  validationRunUrl = $ValidationRunUrl
  remoteConfigEvidenceUrl = $RemoteConfigEvidenceUrl
}

$resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath
} else {
  Join-Path $RepoRoot $OutputPath
}
$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$metadata |
  ConvertTo-Json -Depth 10 |
  Set-Content -LiteralPath $resolvedOutputPath -Encoding utf8NoBOM

Write-Host "Wrote release metadata: $resolvedOutputPath"
