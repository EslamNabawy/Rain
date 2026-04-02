<# 
Builds Rain release artifacts in a clean, repeatable way.
Use from repo root:
  pwsh -File scripts/build_release.ps1 -Platform all
  pwsh -File scripts/build_release.ps1 -Platform windows
  pwsh -File scripts/build_release.ps1 -Platform android
#>
[CmdletBinding()]
param(
  [ValidateSet('all', 'windows', 'android')]
  [string]$Platform = 'all',
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$OutputDir = (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'final product'),
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
  Write-Host "`n[build_release] $Message"
}

function Ensure-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found on PATH: $Name"
  }
}

function Invoke-InDir([string]$Path, [scriptblock]$Script) {
  Push-Location $Path
  try {
    & $Script
  } finally {
    Pop-Location
  }
}

$repoRoot = $RepoRoot
$appsRoot = Join-Path $repoRoot 'apps\rain'
$releaseRoot = $OutputDir

Ensure-Command flutter
Ensure-Command dart
Ensure-Command git

if ($Clean -or (Test-Path $releaseRoot)) {
  Write-Step "Cleaning output directory: $releaseRoot"
  if (Test-Path $releaseRoot) {
    Remove-Item -LiteralPath $releaseRoot -Recurse -Force
  }
}

New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null

Write-Step "Bootstrapping dependencies"
Invoke-InDir $repoRoot {
  dart pub global activate melos | Out-Host
  melos bootstrap | Out-Host
}

if ($Platform -in @('all', 'windows')) {
  Write-Step "Building Windows release"
  Invoke-InDir $appsRoot {
    flutter build windows --release | Out-Host
  }

  $windowsReleaseDir = Join-Path $appsRoot 'build\windows\x64\runner\Release'
  $windowsZip = Join-Path $releaseRoot 'Rain-windows-portable.zip'

  if (-not (Test-Path $windowsReleaseDir)) {
    throw "Windows release folder not found: $windowsReleaseDir"
  }

  if (Test-Path $windowsZip) {
    Remove-Item -LiteralPath $windowsZip -Force
  }

  Write-Step "Packaging portable Windows zip"
  Compress-Archive -Path (Join-Path $windowsReleaseDir '*') -DestinationPath $windowsZip -Force
}

if ($Platform -in @('all', 'android')) {
  Write-Step "Building Android release APK"
  Invoke-InDir $appsRoot {
    flutter build apk --release | Out-Host
  }

  $apkSource = Join-Path $appsRoot 'build\app\outputs\flutter-apk\app-release.apk'
  $apkDestination = Join-Path $releaseRoot 'Rain-release-android.apk'

  if (-not (Test-Path $apkSource)) {
    throw "Android release APK not found: $apkSource"
  }

  Copy-Item -LiteralPath $apkSource -Destination $apkDestination -Force
}

Write-Step "Release artifacts are ready in $releaseRoot"
