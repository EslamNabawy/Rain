<# 
Builds Rain release artifacts in a clean, repeatable way.
Use from repo root:
  pwsh -File scripts/build_release.ps1 -Platform all -DartDefinesFile .\release-defines.json
  pwsh -File scripts/build_release.ps1 -Platform windows -DartDefinesFile .\release-defines.json
  pwsh -File scripts/build_release.ps1 -Platform android -DartDefinesFile .\release-defines.json
  pwsh -File scripts/build_release.ps1 -Platform all -DartDefinesFile .\apps\rain\tool\dart_defines.local.json -AllowPublicTurnForDemo -UseDemoAndroidSigningKey
#>
[CmdletBinding()]
param(
  [ValidateSet('all', 'windows', 'android')]
  [string]$Platform = 'all',
  [string]$RepoRoot = '',
  [string]$OutputDir = '',
  [string]$DartDefinesFile = '',
  [ValidateSet('all', 'mobile')]
  [string]$AndroidArtifactSet = 'all',
  [switch]$AllowPublicTurnForDemo,
  [switch]$UseDemoAndroidSigningKey,
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$DemoSignalingEncryptionKey = 'rain-demo-signaling-encryption-key-v1-change-me'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
  $OutputDir = Join-Path $RepoRoot 'final product'
}

function Write-Step([string]$Message) {
  Write-Host "`n[build_release] $Message"
}

function Ensure-Command([string]$Name) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found on PATH: $Name"
  }
}

function Resolve-KeytoolPath() {
  $command = Get-Command keytool -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidateRoots = @(
    $env:JAVA_HOME,
    $env:ANDROID_STUDIO_JDK,
    'C:\Program Files\Android\Android Studio\jbr',
    'C:\Program Files\Android\Android Studio\jre',
    'C:\Program Files\Java',
    (Join-Path $env:USERPROFILE '.gradle\jdks')
  ) | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_)
  }

  foreach ($root in $candidateRoots) {
    $keytool = Get-ChildItem -Path $root -Recurse -Filter keytool.exe -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($keytool) {
      return $keytool.FullName
    }
  }

  throw "Required command not found: keytool. Install a JDK or set JAVA_HOME."
}

function Stop-RepoRainProcesses([string]$RepoRoot) {
  $normalizedRepoRoot = $RepoRoot.TrimEnd('\')
  $rainProcesses = Get-Process -Name 'rain' -ErrorAction SilentlyContinue
  if (-not $rainProcesses) {
    return
  }

  foreach ($process in $rainProcesses) {
    try {
      $processPath = $process.Path
    } catch {
      continue
    }

    if ([string]::IsNullOrWhiteSpace($processPath)) {
      continue
    }

    if ($processPath.StartsWith($normalizedRepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
      Write-Step "Stopping running Rain process: $processPath"
      Stop-Process -Id $process.Id -Force
    }
  }
}

function Remove-PathWithRetries(
  [string]$Path,
  [int]$Attempts = 5,
  [int]$DelayMilliseconds = 1000,
  [switch]$AllowFailure
) {
  if (-not (Test-Path $Path)) {
    return $true
  }

  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      return $true
    } catch {
      if ($attempt -eq $Attempts) {
        if ($AllowFailure) {
          Write-Warning "Could not remove '$Path': $($_.Exception.Message)"
          return $false
        }
        throw
      }
      Start-Sleep -Milliseconds $DelayMilliseconds
    }
  }

  return $false
}

function Invoke-InDir([string]$Path, [scriptblock]$Script) {
  Push-Location $Path
  try {
    & $Script
  } finally {
    Pop-Location
  }
}

function Get-ReleaseTempDir([string]$RepoRoot) {
  $baseDir = [System.Environment]::GetEnvironmentVariable('RUNNER_TEMP')
  if ([string]::IsNullOrWhiteSpace($baseDir)) {
    $baseDir = [System.IO.Path]::GetTempPath()
  }

  $tmpDir = Join-Path $baseDir 'rain-release'
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  return $tmpDir
}

function Get-DartDefineArgs(
  [string]$FlutterProjectRoot,
  [string]$DartDefinesFile,
  [string]$RepoRoot,
  [bool]$AllowPublicTurnForDemo
) {
  if ([string]::IsNullOrWhiteSpace($DartDefinesFile)) {
    throw "Release builds require -DartDefinesFile with project-owned TURN servers."
  }

  if (-not (Test-Path -LiteralPath $DartDefinesFile)) {
    throw "Release dart defines file not found: $DartDefinesFile"
  }

  $resolved = (Resolve-Path -LiteralPath $DartDefinesFile).Path
  $localDefines = Join-Path $FlutterProjectRoot 'tool\dart_defines.local.json'
  $localResolved = Resolve-Path -LiteralPath $localDefines -ErrorAction SilentlyContinue
  if (
    -not $AllowPublicTurnForDemo -and
    $null -ne $localResolved -and
    $resolved.Equals($localResolved.Path, [System.StringComparison]::OrdinalIgnoreCase)
  ) {
    throw "Release builds must not use tool\dart_defines.local.json. Pass a sanitized release defines file."
  }

  Assert-ReleaseDartDefines -Path $resolved -AllowPublicTurnForDemo:$AllowPublicTurnForDemo

  if ($AllowPublicTurnForDemo) {
    $resolved = New-DemoDartDefinesFile -Path $resolved -RepoRoot $RepoRoot
  }

  return @("--dart-define-from-file=$resolved")
}

function New-DemoDartDefinesFile([string]$Path, [string]$RepoRoot) {
  $defines = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop
  if ($null -eq $defines.PSObject.Properties['RAIN_ALLOW_PUBLIC_TURN']) {
    $defines | Add-Member -NotePropertyName 'RAIN_ALLOW_PUBLIC_TURN' -NotePropertyValue 'true'
  } else {
    $defines.RAIN_ALLOW_PUBLIC_TURN = 'true'
  }

  if ($null -eq $defines.PSObject.Properties['RAIN_SIGNALING_ENCRYPTION_KEY']) {
    $defines | Add-Member -NotePropertyName 'RAIN_SIGNALING_ENCRYPTION_KEY' -NotePropertyValue $script:DemoSignalingEncryptionKey
  } elseif ([string]::IsNullOrWhiteSpace([string]$defines.RAIN_SIGNALING_ENCRYPTION_KEY)) {
    $defines.RAIN_SIGNALING_ENCRYPTION_KEY = $script:DemoSignalingEncryptionKey
  }

  $tmpDir = Get-ReleaseTempDir $RepoRoot
  $demoDefinesPath = Join-Path $tmpDir 'rain-openrelay-demo-defines.generated.json'
  $defines | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $demoDefinesPath -Encoding utf8
  return $demoDefinesPath
}

function Get-JsonPropertyValue([object]$Json, [string]$Name) {
  $property = $Json.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return ''
  }
  return [string]$property.Value
}

function Get-IceServerUrls([object]$IceServer) {
  $property = $IceServer.PSObject.Properties['urls']
  if ($null -eq $property -or $null -eq $property.Value) {
    return @()
  }

  $urls = $property.Value
  if ($urls -is [string]) {
    return @($urls)
  }
  if ($urls -is [System.Collections.IEnumerable]) {
    return @($urls | ForEach-Object { [string]$_ })
  }
  return @([string]$urls)
}

function Test-IceUrlIsTurn([string]$Url) {
  return $Url.StartsWith('turn:', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-IceUrlIsTurns([string]$Url) {
  return $Url.StartsWith('turns:', [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-IceUrlHasTransport([string]$Url, [string]$Transport) {
  $normalized = $Url.Trim().ToLowerInvariant()
  $expected = "transport=$($Transport.ToLowerInvariant())"
  return $normalized.Contains("?$expected") -or $normalized.Contains("&$expected")
}

function Assert-ReleaseDartDefines([string]$Path, [switch]$AllowPublicTurnForDemo) {
  try {
    $defines = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -ErrorAction Stop
  } catch {
    throw "Release dart defines file must be valid JSON: $Path"
  }

  $signalingEncryptionKey = Get-JsonPropertyValue $defines 'RAIN_SIGNALING_ENCRYPTION_KEY'
  if ([string]::IsNullOrWhiteSpace($signalingEncryptionKey)) {
    if (-not $AllowPublicTurnForDemo) {
      throw "RAIN_SIGNALING_ENCRYPTION_KEY is required in release dart defines."
    }
    Write-Warning "RAIN_SIGNALING_ENCRYPTION_KEY is missing; demo release artifacts will use the bundled demo signaling key."
  } else {
    $signalingEncryptionKey = $signalingEncryptionKey.Trim()
    if ($signalingEncryptionKey.Length -lt 32) {
      throw "RAIN_SIGNALING_ENCRYPTION_KEY must be at least 32 characters."
    }
    if (
      -not $AllowPublicTurnForDemo -and
      $signalingEncryptionKey.Equals($script:DemoSignalingEncryptionKey, [System.StringComparison]::Ordinal)
    ) {
      throw "Production release builds must not use the demo signaling encryption key."
    }
  }

  $rawIceServers = Get-JsonPropertyValue $defines 'RAIN_ICE_SERVERS'
  if ([string]::IsNullOrWhiteSpace($rawIceServers)) {
    throw "RAIN_ICE_SERVERS is required in release dart defines."
  }

  $rawIceServers = $rawIceServers.Trim()
  if (-not $rawIceServers.StartsWith('[')) {
    throw "RAIN_ICE_SERVERS must be a JSON array of ICE server objects."
  }

  try {
    $parsedIceServers = ConvertFrom-Json -InputObject $rawIceServers -ErrorAction Stop
  } catch {
    throw "RAIN_ICE_SERVERS must be a JSON array of ICE server objects."
  }

  $iceServers = if ($parsedIceServers -is [System.Array]) {
    @($parsedIceServers)
  } else {
    @($parsedIceServers)
  }

  if ($iceServers.Count -eq 0) {
    throw "RAIN_ICE_SERVERS must include at least one ICE server."
  }

  $urls = @($iceServers | ForEach-Object { Get-IceServerUrls $_ } | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_)
  })
  if ($urls.Count -eq 0) {
    throw "RAIN_ICE_SERVERS must include ICE server urls."
  }

  $openRelayUrls = @($urls | Where-Object {
    $_.IndexOf('openrelay.metered.ca', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
  })
  if ($openRelayUrls.Count -gt 0) {
    if (-not $AllowPublicTurnForDemo) {
      throw "Release builds must not use OpenRelay/public TURN servers. Configure project-owned TURN servers."
    }
    Write-Warning "OpenRelay/public TURN is enabled for demo release artifacts only."
  }

  $turnBrokerUrl = Get-JsonPropertyValue $defines 'RAIN_TURN_BROKER_URL'
  $hasTurnBroker = -not [string]::IsNullOrWhiteSpace($turnBrokerUrl)
  if ($hasTurnBroker -and -not $AllowPublicTurnForDemo) {
    Write-Host "Production release uses TURN credential broker: $turnBrokerUrl"
    return
  }

  $turnUrls = @($urls | Where-Object {
    (Test-IceUrlIsTurn $_) -or (Test-IceUrlIsTurns $_)
  })
  if ($turnUrls.Count -eq 0) {
    throw "Release builds require RAIN_TURN_BROKER_URL or at least one project-owned TURN/TURNS URL in RAIN_ICE_SERVERS."
  }

  $turnServerEntries = @($iceServers | Where-Object {
    $serverUrls = @(Get-IceServerUrls $_ | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    })
    @($serverUrls | Where-Object {
      (Test-IceUrlIsTurn $_) -or (Test-IceUrlIsTurns $_)
    }).Count -gt 0
  })

  $turnServersWithCredentials = @($iceServers | Where-Object {
    $serverUrls = @(Get-IceServerUrls $_ | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    })
    $hasTurnUrl = @($serverUrls | Where-Object {
      (Test-IceUrlIsTurn $_) -or (Test-IceUrlIsTurns $_)
    }).Count -gt 0

    $username = Get-JsonPropertyValue $_ 'username'
    $credential = Get-JsonPropertyValue $_ 'credential'
    $hasTurnUrl -and
      -not [string]::IsNullOrWhiteSpace($username) -and
      -not [string]::IsNullOrWhiteSpace($credential)
  })
  if ($turnServersWithCredentials.Count -eq 0) {
    throw "Release TURN servers must include username and credential."
  }

  if (-not $AllowPublicTurnForDemo) {
    $turnServersMissingCredentials = @($turnServerEntries | Where-Object {
      $username = Get-JsonPropertyValue $_ 'username'
      $credential = Get-JsonPropertyValue $_ 'credential'
      [string]::IsNullOrWhiteSpace($username) -or
        [string]::IsNullOrWhiteSpace($credential)
    })
    if ($turnServersMissingCredentials.Count -gt 0) {
      throw "Every production TURN/TURNS server entry must include username and credential."
    }

    $hasTurnUdp = @($turnUrls | Where-Object {
      (Test-IceUrlIsTurn $_) -and (Test-IceUrlHasTransport $_ 'udp')
    }).Count -gt 0
    if (-not $hasTurnUdp) {
      throw "Production RAIN_ICE_SERVERS must include a turn: UDP endpoint."
    }

    $hasTurnTcp = @($turnUrls | Where-Object {
      (Test-IceUrlIsTurn $_) -and (Test-IceUrlHasTransport $_ 'tcp')
    }).Count -gt 0
    if (-not $hasTurnTcp) {
      throw "Production RAIN_ICE_SERVERS must include a turn: TCP endpoint."
    }

    $hasTurnsTcp = @($turnUrls | Where-Object {
      (Test-IceUrlIsTurns $_) -and (Test-IceUrlHasTransport $_ 'tcp')
    }).Count -gt 0
    if (-not $hasTurnsTcp) {
      throw "Production RAIN_ICE_SERVERS must include a turns: TCP/TLS endpoint."
    }
  }
}

function Assert-AndroidReleaseSigning() {
  $requiredVariables = @(
    'RAIN_RELEASE_STORE_FILE',
    'RAIN_RELEASE_STORE_PASSWORD',
    'RAIN_RELEASE_KEY_ALIAS',
    'RAIN_RELEASE_KEY_PASSWORD'
  )

  foreach ($name in $requiredVariables) {
    $value = [System.Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value)) {
      throw "$name is required for release signing."
    }
  }

  $storeFile = [System.Environment]::GetEnvironmentVariable('RAIN_RELEASE_STORE_FILE')
  if (-not (Test-Path -LiteralPath $storeFile)) {
    throw "RAIN_RELEASE_STORE_FILE does not exist: $storeFile"
  }
}

function Use-DemoAndroidSigningKey([string]$RepoRoot) {
  $keytoolPath = Resolve-KeytoolPath
  $jdkRoot = Split-Path (Split-Path $keytoolPath -Parent) -Parent
  [System.Environment]::SetEnvironmentVariable('JAVA_HOME', $jdkRoot, 'Process')
  $env:PATH = "$(Join-Path $jdkRoot 'bin');$env:PATH"

  $tmpDir = Get-ReleaseTempDir $RepoRoot
  $keyPath = Join-Path $tmpDir 'rain-openrelay-demo-release.jks'
  $password = 'rain-openrelay-demo'
  $alias = 'rain-openrelay-demo'

  if (-not (Test-Path -LiteralPath $keyPath)) {
    Write-Step "Creating demo Android signing key"
    & $keytoolPath `
      -genkeypair `
      -noprompt `
      -alias $alias `
      -keyalg RSA `
      -keysize 2048 `
      -validity 10000 `
      -keystore $keyPath `
      -storepass $password `
      -keypass $password `
      -dname 'CN=Rain OpenRelay Demo,O=Rain,C=US' | Out-Host

    if ($LASTEXITCODE -ne 0) {
      throw "keytool failed to create demo Android signing key with exit code $LASTEXITCODE"
    }
  }

  [System.Environment]::SetEnvironmentVariable('RAIN_RELEASE_STORE_FILE', $keyPath, 'Process')
  [System.Environment]::SetEnvironmentVariable('RAIN_RELEASE_STORE_PASSWORD', $password, 'Process')
  [System.Environment]::SetEnvironmentVariable('RAIN_RELEASE_KEY_ALIAS', $alias, 'Process')
  [System.Environment]::SetEnvironmentVariable('RAIN_RELEASE_KEY_PASSWORD', $password, 'Process')
}

function Invoke-FlutterBuild([string[]]$Arguments) {
  & flutter @Arguments | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "flutter $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Stop-GradleDaemons([string]$ProjectRoot) {
  $gradlewPath = Join-Path $ProjectRoot 'android\gradlew.bat'
  if (-not (Test-Path $gradlewPath)) {
    return
  }

  try {
    Push-Location (Split-Path $gradlewPath -Parent)
    & $gradlewPath --stop | Out-Host
  } catch {
    Write-Warning "Could not stop Gradle daemons: $($_.Exception.Message)"
  } finally {
    Pop-Location
  }
}

function Clean-FlutterProject([string]$ProjectRoot) {
  $buildDir = Join-Path $ProjectRoot 'build'
  $ephemeralDirs = @(
    'windows\flutter\ephemeral'
    'linux\flutter\ephemeral'
    'macos\Flutter\ephemeral'
    'android\app\generated'
    'android\.gradle'
    '.gradle'
  )

  if (Test-Path $buildDir) {
    Remove-PathWithRetries -Path $buildDir -Attempts 10 -DelayMilliseconds 2000 -AllowFailure | Out-Null
  }

  foreach ($relativePath in $ephemeralDirs) {
    $ephemeralDir = Join-Path $ProjectRoot $relativePath
    if (Test-Path $ephemeralDir) {
      Remove-PathWithRetries -Path $ephemeralDir -Attempts 10 -DelayMilliseconds 2000 -AllowFailure | Out-Null
    }
  }
}

function Get-WindowsNativeAssetNames([string]$ManifestPath) {
  if (-not (Test-Path -LiteralPath $ManifestPath)) {
    return @()
  }

  $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json -ErrorAction Stop
  $nativeAssetsProperty = $manifest.PSObject.Properties['native-assets']
  if ($null -eq $nativeAssetsProperty) {
    return @()
  }

  $windowsAssetsProperty = $nativeAssetsProperty.Value.PSObject.Properties['windows_x64']
  if ($null -eq $windowsAssetsProperty) {
    return @()
  }

  $assetNames = @()
  foreach ($property in $windowsAssetsProperty.Value.PSObject.Properties) {
    $entry = @($property.Value)
    if ($entry.Count -lt 2 -or [string]$entry[0] -ne 'absolute') {
      continue
    }

    $assetName = [System.IO.Path]::GetFileName([string]$entry[1])
    if (-not [string]::IsNullOrWhiteSpace($assetName)) {
      $assetNames += $assetName
    }
  }

  return @($assetNames | Sort-Object -Unique)
}

function Copy-WindowsNativeAssets([string]$ProjectRoot, [string]$DestinationRoot) {
  $nativeAssetsDir = Join-Path $ProjectRoot 'build\native_assets\windows'
  if (-not (Test-Path -LiteralPath $nativeAssetsDir)) {
    return
  }

  $nativeAssetsManifest = Join-Path $DestinationRoot 'data\flutter_assets\NativeAssetsManifest.json'
  $nativeAssetNames = @(Get-WindowsNativeAssetNames -ManifestPath $nativeAssetsManifest)
  if ($nativeAssetNames.Count -eq 0) {
    return
  }

  Write-Step "Copying Windows native assets"
  foreach ($nativeAssetName in $nativeAssetNames) {
    $nativeAssetPath = Join-Path $nativeAssetsDir $nativeAssetName
    if (-not (Test-Path -LiteralPath $nativeAssetPath)) {
      throw "Windows native asset source not found: $nativeAssetPath"
    }
    Copy-Item -LiteralPath $nativeAssetPath -Destination $DestinationRoot -Force
  }
}

function Assert-WindowsNativeAssetsPackaged([string]$ProjectRoot, [string]$DestinationRoot) {
  $nativeAssetsManifest = Join-Path $DestinationRoot 'data\flutter_assets\NativeAssetsManifest.json'
  $nativeAssetNames = @(Get-WindowsNativeAssetNames -ManifestPath $nativeAssetsManifest)
  foreach ($nativeAssetName in $nativeAssetNames) {
    $packagedNativeAsset = Join-Path $DestinationRoot $nativeAssetName
    if (-not (Test-Path -LiteralPath $packagedNativeAsset)) {
      throw "Windows native asset not found in portable output: $packagedNativeAsset"
    }
  }
}

function Remove-WindowsLinkerArtifacts([string]$DestinationRoot) {
  Get-ChildItem -LiteralPath $DestinationRoot -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in @('.exp', '.lib') } |
    Remove-Item -Force
}

function Resolve-DumpbinPath() {
  $command = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidatePatterns = @(
    'C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe',
    'C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe',
    'C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe',
    'C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe',
    'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe'
  )

  foreach ($pattern in $candidatePatterns) {
    $candidate = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
      Sort-Object FullName -Descending |
      Select-Object -First 1
    if ($candidate) {
      return $candidate.FullName
    }
  }

  throw "Required command not found: dumpbin.exe. Install Visual Studio Build Tools."
}

function Assert-DllExports([string]$DllPath, [string[]]$RequiredExports) {
  if (-not (Test-Path -LiteralPath $DllPath)) {
    throw "Required Windows runtime DLL not found: $DllPath"
  }

  $dumpbin = Resolve-DumpbinPath
  $output = & $dumpbin /exports $DllPath 2>&1
  if ($LASTEXITCODE -ne 0) {
    $text = $output | Out-String
    throw "Could not inspect Windows runtime DLL exports: $DllPath`n$text"
  }

  $exports = $output | Out-String
  foreach ($requiredExport in $RequiredExports) {
    $pattern = "(?m)(^|\s)$([regex]::Escape($requiredExport))(\s|$)"
    if ($exports -notmatch $pattern) {
      throw "Windows runtime DLL '$DllPath' is missing required export '$requiredExport'."
    }
  }
}

function Assert-WindowsSqliteExports([string]$DestinationRoot) {
  $sqliteDll = Join-Path $DestinationRoot 'sqlite3.dll'
  Assert-DllExports -DllPath $sqliteDll -RequiredExports @(
    'sqlite3_open_v2',
    'sqlite3_temp_directory'
  )
}

function Assert-WindowsRuntimeBundle([string]$DestinationRoot) {
  $requiredEntries = @(
    'rain.exe',
    'flutter_windows.dll',
    'flutter_webrtc_plugin.dll',
    'libwebrtc.dll',
    'sqlite3.dll',
    'data'
  )

  foreach ($entry in $requiredEntries) {
    $path = Join-Path $DestinationRoot $entry
    if (-not (Test-Path -LiteralPath $path)) {
      throw "Windows runtime bundle is missing required entry: $path"
    }
  }
}

function Get-ZipEntryNames([string]$ArchivePath) {
  Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
  Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

  $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
  try {
    return @($archive.Entries | ForEach-Object { $_.FullName })
  } finally {
    $archive.Dispose()
  }
}

function Assert-AndroidApkContainsNativeRuntimes([string]$ApkPath, [string[]]$Abis) {
  if (-not (Test-Path -LiteralPath $ApkPath)) {
    throw "Android release APK not found: $ApkPath"
  }

  $requiredLibraries = @(
    'libsqlite3.so',
    'libjingle_peerconnection_so.so'
  )
  $entryNames = @(Get-ZipEntryNames -ArchivePath $ApkPath)
  foreach ($abi in $Abis) {
    foreach ($library in $requiredLibraries) {
      $requiredEntry = "lib/$abi/$library"
      if ($entryNames -notcontains $requiredEntry) {
        throw "Android APK is missing required native runtime library: $ApkPath -> $requiredEntry"
      }
    }
  }

  $knownAndroidAbis = @('armeabi-v7a', 'arm64-v8a', 'x86', 'x86_64')
  foreach ($knownAbi in $knownAndroidAbis) {
    if ($Abis -contains $knownAbi) {
      continue
    }

    $unexpectedEntries = @($entryNames | Where-Object {
        $_.StartsWith("lib/$knownAbi/", [System.StringComparison]::Ordinal)
      })
    if ($unexpectedEntries.Count -gt 0) {
      throw "Android APK contains unexpected native ABI '$knownAbi': $ApkPath"
    }
  }
}

$repoRoot = $RepoRoot
$appsRoot = Join-Path $repoRoot 'apps\rain'
$releaseRoot = $OutputDir
$isOpenRelayDemoBuild = [bool]$AllowPublicTurnForDemo
if ($UseDemoAndroidSigningKey -and -not $isOpenRelayDemoBuild) {
  throw "Demo Android signing is only allowed with -AllowPublicTurnForDemo."
}

$androidArtifactPrefix = if ($isOpenRelayDemoBuild) { 'Rain-Demo' } else { 'Rain-release' }
$windowsPortableName = if ($isOpenRelayDemoBuild) { 'Rain-Demo-Windows-x64-Build' } else { 'Rain-windows-portable' }
$dartDefineArgs = Get-DartDefineArgs $appsRoot $DartDefinesFile $repoRoot $isOpenRelayDemoBuild
if ($Platform -in @('all', 'android')) {
  if ($UseDemoAndroidSigningKey) {
    Use-DemoAndroidSigningKey $repoRoot
  }
  Assert-AndroidReleaseSigning
}

Ensure-Command flutter
Ensure-Command dart
Ensure-Command git

Write-Step "Syncing app icons"
& (Join-Path $repoRoot 'scripts\sync_app_icons.ps1') -RepoRoot $repoRoot | Out-Host

Stop-RepoRainProcesses $repoRoot

if ($Clean) {
  Write-Step "Cleaning output directory: $releaseRoot"
  Remove-PathWithRetries -Path $releaseRoot -AllowFailure | Out-Null
}

New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null

Write-Step "Bootstrapping dependencies"
Invoke-InDir $repoRoot {
  dart pub get | Out-Host
}

$pubGetRoots = @(
  $appsRoot,
  (Join-Path $repoRoot 'packages\peer_core'),
  (Join-Path $repoRoot 'packages\protocol_brain'),
  (Join-Path $repoRoot 'packages\rain_core')
)

foreach ($pubRoot in $pubGetRoots) {
  Write-Step "Running flutter pub get in $pubRoot"
  Invoke-InDir $pubRoot {
    flutter pub get | Out-Host
  }
}

if ($Platform -in @('all', 'windows')) {
  Write-Step "Building Windows release"
  Invoke-InDir $appsRoot {
    & flutter config --enable-windows-desktop | Out-Host
  }
  if ($Clean) {
    Write-Step "Cleaning Flutter project state for Windows build"
    Clean-FlutterProject $appsRoot
  }
  $flutterArgs = @('build', 'windows', '--release') + $dartDefineArgs
  Invoke-InDir $appsRoot {
    Invoke-FlutterBuild $flutterArgs
  }

  $windowsReleaseDir = Join-Path $appsRoot 'build\windows\x64\runner\Release'
  $windowsPortableDir = Join-Path $releaseRoot $windowsPortableName
  $windowsZip = Join-Path $releaseRoot "$windowsPortableName.zip"

  if (-not (Test-Path $windowsReleaseDir)) {
    throw "Windows release folder not found: $windowsReleaseDir"
  }

  if (-not (Remove-PathWithRetries -Path $windowsPortableDir -AllowFailure)) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $windowsPortableDir = Join-Path $releaseRoot "$windowsPortableName-$timestamp"
    Write-Warning "Portable output folder is locked. Using fallback directory '$windowsPortableDir'."
  }

  Write-Step "Copying Windows release folder to final product directory"
  New-Item -ItemType Directory -Force -Path $windowsPortableDir | Out-Null
  Copy-Item -Path (Join-Path $windowsReleaseDir '*') -Destination $windowsPortableDir -Recurse -Force

  $windowsAotSource = Join-Path $appsRoot 'build\windows\app.so'
  $windowsAotDestinationDir = Join-Path $windowsPortableDir 'data'
  $windowsAotDestination = Join-Path $windowsAotDestinationDir 'app.so'
  $flutterAssetsSource = Join-Path $appsRoot 'build\flutter_assets'
  $flutterAssetsDestination = Join-Path $windowsAotDestinationDir 'flutter_assets'

  if (-not (Test-Path $windowsAotSource)) {
    throw "Windows AOT library not found: $windowsAotSource"
  }
  if (-not (Test-Path $flutterAssetsSource)) {
    throw "Flutter assets bundle not found: $flutterAssetsSource"
  }

  New-Item -ItemType Directory -Force -Path $windowsAotDestinationDir | Out-Null
  Copy-Item -LiteralPath $windowsAotSource -Destination $windowsAotDestination -Force
  if (Test-Path $flutterAssetsDestination) {
    Remove-Item -LiteralPath $flutterAssetsDestination -Recurse -Force
  }
  Copy-Item -Path $flutterAssetsSource -Destination $flutterAssetsDestination -Recurse -Force
  Copy-WindowsNativeAssets -ProjectRoot $appsRoot -DestinationRoot $windowsPortableDir
  Assert-WindowsNativeAssetsPackaged -ProjectRoot $appsRoot -DestinationRoot $windowsPortableDir
  Remove-WindowsLinkerArtifacts -DestinationRoot $windowsPortableDir
  Assert-WindowsRuntimeBundle -DestinationRoot $windowsPortableDir
  Assert-WindowsSqliteExports -DestinationRoot $windowsPortableDir

  if (Test-Path $windowsZip) {
    Remove-Item -LiteralPath $windowsZip -Force
  }

  Write-Step "Packaging portable Windows zip"
  Compress-Archive -Path (Join-Path $windowsPortableDir '*') -DestinationPath $windowsZip -Force
}

if ($Platform -in @('all', 'android')) {
  Write-Step "Building Android ARM v7 and ARM v8/v9 release APKs"
  if ($Clean) {
    Write-Step "Cleaning Flutter project state for Android build"
    Stop-GradleDaemons $appsRoot
    Clean-FlutterProject $appsRoot
  }
  $androidTargetPlatformArgs = @('--target-platform', 'android-arm,android-arm64')
  Write-Step "Building Android per-ABI release APKs: armeabi-v7a and arm64-v8a"
  $splitFlutterArgs = @('build', 'apk', '--release', '--split-per-abi') + $androidTargetPlatformArgs + $dartDefineArgs
  Invoke-InDir $appsRoot {
    Invoke-FlutterBuild $splitFlutterArgs
  }

  $abiApks = if ($isOpenRelayDemoBuild) {
    @(
      @{ Label = 'ARM v7 devices (armeabi-v7a)'; Source = 'app-armeabi-v7a-release.apk'; Destination = 'Rain-Demo-Android-ARM-v7a-Build.apk'; Abi = 'armeabi-v7a' }
      @{ Label = 'ARM v8/v9 devices (arm64-v8a)'; Source = 'app-arm64-v8a-release.apk'; Destination = 'Rain-Demo-Android-ARM-v8-v9-Build.apk'; Abi = 'arm64-v8a' }
    )
  } else {
    @(
      @{ Label = 'ARM v7 devices (armeabi-v7a)'; Source = 'app-armeabi-v7a-release.apk'; Destination = "$androidArtifactPrefix-android-armeabi-v7a.apk"; Abi = 'armeabi-v7a' }
      @{ Label = 'ARM v8/v9 devices (arm64-v8a)'; Source = 'app-arm64-v8a-release.apk'; Destination = "$androidArtifactPrefix-android-arm64-v8a.apk"; Abi = 'arm64-v8a' }
    )
  }

  foreach ($abiApk in $abiApks) {
    $abiApkSource = Join-Path $appsRoot "build\app\outputs\flutter-apk\$($abiApk.Source)"
    $abiApkDestination = Join-Path $releaseRoot $abiApk.Destination

    if (-not (Test-Path $abiApkSource)) {
      throw "Android release APK not found: $abiApkSource"
    }

    Copy-Item -LiteralPath $abiApkSource -Destination $abiApkDestination -Force
    Assert-AndroidApkContainsNativeRuntimes -ApkPath $abiApkDestination -Abis @($abiApk.Abi)
    Write-Step "Packaged Android APK for $($abiApk.Label): $abiApkDestination"
  }
}

if ($Platform -in @('all', 'windows')) {
  $portableExe = if ($windowsPortableDir) {
    Join-Path $windowsPortableDir 'rain.exe'
  } else {
    Join-Path (Join-Path $releaseRoot $windowsPortableName) 'rain.exe'
  }

  if (-not (Test-Path $portableExe)) {
    $portableExe = Get-ChildItem -Path $releaseRoot -Directory -Filter "$windowsPortableName*" |
      Sort-Object LastWriteTime -Descending |
      ForEach-Object { Join-Path $_.FullName 'rain.exe' } |
      Where-Object { Test-Path $_ } |
      Select-Object -First 1
  }

  if (-not (Test-Path $portableExe)) {
    throw "Portable Windows executable not found in $releaseRoot"
  }
}

if ($Platform -in @('all', 'android')) {
  $expectedApks = if ($isOpenRelayDemoBuild) {
    @(
      'Rain-Demo-Android-ARM-v7a-Build.apk',
      'Rain-Demo-Android-ARM-v8-v9-Build.apk'
    )
  } else {
    @(
      "$androidArtifactPrefix-android-armeabi-v7a.apk",
      "$androidArtifactPrefix-android-arm64-v8a.apk"
    )
  }

  foreach ($apkName in $expectedApks) {
    $apkDestination = Join-Path $releaseRoot $apkName
    if (-not (Test-Path $apkDestination)) {
      throw "Android release APK not found in final product directory: $apkDestination"
    }
  }
}

$global:LASTEXITCODE = 0
Write-Step "Release artifacts are ready in $releaseRoot"
