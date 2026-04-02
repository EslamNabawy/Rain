<# 
PowerShell script to run Flutter tests for all Flutter packages in the Rain monorepo.
Usage: Run from repo root: powershell -ExecutionPolicy Bypass -File scripts/test_all.ps1
This script bootstraps dependencies and runs tests for all Dart/Flutter packages under packages/.
#>
$root = (Get-Location).Path
$packagePaths = @("packages\rain_core","packages\peer_core")
$failed = $false
Write-Host "Rain test runner: testing packages:" ($packagePaths -join ", ")
foreach ($relPath in $packagePaths) {
  $full = Join-Path $root $relPath
  if (-not (Test-Path $full)) {
    Write-Warning "Package path not found: $full"
    continue
  }
  Write-Host "Testing package: $full"
  Push-Location $full
  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter CLI not found in PATH. Please install Flutter and make sure flutter is in PATH."
    $failed = $true
    Pop-Location
    continue
  }
  flutter pub get
  $exit = flutter test
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Tests FAILED for $full"
    $failed = $true
  } else {
    Write-Host "Tests PASSED for $full"
  }
  Pop-Location
}
if ($failed) { exit 1 } else { exit 0 }
