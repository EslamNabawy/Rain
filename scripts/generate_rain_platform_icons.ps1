[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$RepoRoot = '',
  [string]$SourceIcon = '',
  [string]$OutputRoot = '',
  [switch]$Apply,
  [switch]$Approved,
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
} else {
  $RepoRoot = (Resolve-Path $RepoRoot).Path
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = $RepoRoot
} else {
  $OutputRoot = (Resolve-Path $OutputRoot).Path
}

if ([string]::IsNullOrWhiteSpace($SourceIcon)) {
  $SourceIcon = Join-Path $RepoRoot 'apps\rain\assets\branding\generated\peer_core_app_icon_1024.png'
} else {
  $SourceIcon = (Resolve-Path $SourceIcon).Path
}

$requiredPreviewAssets = @(
  'apps\rain\assets\branding\generated\peer_core_preview_sheet.png',
  'apps\rain\assets\branding\generated\peer_core_size_check.png'
)

if (-not (Test-Path -LiteralPath $SourceIcon)) {
  throw "Source icon not found: $SourceIcon"
}

foreach ($relativePath in $requiredPreviewAssets) {
  $previewPath = Join-Path $RepoRoot $relativePath
  if (-not (Test-Path -LiteralPath $previewPath)) {
    throw "Preview asset not found: $previewPath"
  }
}

if ($Apply -and -not $Approved) {
  throw 'Platform icon replacement is gated. Re-run with -Apply -Approved only after in-app brand approval.'
}

Add-Type -AssemblyName System.Drawing

function New-IconBitmap {
  param(
    [System.Drawing.Image]$Source,
    [int]$Size
  )

  $bitmap = New-Object System.Drawing.Bitmap $Size, $Size
  $bitmap.SetResolution(96, 96)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

  try {
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage($Source, 0, 0, $Size, $Size)
    return $bitmap
  } finally {
    $graphics.Dispose()
  }
}

function Get-PngBytes {
  param(
    [System.Drawing.Image]$Source,
    [int]$Size
  )

  $bitmap = New-IconBitmap -Source $Source -Size $Size
  $stream = New-Object System.IO.MemoryStream

  try {
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    return ,$stream.ToArray()
  } finally {
    $stream.Dispose()
    $bitmap.Dispose()
  }
}

function Save-Png {
  param(
    [System.Drawing.Image]$Source,
    [int]$Size,
    [string]$DestinationPath
  )

  $bitmap = New-IconBitmap -Source $Source -Size $Size

  try {
    $destinationDirectory = Split-Path $DestinationPath -Parent
    New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    $bitmap.Save($DestinationPath, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $bitmap.Dispose()
  }
}

function Save-Ico {
  param(
    [System.Drawing.Image]$Source,
    [int[]]$Sizes,
    [string]$DestinationPath
  )

  $frames = foreach ($size in $Sizes) {
    [PSCustomObject]@{
      Size = $size
      Bytes = [byte[]](Get-PngBytes -Source $Source -Size $size)
    }
  }

  $destinationDirectory = Split-Path $DestinationPath -Parent
  New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

  $stream = New-Object System.IO.MemoryStream
  $writer = New-Object System.IO.BinaryWriter $stream

  try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$frames.Count)

    $offset = 6 + (16 * $frames.Count)
    foreach ($frame in $frames) {
      $dimension = if ($frame.Size -ge 256) { 0 } else { $frame.Size }
      $writer.Write([byte]$dimension)
      $writer.Write([byte]$dimension)
      $writer.Write([byte]0)
      $writer.Write([byte]0)
      $writer.Write([UInt16]1)
      $writer.Write([UInt16]32)
      $writer.Write([UInt32]$frame.Bytes.Length)
      $writer.Write([UInt32]$offset)
      $offset += $frame.Bytes.Length
    }

    foreach ($frame in $frames) {
      $writer.Write([byte[]]$frame.Bytes)
    }

    [System.IO.File]::WriteAllBytes($DestinationPath, $stream.ToArray())
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

$pngTargets = [ordered]@{
  'apps\rain\android\app\src\main\res\mipmap-mdpi\ic_launcher.png' = 48
  'apps\rain\android\app\src\main\res\mipmap-hdpi\ic_launcher.png' = 72
  'apps\rain\android\app\src\main\res\mipmap-xhdpi\ic_launcher.png' = 96
  'apps\rain\android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png' = 144
  'apps\rain\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png' = 192
  'apps\rain\linux\runner\resources\app_icon.png' = 512
  'apps\rain\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_16.png' = 16
  'apps\rain\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_32.png' = 32
  'apps\rain\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_64.png' = 64
  'apps\rain\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_128.png' = 128
  'apps\rain\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_256.png' = 256
  'apps\rain\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_512.png' = 512
  'apps\rain\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png' = 1024
}

$icoTarget = 'apps\rain\windows\runner\resources\app_icon.ico'
$icoSizes = @(16, 24, 32, 48, 64, 128, 256)

$sourceImage = [System.Drawing.Image]::FromFile($SourceIcon)

try {
  if ($sourceImage.Width -ne 1024 -or $sourceImage.Height -ne 1024) {
    throw "Expected a 1024x1024 source icon. Got $($sourceImage.Width)x$($sourceImage.Height): $SourceIcon"
  }

  Write-Host "[rain-icons] Source: $SourceIcon"
  Write-Host '[rain-icons] Preview assets verified.'

  foreach ($relativePath in $pngTargets.Keys) {
    $destinationPath = Join-Path $OutputRoot $relativePath
    $size = $pngTargets[$relativePath]
    if ($ValidateOnly -or -not $Apply) {
      Write-Host "[rain-icons] Ready PNG ${size}px -> $relativePath"
      continue
    }
    if ($PSCmdlet.ShouldProcess($destinationPath, "Generate ${size}px PNG")) {
      Save-Png -Source $sourceImage -Size $size -DestinationPath $destinationPath
      Write-Host "[rain-icons] Updated $relativePath"
    }
  }

  $icoPath = Join-Path $OutputRoot $icoTarget
  if ($ValidateOnly -or -not $Apply) {
    Write-Host "[rain-icons] Ready ICO $($icoSizes -join ',')px -> $icoTarget"
  } elseif ($PSCmdlet.ShouldProcess($icoPath, 'Generate Windows ICO')) {
    Save-Ico -Source $sourceImage -Sizes $icoSizes -DestinationPath $icoPath
    Write-Host "[rain-icons] Updated $icoTarget"
  }

  if (-not $Apply) {
    Write-Host '[rain-icons] Dry run only. No platform icon files were changed.'
  }
} finally {
  $sourceImage.Dispose()
}
