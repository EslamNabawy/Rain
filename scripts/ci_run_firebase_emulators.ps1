param()

$ErrorActionPreference = 'Stop'
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')
$firebaseDir = Join-Path $repoRoot 'backend\firebase'
$firebaseConfig = Join-Path $firebaseDir 'firebase.json'
$firebaseToolsVersion = if ($env:FIREBASE_TOOLS_VERSION) {
  $env:FIREBASE_TOOLS_VERSION
} else {
  '15.18.0'
}

function Get-JavaMajorVersion {
  param(
    [Parameter(Mandatory = $true)]
    [string] $JavaPath
  )

  $versionOutput = & cmd.exe /d /s /c "`"$JavaPath`" -version 2>&1"
  $versionText = $versionOutput | Out-String
  if ($versionText -match 'version "([0-9]+)') {
    return [int] $Matches[1]
  }

  return 0
}

function Ensure-JavaOnPath {
  $candidateDirectories = @()
  if ($env:JAVA_HOME) {
    $candidateDirectories += Join-Path $env:JAVA_HOME 'bin'
  }
  $candidateDirectories += @(
    'C:\Program Files\Android\Android Studio1\jbr\bin',
    'C:\Program Files\Android\Android Studio\jbr\bin',
    'C:\Program Files\Java\jdk-21\bin',
    'C:\Program Files\Eclipse Adoptium\jdk-21*\bin',
    'C:\Program Files\Microsoft\jdk-21*\bin'
  )

  foreach ($pattern in @(
      'C:\Program Files\Java\*\bin',
      'C:\Program Files\Android\Android Studio*\jbr\bin',
      'C:\Program Files\Eclipse Adoptium\*\bin',
      'C:\Program Files\Microsoft\*\bin'
    )) {
    $candidateDirectories += Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
      Sort-Object -Property FullName -Descending |
      ForEach-Object { $_.FullName }
  }

  $currentJava = Get-Command java -ErrorAction SilentlyContinue
  if ($currentJava -and (Get-JavaMajorVersion -JavaPath $currentJava.Source) -ge 21) {
    return
  }

  foreach ($candidate in $candidateDirectories) {
    if ([string]::IsNullOrWhiteSpace($candidate)) {
      continue
    }
    if (-not (Test-Path -LiteralPath $candidate)) {
      continue
    }
    $javaPath = Join-Path $candidate 'java.exe'
    if ((Test-Path -LiteralPath $javaPath) -and (Get-JavaMajorVersion -JavaPath $javaPath) -ge 21) {
      $env:PATH = "$candidate;$env:PATH"
      return
    }
  }

  throw 'Java 21 is required for Firebase emulators, but a compatible java.exe was not found. Install JDK 21 or set JAVA_HOME.'
}

Write-Host '[CI] Starting Firebase emulators (Auth + RTDB) for tests...'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js is required but was not found on PATH.'
}

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
  Write-Host '[CI] Installing firebase-tools...'
  npm install -g "firebase-tools@$firebaseToolsVersion"
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

Ensure-JavaOnPath

firebase --version
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if (-not (Test-Path -LiteralPath $firebaseConfig)) {
  throw "Firebase config not found: $firebaseConfig"
}

if ($env:RUN_TESTS -and $env:RUN_TESTS -ne 'true') {
  Write-Host '[CI] RUN_TESTS is disabled; skipping emulator test run.'
  exit 0
}

Write-Host '[CI] Running Firebase emulator integration tests...'
Push-Location $repoRoot
try {
  $testCommand = 'dart pub get && cd apps/rain && flutter pub get && flutter test test/integration_two_users_end2end_test.dart test/integration_two_devices_handshake_full_test.dart test/integration_voice_signaling_emulator_test.dart --dart-define=RUN_RAIN_INTEGRATION_TESTS=true --reporter expanded'
  firebase --config $firebaseConfig emulators:exec `
    --project rain-8fb4b `
    --only auth,database `
    --non-interactive `
    $testCommand
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  Pop-Location
}
