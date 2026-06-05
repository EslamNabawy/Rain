[CmdletBinding()]
param(
    [string]$ProjectPath = "",
    [string]$ProjectName = "",
    [string]$Include = "*.md,*.dart,*.yaml,*.yml,*.json,*.js,*.mjs,*.cjs,*.ps1,*.sh,*.xml,*.gradle,*.properties,*.toml,*.lock,*.cpp,*.h,*.rc,*.manifest",
    [string]$Exclude = "build/,.dart_tool/,coverage/,node_modules/,ephemeral/,.plugin_symlinks/",
    [int]$WatchInterval = 0,
    [switch]$NoWait
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\")).Path
}
else {
    $ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
}

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Split-Path -Leaf $ProjectPath
}

if (-not (Get-Command ov -ErrorAction SilentlyContinue)) {
    throw "OpenViking CLI 'ov' was not found. Install it globally first or add it to PATH."
}

$sourceRootUri = "viking://resources/projects/$ProjectName/source"

function Invoke-OvAddFolder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetUri,
        [string]$FolderInclude = $Include,
        [string]$FolderExclude = $Exclude
    )

    $path = Join-Path $ProjectPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Write-Warning "Skipping missing folder: $path"
        return
    }

    $args = @(
        "add-resource",
        $path,
        "--to",
        $TargetUri,
        "--include",
        $FolderInclude,
        "--exclude",
        $FolderExclude
    )

    if ($WatchInterval -gt 0) {
        $args += @("--watch-interval", "$WatchInterval")
    }

    Write-Host "Importing folder into OpenViking:"
    Write-Host "  Source: $path"
    Write-Host "  Target: $TargetUri"

    $global:LASTEXITCODE = 0
    & ov @args
    if ($LASTEXITCODE -ne 0) {
        throw "OpenViking folder import failed for '$path' with exit code $LASTEXITCODE."
    }
}

function Invoke-OvAddFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$TargetUri
    )

    $path = Join-Path $ProjectPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Warning "Skipping missing file: $path"
        return
    }

    $args = @("add-resource", $path, "--to", $TargetUri)
    if ($WatchInterval -gt 0) {
        $args += @("--watch-interval", "$WatchInterval")
    }

    Write-Host "Importing file into OpenViking:"
    Write-Host "  Source: $path"
    Write-Host "  Target: $TargetUri"

    $global:LASTEXITCODE = 0
    & ov @args
    if ($LASTEXITCODE -ne 0) {
        throw "OpenViking file import failed for '$path' with exit code $LASTEXITCODE."
    }
}

function Wait-OpenVikingQueue {
    $maxPolls = 120
    for ($i = 0; $i -lt $maxPolls; $i++) {
        $status = ov status | Out-String
        Write-Host $status
        if ($status -match "Pending\s+0" -and $status -match "In progress\s+0") {
            return
        }

        Start-Sleep -Seconds 30
    }

    throw "Timed out waiting for OpenViking queue to finish."
}

$global:LASTEXITCODE = 0
$existing = & ov stat $sourceRootUri 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Removing existing OpenViking source index before refresh..."
    & ov rm $sourceRootUri --recursive
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to remove existing OpenViking source index '$sourceRootUri'."
    }
}

Invoke-OvAddFolder -RelativePath "packages" -TargetUri "$sourceRootUri/packages"
Invoke-OvAddFolder -RelativePath "apps\rain\lib" -TargetUri "$sourceRootUri/apps/rain/lib"
Invoke-OvAddFolder -RelativePath "apps\rain\test" -TargetUri "$sourceRootUri/apps/rain/test"
Invoke-OvAddFolder -RelativePath "apps\rain\android" -TargetUri "$sourceRootUri/apps/rain/android"
Invoke-OvAddFolder -RelativePath "apps\rain\windows" -TargetUri "$sourceRootUri/apps/rain/windows"
Invoke-OvAddFolder -RelativePath "apps\rain\integration_test" -TargetUri "$sourceRootUri/apps/rain/integration_test"
Invoke-OvAddFolder -RelativePath "apps\rain\tool" -TargetUri "$sourceRootUri/apps/rain/tool"
Invoke-OvAddFolder -RelativePath "apps\rain\assets" -TargetUri "$sourceRootUri/apps/rain/assets"
Invoke-OvAddFolder -RelativePath "backend\firebase" -TargetUri "$sourceRootUri/backend/firebase" -FolderExclude "node_modules/,functions/node_modules/"
Invoke-OvAddFolder -RelativePath "docs" -TargetUri "$sourceRootUri/docs"
Invoke-OvAddFolder -RelativePath "scripts" -TargetUri "$sourceRootUri/scripts"

$rootFiles = @(
    "ACCOUNT_LIFECYCLE_ANALYSIS.md",
    "AGENTS.md",
    "analysis_options.yaml",
    "AUTHENTICATION_AUDIT.md",
    "CONTINUITY.md",
    "DOCUMENTATION_RULES.md",
    "NAVIGATION_INITIALIZATION_AUDIT.md",
    "PHASES.md",
    "PROJECT_OPERATING_SYSTEM.md",
    "pubspec.lock",
    "pubspec.yaml",
    "README.md",
    "ROOT_AUTH_STARTUP_REMEDIATION_ROADMAP.md",
    "ROOT_CAUSE_ANALYSIS.md",
    "SPLASH_SCREEN_INVESTIGATION.md",
    "STARTUP_SEQUENCE_ANALYSIS.md",
    "STATE_MANAGEMENT_FAILURE_ANALYSIS.md"
)

foreach ($file in $rootFiles) {
    Invoke-OvAddFile -RelativePath $file -TargetUri "$sourceRootUri/root/$file"
}

$appRootFiles = @(
    "apps\rain\AGENTS.md",
    "apps\rain\analysis_options.yaml",
    "apps\rain\firebase.json",
    "apps\rain\pubspec.lock",
    "apps\rain\pubspec.yaml",
    "apps\rain\qa.appium.json",
    "apps\rain\README.md"
)

foreach ($file in $appRootFiles) {
    $targetName = ($file -replace "\\", "/")
    Invoke-OvAddFile -RelativePath $file -TargetUri "$sourceRootUri/$targetName"
}

if (-not $NoWait) {
    Wait-OpenVikingQueue
}
