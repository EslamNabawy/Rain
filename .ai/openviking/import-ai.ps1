[CmdletBinding()]
param(
    [string]$AiPath = "",
    [string]$ProjectName = "Rain",
    [string]$Destination = "",
    [string]$Include = "*.md,*.ps1,*.yaml,*.yml,*.json,*.txt",
    [string]$Exclude = "promptfoo/promptfooconfig.yaml,promptfoo/prompts/,promptfoo/tests/",
    [int]$WatchInterval = 0,
    [switch]$NoWait
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($AiPath)) {
    $AiPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\")).Path
}
else {
    $AiPath = (Resolve-Path -LiteralPath $AiPath).Path
}

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = "viking://resources/projects/$ProjectName/ai-overlay"
}

if (-not (Get-Command ov -ErrorAction SilentlyContinue)) {
    throw "OpenViking CLI 'ov' was not found. Install it globally first or add it to PATH."
}

$Args = @(
    "add-resource",
    $AiPath,
    "--to",
    $Destination,
    "--include",
    $Include,
    "--exclude",
    $Exclude
)

if (-not $NoWait) {
    $Args += "--wait"
}

if ($WatchInterval -gt 0) {
    $Args += @("--watch-interval", "$WatchInterval")
}

Write-Host "Importing AI overlay into OpenViking:"
Write-Host "  Source: $AiPath"
Write-Host "  Target: $Destination"
Write-Host "  Include: $Include"
Write-Host "  Exclude: $Exclude"

$global:LASTEXITCODE = 0
& ov @Args
if ($LASTEXITCODE -ne 0) {
    throw "OpenViking AI overlay import failed with exit code $LASTEXITCODE."
}
