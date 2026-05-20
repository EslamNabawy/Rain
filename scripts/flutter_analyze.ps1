$ErrorActionPreference = 'Stop'
try {
  $root = (Get-Location).Path
  $packagePaths = @(
    "apps\rain",
    "packages\peer_core",
    "packages\protocol_brain",
    "packages\rain_core"
  )
  foreach ($relPath in $packagePaths) {
    $fullPath = Join-Path $root $relPath
    Push-Location -Path $fullPath -ErrorAction Stop
    Write-Host "Running flutter analyze in $relPath..." -ForegroundColor Cyan
    & flutter analyze
    if ($LASTEXITCODE -ne 0) {
      Write-Error "flutter analyze reported issues in $relPath"
      exit 1
    }
    Pop-Location
  }
  Write-Host "flutter analyze completed successfully" -ForegroundColor Green
  exit 0
} catch {
  Write-Error $_.Exception.Message
  exit 2
}
