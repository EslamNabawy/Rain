<#
Runs Flutter tests for the Rain app package from the correct package root.

Use this for isolated app tests, especially tests that touch Drift/SQLite.
Running `flutter test apps\rain\test\...` from the repository root can skip
native asset resolution on Windows.
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [string[]]$TestPath = @(),

  [string]$PlainName,

  [string]$Reporter = 'expanded',

  [switch]$NoPubGet,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$FlutterTestArgs = @()
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path -LiteralPath (Join-Path $scriptRoot '..')
$appRoot = Join-Path $repoRoot 'apps\rain'

if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'pubspec.yaml'))) {
  throw "Rain app package was not found at expected path: $appRoot"
}

function Convert-ToAppRelativeTestPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $trimmed = $Path.Trim('"')
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    return $trimmed
  }

  $rootRelative = Join-Path $repoRoot $trimmed
  $appRelative = Join-Path $appRoot $trimmed

  if ([IO.Path]::IsPathRooted($trimmed)) {
    $fullPath = [IO.Path]::GetFullPath($trimmed)
  } elseif (Test-Path -LiteralPath $rootRelative) {
    $fullPath = [IO.Path]::GetFullPath($rootRelative)
  } elseif (Test-Path -LiteralPath $appRelative) {
    $fullPath = [IO.Path]::GetFullPath($appRelative)
  } elseif ($trimmed -like 'apps\rain\*' -or $trimmed -like 'apps/rain/*') {
    $fullPath = [IO.Path]::GetFullPath($rootRelative)
  } else {
    $fullPath = [IO.Path]::GetFullPath($appRelative)
  }

  $normalizedAppRoot = [IO.Path]::GetFullPath($appRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  if (-not $fullPath.StartsWith($normalizedAppRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Test path must be under apps\rain: $Path"
  }

  return [IO.Path]::GetRelativePath($appRoot, $fullPath)
}

Push-Location -LiteralPath $appRoot
try {
  if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter CLI not found in PATH.'
  }

  if (-not $NoPubGet) {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  }

  $args = @('test')
  foreach ($path in $TestPath) {
    $args += Convert-ToAppRelativeTestPath -Path $path
  }
  if (-not [string]::IsNullOrWhiteSpace($PlainName)) {
    $args += '--plain-name'
    $args += $PlainName
  }
  if (-not [string]::IsNullOrWhiteSpace($Reporter)) {
    $args += '--reporter'
    $args += $Reporter
  }
  $args += $FlutterTestArgs

  Write-Host "Running from $appRoot`: flutter $($args -join ' ')" -ForegroundColor Cyan
  & flutter @args
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
