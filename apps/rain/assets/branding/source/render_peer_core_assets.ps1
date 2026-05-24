[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$SourceDir = Split-Path -Parent $PSCommandPath
$BrandingDir = Split-Path -Parent $SourceDir
$GeneratedDir = Join-Path $BrandingDir 'generated'

New-Item -ItemType Directory -Force -Path $SourceDir, $GeneratedDir | Out-Null

function Write-Utf8NoBom {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

$peerCoreMarkSvg = @'
<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="peerCoreRing" x1="240" y1="180" x2="808" y2="844" gradientUnits="userSpaceOnUse">
      <stop stop-color="#D7F9FF"/>
      <stop offset="0.48" stop-color="#7DEBFF"/>
      <stop offset="1" stop-color="#2DD4A3"/>
    </linearGradient>
  </defs>
  <circle cx="512" cy="512" r="328" stroke="url(#peerCoreRing)" stroke-width="72"/>
  <path d="M410 584L614 441L645 645L410 584Z" stroke="#FCFEFF" stroke-opacity="0.82" stroke-width="42" stroke-linejoin="round"/>
  <circle cx="410" cy="584" r="72" fill="#2DD4A3"/>
  <circle cx="614" cy="441" r="72" fill="#2DD4A3"/>
  <circle cx="645" cy="645" r="72" fill="#2DD4A3"/>
  <circle cx="410" cy="584" r="26" fill="#061017" fill-opacity="0.92"/>
  <circle cx="614" cy="441" r="26" fill="#061017" fill-opacity="0.92"/>
  <circle cx="645" cy="645" r="26" fill="#061017" fill-opacity="0.92"/>
</svg>
'@

$peerCoreTinySvg = @'
<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="peerCoreTinyRing" x1="240" y1="180" x2="808" y2="844" gradientUnits="userSpaceOnUse">
      <stop stop-color="#D7F9FF"/>
      <stop offset="0.52" stop-color="#7DEBFF"/>
      <stop offset="1" stop-color="#2DD4A3"/>
    </linearGradient>
  </defs>
  <circle cx="512" cy="512" r="328" stroke="url(#peerCoreTinyRing)" stroke-width="92"/>
  <circle cx="512" cy="512" r="132" fill="#2DD4A3"/>
  <circle cx="512" cy="512" r="48" fill="#061017" fill-opacity="0.92"/>
</svg>
'@

$peerCoreMonoSvg = @'
<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <circle cx="512" cy="512" r="328" stroke="currentColor" stroke-width="72"/>
  <path d="M410 584L614 441L645 645L410 584Z" stroke="currentColor" stroke-width="42" stroke-linejoin="round"/>
  <circle cx="410" cy="584" r="72" fill="currentColor"/>
  <circle cx="614" cy="441" r="72" fill="currentColor"/>
  <circle cx="645" cy="645" r="72" fill="currentColor"/>
</svg>
'@

$peerCoreAppIconSvg = @'
<svg width="1024" height="1024" viewBox="0 0 1024 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="appBg" x1="0" y1="0" x2="1024" y2="1024" gradientUnits="userSpaceOnUse">
      <stop stop-color="#061017"/>
      <stop offset="1" stop-color="#0A1E26"/>
    </linearGradient>
    <linearGradient id="appRing" x1="250" y1="170" x2="790" y2="830" gradientUnits="userSpaceOnUse">
      <stop stop-color="#D7F9FF"/>
      <stop offset="0.48" stop-color="#7DEBFF"/>
      <stop offset="1" stop-color="#2DD4A3"/>
    </linearGradient>
    <clipPath id="clip">
      <rect width="1024" height="1024" rx="230"/>
    </clipPath>
  </defs>
  <g clip-path="url(#clip)">
    <rect width="1024" height="1024" fill="url(#appBg)"/>
    <path d="M70 -40L250 1080M230 -40L410 1080M390 -40L570 1080M550 -40L730 1080M710 -40L890 1080M870 -40L1050 1080" stroke="#7DEBFF" stroke-opacity="0.13" stroke-width="6"/>
    <circle cx="512" cy="512" r="420" stroke="#7DEBFF" stroke-opacity="0.10" stroke-width="3"/>
    <circle cx="512" cy="512" r="356" stroke="#7DEBFF" stroke-opacity="0.13" stroke-width="3"/>
    <circle cx="512" cy="512" r="286" stroke="url(#appRing)" stroke-width="68"/>
    <path d="M423 575L601 451L628 629L423 575Z" stroke="#FCFEFF" stroke-opacity="0.84" stroke-width="38" stroke-linejoin="round"/>
    <circle cx="423" cy="575" r="64" fill="#2DD4A3"/>
    <circle cx="601" cy="451" r="64" fill="#2DD4A3"/>
    <circle cx="628" cy="629" r="64" fill="#2DD4A3"/>
    <circle cx="423" cy="575" r="23" fill="#061017" fill-opacity="0.92"/>
    <circle cx="601" cy="451" r="23" fill="#061017" fill-opacity="0.92"/>
    <circle cx="628" cy="629" r="23" fill="#061017" fill-opacity="0.92"/>
  </g>
</svg>
'@

$peerCoreSplashLockupSvg = @'
<svg width="1440" height="1024" viewBox="0 0 1440 1024" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="splashBg" x1="0" y1="0" x2="1440" y2="1024" gradientUnits="userSpaceOnUse">
      <stop stop-color="#061017"/>
      <stop offset="1" stop-color="#0A1E26"/>
    </linearGradient>
    <linearGradient id="splashRing" x1="580" y1="190" x2="860" y2="510" gradientUnits="userSpaceOnUse">
      <stop stop-color="#D7F9FF"/>
      <stop offset="0.5" stop-color="#7DEBFF"/>
      <stop offset="1" stop-color="#2DD4A3"/>
    </linearGradient>
  </defs>
  <rect width="1440" height="1024" fill="url(#splashBg)"/>
  <path d="M120 -80L320 1120M360 -80L560 1120M600 -80L800 1120M840 -80L1040 1120M1080 -80L1280 1120" stroke="#7DEBFF" stroke-opacity="0.08" stroke-width="5"/>
  <circle cx="720" cy="348" r="194" stroke="#7DEBFF" stroke-opacity="0.12" stroke-width="3"/>
  <circle cx="720" cy="348" r="154" stroke="#7DEBFF" stroke-opacity="0.18" stroke-width="3"/>
  <circle cx="720" cy="348" r="116" stroke="url(#splashRing)" stroke-width="26"/>
  <path d="M684 374L756 324L767 396L684 374Z" stroke="#FCFEFF" stroke-opacity="0.82" stroke-width="16" stroke-linejoin="round"/>
  <circle cx="684" cy="374" r="26" fill="#2DD4A3"/>
  <circle cx="756" cy="324" r="26" fill="#2DD4A3"/>
  <circle cx="767" cy="396" r="26" fill="#2DD4A3"/>
  <circle cx="684" cy="374" r="9" fill="#061017" fill-opacity="0.92"/>
  <circle cx="756" cy="324" r="9" fill="#061017" fill-opacity="0.92"/>
  <circle cx="767" cy="396" r="9" fill="#061017" fill-opacity="0.92"/>
  <text x="720" y="632" text-anchor="middle" fill="#FCFEFF" font-family="Space Grotesk, Inter, Arial, sans-serif" font-size="88" font-weight="800" letter-spacing="0">Rain</text>
  <text x="720" y="690" text-anchor="middle" fill="#FCFEFF" fill-opacity="0.72" font-family="Inter, Arial, sans-serif" font-size="28" font-weight="500" letter-spacing="0">Private peer link</text>
</svg>
'@

$rainStreakTreatmentSvg = @'
<svg width="1024" height="512" viewBox="0 0 1024 512" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="stateBg" x1="0" y1="0" x2="1024" y2="512" gradientUnits="userSpaceOnUse">
      <stop stop-color="#061017"/>
      <stop offset="1" stop-color="#0A1E26"/>
    </linearGradient>
    <clipPath id="pillClip">
      <rect x="224" y="180" width="576" height="152" rx="76"/>
    </clipPath>
  </defs>
  <rect width="1024" height="512" fill="url(#stateBg)"/>
  <rect x="224" y="180" width="576" height="152" rx="76" fill="#7DEBFF" fill-opacity="0.11" stroke="#7DEBFF" stroke-opacity="0.34" stroke-width="4"/>
  <g clip-path="url(#pillClip)">
    <path d="M200 80L270 430M300 80L370 430M400 80L470 430M500 80L570 430M600 80L670 430M700 80L770 430M800 80L870 430" stroke="#FCFEFF" stroke-opacity="0.15" stroke-width="6"/>
  </g>
  <circle cx="316" cy="256" r="32" stroke="#7DEBFF" stroke-width="8"/>
  <circle cx="304" cy="266" r="6" fill="#2DD4A3"/>
  <circle cx="326" cy="250" r="6" fill="#2DD4A3"/>
  <circle cx="334" cy="270" r="6" fill="#2DD4A3"/>
  <text x="384" y="270" fill="#FCFEFF" font-family="Space Grotesk, Inter, Arial, sans-serif" font-size="42" font-weight="700">Rain Streak active state</text>
</svg>
'@

$previewSheetSvg = @'
<svg width="1800" height="1200" viewBox="0 0 1800 1200" fill="none" xmlns="http://www.w3.org/2000/svg">
  <rect width="1800" height="1200" fill="#061017"/>
  <text x="80" y="110" fill="#FCFEFF" font-family="Space Grotesk, Inter, Arial, sans-serif" font-size="64" font-weight="800">Rain Peer Core Asset Pack</text>
  <text x="80" y="158" fill="#FCFEFF" fill-opacity="0.66" font-family="Inter, Arial, sans-serif" font-size="28">Signal Mist / Peer Core / Rain Streak active states</text>
  <g transform="translate(80 240)">
    <rect width="420" height="420" rx="92" fill="#0A1E26"/>
    <path d="M20 -30L100 470M120 -30L200 470M220 -30L300 470M320 -30L400 470M420 -30L500 470" stroke="#7DEBFF" stroke-opacity="0.13" stroke-width="4"/>
    <circle cx="210" cy="210" r="118" stroke="#7DEBFF" stroke-width="30"/>
    <path d="M174 235L247 184L258 258L174 235Z" stroke="#FCFEFF" stroke-opacity="0.82" stroke-width="16" stroke-linejoin="round"/>
    <circle cx="174" cy="235" r="26" fill="#2DD4A3"/>
    <circle cx="247" cy="184" r="26" fill="#2DD4A3"/>
    <circle cx="258" cy="258" r="26" fill="#2DD4A3"/>
    <text x="0" y="484" fill="#FCFEFF" fill-opacity="0.72" font-family="Inter, Arial, sans-serif" font-size="24">App icon source</text>
  </g>
  <g transform="translate(620 250)">
    <circle cx="140" cy="140" r="112" stroke="#7DEBFF" stroke-width="24"/>
    <path d="M105 165L175 116L186 186L105 165Z" stroke="#FCFEFF" stroke-opacity="0.82" stroke-width="14" stroke-linejoin="round"/>
    <circle cx="105" cy="165" r="24" fill="#2DD4A3"/>
    <circle cx="175" cy="116" r="24" fill="#2DD4A3"/>
    <circle cx="186" cy="186" r="24" fill="#2DD4A3"/>
    <text x="0" y="330" fill="#FCFEFF" fill-opacity="0.72" font-family="Inter, Arial, sans-serif" font-size="24">Full mark</text>
  </g>
  <g transform="translate(1000 260)">
    <circle cx="110" cy="110" r="88" stroke="#7DEBFF" stroke-width="26"/>
    <circle cx="110" cy="110" r="34" fill="#2DD4A3"/>
    <text x="0" y="270" fill="#FCFEFF" fill-opacity="0.72" font-family="Inter, Arial, sans-serif" font-size="24">Tiny mark</text>
  </g>
  <g transform="translate(1330 270)">
    <circle cx="80" cy="80" r="68" stroke="#7DEBFF" stroke-opacity="0.18" stroke-width="2"/>
    <circle cx="80" cy="80" r="54" stroke="#7DEBFF" stroke-opacity="0.28" stroke-width="2"/>
    <circle cx="80" cy="80" r="42" stroke="#7DEBFF" stroke-width="10"/>
    <path d="M67 89L94 70L98 98L67 89Z" stroke="#FCFEFF" stroke-opacity="0.82" stroke-width="6" stroke-linejoin="round"/>
    <circle cx="67" cy="89" r="9" fill="#2DD4A3"/>
    <circle cx="94" cy="70" r="9" fill="#2DD4A3"/>
    <circle cx="98" cy="98" r="9" fill="#2DD4A3"/>
    <text x="-18" y="210" fill="#FCFEFF" fill-opacity="0.72" font-family="Inter, Arial, sans-serif" font-size="24">Wave emission</text>
  </g>
  <g transform="translate(80 820)">
    <rect width="1640" height="180" rx="90" fill="#7DEBFF" fill-opacity="0.11" stroke="#7DEBFF" stroke-opacity="0.34" stroke-width="4"/>
    <path d="M-20 -40L40 220M120 -40L180 220M260 -40L320 220M400 -40L460 220M540 -40L600 220M680 -40L740 220M820 -40L880 220M960 -40L1020 220M1100 -40L1160 220M1240 -40L1300 220M1380 -40L1440 220M1520 -40L1580 220" stroke="#FCFEFF" stroke-opacity="0.13" stroke-width="6"/>
    <text x="80" y="108" fill="#FCFEFF" font-family="Space Grotesk, Inter, Arial, sans-serif" font-size="54" font-weight="700">Rain Streak active state treatment</text>
  </g>
</svg>
'@

Write-Utf8NoBom (Join-Path $SourceDir 'peer_core_mark.svg') $peerCoreMarkSvg
Write-Utf8NoBom (Join-Path $SourceDir 'peer_core_mark_tiny.svg') $peerCoreTinySvg
Write-Utf8NoBom (Join-Path $SourceDir 'peer_core_mark_mono.svg') $peerCoreMonoSvg
Write-Utf8NoBom (Join-Path $SourceDir 'peer_core_app_icon.svg') $peerCoreAppIconSvg
Write-Utf8NoBom (Join-Path $SourceDir 'peer_core_splash_lockup.svg') $peerCoreSplashLockupSvg
Write-Utf8NoBom (Join-Path $SourceDir 'rain_streak_treatment.svg') $rainStreakTreatmentSvg
Write-Utf8NoBom (Join-Path $SourceDir 'peer_core_preview_sheet.svg') $previewSheetSvg

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

function Color-Html {
  param([string]$Hex, [int]$Alpha = 255)
  $base = [System.Drawing.ColorTranslator]::FromHtml($Hex)
  [System.Drawing.Color]::FromArgb($Alpha, $base.R, $base.G, $base.B)
}

function New-RoundedRectPath {
  param([float]$X, [float]$Y, [float]$W, [float]$H, [float]$R)
  $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $d = $R * 2
  $path.AddArc($X, $Y, $d, $d, 180, 90)
  $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
  $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
  $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $path
}

function Set-HighQuality {
  param([System.Drawing.Graphics]$Graphics)
  $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $Graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
}

function Draw-PeerCoreMark {
  param(
    [System.Drawing.Graphics]$Graphics,
    [float]$CenterX,
    [float]$CenterY,
    [float]$Size,
    [bool]$Tiny = $false
  )

  $ringRadius = $Size * 0.32
  $ringWidth = if ($Tiny) { $Size * 0.09 } else { $Size * 0.07 }
  $ringPen = [System.Drawing.Pen]::new((Color-Html '#7DEBFF'), $ringWidth)
  $Graphics.DrawEllipse(
    $ringPen,
    $CenterX - $ringRadius,
    $CenterY - $ringRadius,
    $ringRadius * 2,
    $ringRadius * 2
  )
  $ringPen.Dispose()

  if ($Tiny) {
    $dotBrush = [System.Drawing.SolidBrush]::new((Color-Html '#2DD4A3'))
    $dotRadius = $Size * 0.13
    $Graphics.FillEllipse($dotBrush, $CenterX - $dotRadius, $CenterY - $dotRadius, $dotRadius * 2, $dotRadius * 2)
    $dotBrush.Dispose()
    return
  }

  $points = @(
    [System.Drawing.PointF]::new($CenterX - $Size * 0.10, $CenterY + $Size * 0.07),
    [System.Drawing.PointF]::new($CenterX + $Size * 0.10, $CenterY - $Size * 0.07),
    [System.Drawing.PointF]::new($CenterX + $Size * 0.13, $CenterY + $Size * 0.13)
  )

  $linePen = [System.Drawing.Pen]::new((Color-Html '#FCFEFF' 210), $Size * 0.04)
  $Graphics.DrawPolygon($linePen, $points)
  $linePen.Dispose()

  $nodeBrush = [System.Drawing.SolidBrush]::new((Color-Html '#2DD4A3'))
  $coreBrush = [System.Drawing.SolidBrush]::new((Color-Html '#061017' 235))
  $nodeRadius = $Size * 0.07
  $coreRadius = $Size * 0.025

  foreach ($point in $points) {
    $Graphics.FillEllipse($nodeBrush, $point.X - $nodeRadius, $point.Y - $nodeRadius, $nodeRadius * 2, $nodeRadius * 2)
    $Graphics.FillEllipse($coreBrush, $point.X - $coreRadius, $point.Y - $coreRadius, $coreRadius * 2, $coreRadius * 2)
  }

  $nodeBrush.Dispose()
  $coreBrush.Dispose()
}

function Draw-Waves {
  param(
    [System.Drawing.Graphics]$Graphics,
    [float]$CenterX,
    [float]$CenterY,
    [float]$Size
  )

  foreach ($wave in @(
    @{ Radius = 0.42; Alpha = 48 },
    @{ Radius = 0.52; Alpha = 32 },
    @{ Radius = 0.63; Alpha = 18 }
  )) {
    $radius = $Size * [float]$wave.Radius
    $pen = [System.Drawing.Pen]::new((Color-Html '#7DEBFF' ([int]$wave.Alpha)), [Math]::Max(1.0, $Size * 0.006))
    $Graphics.DrawEllipse($pen, $CenterX - $radius, $CenterY - $radius, $radius * 2, $radius * 2)
    $pen.Dispose()
  }
}

function Save-Png {
  param(
    [string]$Path,
    [int]$Width,
    [int]$Height,
    [scriptblock]$Draw
  )

  $bitmap = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  Set-HighQuality $graphics
  $graphics.Clear([System.Drawing.Color]::Transparent)
  & $Draw $graphics
  $graphics.Dispose()
  $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bitmap.Dispose()
}

function Draw-AppIcon {
  param([System.Drawing.Graphics]$Graphics, [int]$Size)

  $path = New-RoundedRectPath 0 0 $Size $Size ($Size * 0.225)
  $bgBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
    [System.Drawing.RectangleF]::new(0, 0, $Size, $Size),
    (Color-Html '#061017'),
    (Color-Html '#0A1E26'),
    45
  )
  $Graphics.FillPath($bgBrush, $path)
  $bgBrush.Dispose()

  $previousClip = $Graphics.Clip
  $Graphics.SetClip($path)
  $streakPen = [System.Drawing.Pen]::new((Color-Html '#7DEBFF' 34), [Math]::Max(1.0, $Size * 0.006))
  for ($x = -$Size; $x -lt $Size * 2; $x += $Size / 6.4) {
    $Graphics.DrawLine($streakPen, [float]$x, [float](-$Size * 0.08), [float]($x + $Size * 0.19), [float]($Size * 1.08))
  }
  $streakPen.Dispose()
  Draw-Waves $Graphics ($Size / 2) ($Size / 2) ($Size * 0.98)
  Draw-PeerCoreMark $Graphics ($Size / 2) ($Size / 2) ($Size * 0.9) $false
  $Graphics.Clip = $previousClip
  $path.Dispose()
}

foreach ($size in @(16, 24, 48, 192, 1024)) {
  Save-Png (Join-Path $GeneratedDir "peer_core_mark_$size.png") $size $size {
    param($g)
    Draw-PeerCoreMark $g ($size / 2) ($size / 2) ($size * 0.98) ($size -le 24)
  }
}

foreach ($size in @(16, 24, 48, 192)) {
  Save-Png (Join-Path $GeneratedDir "peer_core_mark_tiny_$size.png") $size $size {
    param($g)
    Draw-PeerCoreMark $g ($size / 2) ($size / 2) ($size * 0.98) $true
  }
}

foreach ($size in @(192, 256, 512, 1024)) {
  Save-Png (Join-Path $GeneratedDir "peer_core_app_icon_$size.png") $size $size {
    param($g)
    Draw-AppIcon $g $size
  }
}

Save-Png (Join-Path $GeneratedDir 'peer_core_preview_sheet.png') 1800 1200 {
  param($g)

  $bg = [System.Drawing.SolidBrush]::new((Color-Html '#061017'))
  $g.FillRectangle($bg, 0, 0, 1800, 1200)
  $bg.Dispose()

  $titleFont = [System.Drawing.Font]::new('Segoe UI', 54, [System.Drawing.FontStyle]::Bold)
  $subtitleFont = [System.Drawing.Font]::new('Segoe UI', 24, [System.Drawing.FontStyle]::Regular)
  $labelFont = [System.Drawing.Font]::new('Segoe UI', 20, [System.Drawing.FontStyle]::Regular)
  $titleBrush = [System.Drawing.SolidBrush]::new((Color-Html '#FCFEFF'))
  $mutedBrush = [System.Drawing.SolidBrush]::new((Color-Html '#FCFEFF' 170))

  $g.DrawString('Rain Peer Core Asset Pack', $titleFont, $titleBrush, 80, 70)
  $g.DrawString('Signal Mist / Peer Core / Rain Streak active states', $subtitleFont, $mutedBrush, 82, 146)

  $iconRect = [System.Drawing.RectangleF]::new(80, 240, 420, 420)
  $g.TranslateTransform($iconRect.X, $iconRect.Y)
  Draw-AppIcon $g 420
  $g.ResetTransform()
  $g.DrawString('App icon source', $labelFont, $mutedBrush, 80, 684)

  Draw-PeerCoreMark $g 760 390 360 $false
  $g.DrawString('Full mark', $labelFont, $mutedBrush, 620, 610)

  Draw-PeerCoreMark $g 1110 390 280 $true
  $g.DrawString('Tiny mark', $labelFont, $mutedBrush, 1000, 610)

  Draw-Waves $g 1430 390 270
  Draw-PeerCoreMark $g 1430 390 190 $false
  $g.DrawString('Wave emission', $labelFont, $mutedBrush, 1320, 610)

  $pillPath = New-RoundedRectPath 80 820 1640 180 90
  $pillBrush = [System.Drawing.SolidBrush]::new((Color-Html '#7DEBFF' 28))
  $pillPen = [System.Drawing.Pen]::new((Color-Html '#7DEBFF' 86), 4)
  $g.FillPath($pillBrush, $pillPath)
  $g.DrawPath($pillPen, $pillPath)
  $pillBrush.Dispose()
  $pillPen.Dispose()

  $oldClip = $g.Clip
  $g.SetClip($pillPath)
  $streakPen = [System.Drawing.Pen]::new((Color-Html '#FCFEFF' 34), 6)
  for ($x = -20; $x -lt 1800; $x += 140) {
    $g.DrawLine($streakPen, [float]$x, 780, [float]($x + 60), 1040)
  }
  $streakPen.Dispose()
  $g.Clip = $oldClip
  $pillPath.Dispose()

  $stateFont = [System.Drawing.Font]::new('Segoe UI', 46, [System.Drawing.FontStyle]::Bold)
  $g.DrawString('Rain Streak active state treatment', $stateFont, $titleBrush, 160, 878)

  foreach ($object in @($titleFont, $subtitleFont, $labelFont, $stateFont, $titleBrush, $mutedBrush)) {
    $object.Dispose()
  }
}

Save-Png (Join-Path $GeneratedDir 'peer_core_size_check.png') 1200 800 {
  param($g)

  $bg = [System.Drawing.SolidBrush]::new((Color-Html '#061017'))
  $g.FillRectangle($bg, 0, 0, 1200, 640)
  $bg.Dispose()

  $titleFont = [System.Drawing.Font]::new('Segoe UI', 42, [System.Drawing.FontStyle]::Bold)
  $labelFont = [System.Drawing.Font]::new('Segoe UI', 20, [System.Drawing.FontStyle]::Regular)
  $smallFont = [System.Drawing.Font]::new('Segoe UI', 16, [System.Drawing.FontStyle]::Regular)
  $titleBrush = [System.Drawing.SolidBrush]::new((Color-Html '#FCFEFF'))
  $mutedBrush = [System.Drawing.SolidBrush]::new((Color-Html '#FCFEFF' 170))

  $g.DrawString('Peer Core size check', $titleFont, $titleBrush, 64, 56)
  $g.DrawString('Exact generated PNGs enlarged with nearest-neighbor scaling', $labelFont, $mutedBrush, 66, 112)

  $previousInterpolation = $g.InterpolationMode
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor

  $samples = @(
    @{ File = 'peer_core_mark_16.png'; Label = 'mark 16'; X = 70; Y = 190; Scale = 12 },
    @{ File = 'peer_core_mark_24.png'; Label = 'mark 24'; X = 300; Y = 190; Scale = 9 },
    @{ File = 'peer_core_mark_48.png'; Label = 'mark 48'; X = 560; Y = 190; Scale = 5 },
    @{ File = 'peer_core_mark_192.png'; Label = 'mark 192'; X = 850; Y = 190; Scale = 1.18 },
    @{ File = 'peer_core_app_icon_192.png'; Label = 'app 192'; X = 70; Y = 520; Scale = 0.82 },
    @{ File = 'peer_core_app_icon_256.png'; Label = 'app 256'; X = 320; Y = 510; Scale = 0.66 },
    @{ File = 'peer_core_mark_tiny_16.png'; Label = 'tiny 16'; X = 620; Y = 520; Scale = 12 },
    @{ File = 'peer_core_mark_tiny_24.png'; Label = 'tiny 24'; X = 850; Y = 520; Scale = 9 }
  )

  foreach ($sample in $samples) {
    $imagePath = Join-Path $GeneratedDir $sample.File
    $image = [System.Drawing.Image]::FromFile($imagePath)
    $drawWidth = [int]($image.Width * [double]$sample.Scale)
    $drawHeight = [int]($image.Height * [double]$sample.Scale)
    $g.DrawImage($image, [int]$sample.X, [int]$sample.Y, $drawWidth, $drawHeight)
    $image.Dispose()
    $g.DrawString($sample.Label, $smallFont, $mutedBrush, [float]$sample.X, [float]($sample.Y + $drawHeight + 14))
  }

  $g.InterpolationMode = $previousInterpolation

  foreach ($object in @($titleFont, $labelFont, $smallFont, $titleBrush, $mutedBrush)) {
    $object.Dispose()
  }
}

Write-Host "Generated branding assets in $SourceDir and $GeneratedDir"
