[CmdletBinding()]
param(
    [ValidateSet("project", "ai", "obsidian", "all")]
    [string]$Target = "project",
    [string]$ProjectName = "",
    [string]$VaultPath = "",
    [int]$WatchInterval = 0,
    [switch]$NoWait
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\")).Path
$ProjectImportScript = Join-Path $ProjectRoot ".ai\openviking\import-project.ps1"
$AiImportScript = Join-Path $ProjectRoot ".ai\openviking\import-ai.ps1"
$ObsidianImportScript = Join-Path $ProjectRoot ".ai\openviking\import-obsidian.ps1"

if ([string]::IsNullOrWhiteSpace($ProjectName)) {
    $ProjectName = Split-Path -Leaf $ProjectRoot
}

if ([string]::IsNullOrWhiteSpace($VaultPath)) {
    $VaultPath = Join-Path $ProjectRoot "obsidian-vault"
}

function Invoke-Import {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Missing OpenViking import script: $ScriptPath"
    }

    & $ScriptPath @Parameters
}

$CommonParameters = @{
    ProjectName = $ProjectName
}

if ($WatchInterval -gt 0) {
    $CommonParameters["WatchInterval"] = $WatchInterval
}

if ($NoWait) {
    $CommonParameters["NoWait"] = $true
}

function Copy-Parameters {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters
    )

    $copy = @{}
    foreach ($key in $Parameters.Keys) {
        $copy[$key] = $Parameters[$key]
    }

    return $copy
}

switch ($Target) {
    "project" {
        Invoke-Import -ScriptPath $ProjectImportScript -Parameters (Copy-Parameters -Parameters $CommonParameters)
    }
    "ai" {
        Invoke-Import -ScriptPath $AiImportScript -Parameters (Copy-Parameters -Parameters $CommonParameters)
    }
    "obsidian" {
        $parameters = Copy-Parameters -Parameters $CommonParameters
        $parameters["VaultPath"] = $VaultPath
        Invoke-Import -ScriptPath $ObsidianImportScript -Parameters $parameters
    }
    "all" {
        Invoke-Import -ScriptPath $ProjectImportScript -Parameters (Copy-Parameters -Parameters $CommonParameters)
        Invoke-Import -ScriptPath $AiImportScript -Parameters (Copy-Parameters -Parameters $CommonParameters)
        $parameters = Copy-Parameters -Parameters $CommonParameters
        $parameters["VaultPath"] = $VaultPath
        Invoke-Import -ScriptPath $ObsidianImportScript -Parameters $parameters
    }
}
