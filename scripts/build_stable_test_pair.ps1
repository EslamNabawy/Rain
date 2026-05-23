<# 
Builds a local Rain test pair from the current checkout:
  - Windows x64 release bundle
  - Android armeabi-v7a release-mode APK only

This script is for local device validation, not store distribution. By default it
uses the local Android debug keystore to sign the release-mode APK so old devices
can install and test quickly.

Use from repo root:
  pwsh -NoProfile -File scripts\build_stable_test_pair.ps1
  pwsh -NoProfile -File scripts\build_stable_test_pair.ps1 -SkipWindows
  pwsh -NoProfile -File scripts\build_stable_test_pair.ps1 -SkipAndroid
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$DartDefinesFile = '',
  [switch]$SkipWindows,
  [switch]$SkipAndroid,
  [switch]$UseExistingSigning,
  [switch]$SmokeWindows
)

$ErrorActionPreference = 'Stop'
$DemoSignalingEncryptionKey = 'rain-demo-signaling-encryption-key-v1-change-me'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

$AppRoot = Join-Path $RepoRoot 'apps\rain'
$ExampleDefines = Join-Path $AppRoot 'tool\dart_defines.example.json'

function Write-Step([string]$Message) {
  Write-Host "`n[stable_pair] $Message"
}

function New-SignalingKey {
  $bytes = New-Object byte[] 48
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  return [Convert]::ToBase64String($bytes)
}

function Resolve-StableDartDefines {
  if (-not [string]::IsNullOrWhiteSpace($DartDefinesFile)) {
    if (-not (Test-Path -LiteralPath $DartDefinesFile)) {
      throw "Dart defines file not found: $DartDefinesFile"
    }
    $resolved = (Resolve-Path -LiteralPath $DartDefinesFile).Path
    $defines = Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json
  } else {
    if (-not (Test-Path -LiteralPath $ExampleDefines)) {
      throw "Example dart defines file not found: $ExampleDefines"
    }
    $defines = Get-Content -Raw -LiteralPath $ExampleDefines | ConvertFrom-Json
  }

  $key = [string]$defines.RAIN_SIGNALING_ENCRYPTION_KEY
  if (
    [string]::IsNullOrWhiteSpace($key) -or
    $key.Equals($DemoSignalingEncryptionKey, [System.StringComparison]::Ordinal)
  ) {
    $defines.RAIN_SIGNALING_ENCRYPTION_KEY = New-SignalingKey
  }

  if ([string]$defines.RAIN_SIGNALING_ENCRYPTION_KEY -eq $DemoSignalingEncryptionKey) {
    throw 'Stable test builds must not use the demo signaling encryption key.'
  }
  if (([string]$defines.RAIN_SIGNALING_ENCRYPTION_KEY).Length -lt 32) {
    throw 'RAIN_SIGNALING_ENCRYPTION_KEY must be at least 32 characters.'
  }

  $defines.RAIN_ALLOW_PUBLIC_TURN = 'true'
  if ([string]::IsNullOrWhiteSpace([string]$defines.FIREBASE_DATABASE_URL)) {
    $defines.FIREBASE_DATABASE_URL = 'https://rain-8fb4b-default-rtdb.firebaseio.com'
  }

  $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) 'rain-stable-pair-defines.json'
  $defines | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempPath -Encoding utf8NoBOM
  return $tempPath
}

function Use-LocalDebugSigningKey {
  $debugKeystore = Join-Path $env:USERPROFILE '.android\debug.keystore'
  if (-not (Test-Path -LiteralPath $debugKeystore)) {
    throw "Local Android debug keystore not found: $debugKeystore"
  }

  [System.Environment]::SetEnvironmentVariable('RAIN_RELEASE_STORE_FILE', $debugKeystore, 'Process')
  [System.Environment]::SetEnvironmentVariable('RAIN_RELEASE_STORE_PASSWORD', 'android', 'Process')
  [System.Environment]::SetEnvironmentVariable('RAIN_RELEASE_KEY_ALIAS', 'androiddebugkey', 'Process')
  [System.Environment]::SetEnvironmentVariable('RAIN_RELEASE_KEY_PASSWORD', 'android', 'Process')
}

function Invoke-FlutterBuild([string[]]$Arguments) {
  & flutter @Arguments | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "flutter $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Assert-ApkContainsOnlyArmV7([string]$ApkPath) {
  if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "APK not found: $ApkPath"
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
  $archive = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
  try {
    $abis = @(
      $archive.Entries |
        Where-Object { $_.FullName.StartsWith('lib/', [System.StringComparison]::Ordinal) } |
        ForEach-Object { ($_.FullName -split '/')[1] } |
        Sort-Object -Unique
    )
  } finally {
    $archive.Dispose()
  }

  if ($abis.Count -ne 1 -or $abis[0] -ne 'armeabi-v7a') {
    throw "Expected APK to contain only armeabi-v7a native libraries, found: $($abis -join ', ')"
  }
}

function Assert-WindowsBundle([string]$ReleaseDir) {
  foreach ($entry in @(
      'rain.exe',
      'flutter_windows.dll',
      'flutter_webrtc_plugin.dll',
      'libwebrtc.dll',
      'sqlite3.dll',
      'data\app.so',
      'data\flutter_assets'
    )) {
    $path = Join-Path $ReleaseDir $entry
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Windows release bundle is missing: $path"
    }
  }
}

function Invoke-WindowsSmoke([string]$ReleaseDir) {
  $exe = Join-Path $ReleaseDir 'rain.exe'
  $process = Start-Process -FilePath $exe -WorkingDirectory $ReleaseDir -WindowStyle Hidden -PassThru
  Start-Sleep -Seconds 6
  if ($process.HasExited) {
    throw "rain.exe exited during smoke check with code $($process.ExitCode)"
  }
  Stop-Process -Id $process.Id -Force
}

$definesPath = Resolve-StableDartDefines
$defineArg = "--dart-define-from-file=$definesPath"

Write-Step "Using shared dart defines file: $definesPath"
Write-Step 'Both artifacts built by this script will share the same non-demo signaling key.'

Push-Location $AppRoot
try {
  if (-not $SkipWindows) {
    Write-Step 'Building Windows x64 release'
    Invoke-FlutterBuild @('build', 'windows', '--release', $defineArg)
    $windowsReleaseDir = Join-Path $AppRoot 'build\windows\x64\runner\Release'
    Assert-WindowsBundle $windowsReleaseDir
    if ($SmokeWindows) {
      Write-Step 'Smoke checking Windows release'
      Invoke-WindowsSmoke $windowsReleaseDir
    }
    Write-Step "Windows release ready: $windowsReleaseDir"
  }

  if (-not $SkipAndroid) {
    if (-not $UseExistingSigning) {
      Write-Step 'Using local Android debug keystore for test signing'
      Use-LocalDebugSigningKey
    }

    Write-Step 'Building Android armeabi-v7a release-mode APK'
    Invoke-FlutterBuild @(
      'build',
      'apk',
      '--release',
      '--split-per-abi',
      '--target-platform',
      'android-arm',
      $defineArg
    )
    $apkPath = Join-Path $AppRoot 'build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk'
    Assert-ApkContainsOnlyArmV7 $apkPath
    Write-Step "Android v7a APK ready: $apkPath"
  }
} finally {
  Pop-Location
}

Write-Step 'Stable local test pair build complete.'
