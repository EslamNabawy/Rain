[CmdletBinding(SupportsShouldProcess)]
param(
  [switch]$IncludeFinalProduct
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$relativePaths = @(
  '.dart_tool',
  'apps/rain/.dart_tool',
  'apps/rain/build',
  'apps/rain/coverage',
  'packages/peer_core/.dart_tool',
  'packages/peer_core/build',
  'packages/peer_core/coverage',
  'packages/protocol_brain/.dart_tool',
  'packages/protocol_brain/build',
  'packages/protocol_brain/coverage',
  'packages/rain_core/.dart_tool',
  'packages/rain_core/build',
  'packages/rain_core/coverage',
  'backend/firebase/functions/node_modules',
  'build/github-artifacts-26197760726',
  'build/test_cache',
  'build/actionlint-1.7.8',
  'build/native_assets',
  'build/unit_test_assets'
)

if ($IncludeFinalProduct) {
  $relativePaths += 'final product'
}

foreach ($relative in $relativePaths) {
  $target = Join-Path $repo $relative
  if (-not (Test-Path -LiteralPath $target)) {
    continue
  }

  $resolved = (Resolve-Path -LiteralPath $target).Path
  if (-not $resolved.StartsWith($repo, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove outside repo: $resolved"
  }

  if ($PSCmdlet.ShouldProcess($resolved, 'Remove generated workspace output')) {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}
