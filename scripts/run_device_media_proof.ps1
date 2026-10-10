param(
  [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$Udid = 'emulator-5554',
  [string]$AvdName = 'Pixel_9_API_36_1',
  [string]$PackageName = 'com.rainapp.rain',
  [switch]$LaunchEmulator,
  [switch]$AudioOnly,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
  Write-Host ""
  Write-Host "[device-media-proof] $Message"
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments, [string]$WorkingDirectory) {
  Write-Host "> $FilePath $($Arguments -join ' ')"
  Push-Location $WorkingDirectory
  try {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
  } finally {
    Pop-Location
  }
}

$appRoot = Join-Path $ProjectRoot 'apps\rain'
if (-not (Test-Path -LiteralPath $appRoot)) {
  throw "Rain app root not found: $appRoot"
}

if ($LaunchEmulator) {
  Write-Step "Launching Android emulator $AvdName"
  & flutter emulators --launch $AvdName | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to launch Android emulator '$AvdName'."
  }
}

Write-Step "Checking Android device $Udid"
$escapedUdid = [regex]::Escape($Udid)
$deadline = (Get-Date).AddSeconds(90)
do {
  $devices = & adb devices
  if ($LASTEXITCODE -ne 0) {
    throw 'adb devices failed.'
  }
  if ($devices -match "^$escapedUdid\s+device$") {
    $deviceReady = $true
    break
  }
  Start-Sleep -Seconds 2
} while ((Get-Date) -lt $deadline)

if (-not $deviceReady) {
  throw "Android device '$Udid' is not attached. Start an emulator or pass -Udid."
}

if (-not $SkipBuild) {
  Write-Step "Building debug APK"
  Invoke-Checked 'flutter' @('build', 'apk', '--debug') $appRoot

  Write-Step "Installing debug APK before permission grant"
  $debugApk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-debug.apk'
  if (-not (Test-Path -LiteralPath $debugApk)) {
    throw "Debug APK not found: $debugApk"
  }
  Invoke-Checked 'adb' @('-s', $Udid, 'install', '-r', '-g', $debugApk) $appRoot
}

if ($SkipBuild) {
  $installedPackage = & adb -s $Udid shell pm list packages $PackageName
  if ($LASTEXITCODE -ne 0 -or -not ($installedPackage -match [regex]::Escape($PackageName))) {
    throw "Package '$PackageName' is not installed on '$Udid'. Rerun without -SkipBuild."
  }
}

Write-Step "Granting runtime media permissions"
foreach ($permission in @('android.permission.CAMERA', 'android.permission.RECORD_AUDIO')) {
  & adb -s $Udid shell pm grant $PackageName $permission | Out-Host
}
foreach ($appOp in @('CAMERA', 'RECORD_AUDIO')) {
  & adb -s $Udid shell appops set $PackageName $appOp allow | Out-Host
}

$proofArgs = @(
  'test',
  'integration_test\device_media_reality_proof_test.dart',
  '-d',
  $Udid,
  '--dart-define=RAIN_DEVICE_MEDIA_PROOF=true',
  '--no-uninstall',
  '--reporter',
  'expanded'
)
if ($AudioOnly) {
  $proofArgs += '--dart-define=RAIN_DEVICE_MEDIA_REQUIRE_VIDEO=false'
}

Write-Step "Running opt-in device media proof"
Invoke-Checked 'flutter' $proofArgs $appRoot

Write-Step "Device media proof passed"
