[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$SourceIcon = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if ([string]::IsNullOrWhiteSpace($SourceIcon)) {
  $SourceIcon = Join-Path $RepoRoot 'apps\rain\macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png'
}

if (-not (Test-Path $SourceIcon)) {
  throw "Source icon not found: $SourceIcon"
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

$androidIcons = [ordered]@{
  'apps\rain\android\app\src\main\res\mipmap-mdpi\ic_launcher.png' = 48
  'apps\rain\android\app\src\main\res\mipmap-hdpi\ic_launcher.png' = 72
  'apps\rain\android\app\src\main\res\mipmap-xhdpi\ic_launcher.png' = 96
  'apps\rain\android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png' = 144
  'apps\rain\android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png' = 192
}

$windowsIconPath = Join-Path $RepoRoot 'apps\rain\windows\runner\resources\app_icon.ico'
$windowsIconSizes = @(16, 24, 32, 48, 64, 128, 256)

$sourceImage = [System.Drawing.Image]::FromFile($SourceIcon)

try {
  foreach ($relativePath in $androidIcons.Keys) {
    $destinationPath = Join-Path $RepoRoot $relativePath
    Save-Png -Source $sourceImage -Size $androidIcons[$relativePath] -DestinationPath $destinationPath
    Write-Host "[sync_app_icons] Updated $relativePath"
  }

  Save-Ico -Source $sourceImage -Sizes $windowsIconSizes -DestinationPath $windowsIconPath
  Write-Host "[sync_app_icons] Updated apps\\rain\\windows\\runner\\resources\\app_icon.ico"
} finally {
  $sourceImage.Dispose()
}
