$ErrorActionPreference = 'Stop'
try {
  Push-Location -Path "apps/mobile_flutter" -ErrorAction Stop
  Write-Host "Running flutter analyze in apps/mobile_flutter..." -ForegroundColor Cyan
  & flutter analyze
  if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter analyze reported issues"
    exit 1
  }
  Pop-Location
  Write-Host "flutter analyze completed successfully" -ForegroundColor Green
  exit 0
} catch {
  Write-Error $_.Exception.Message
  exit 2
}
