[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VaultPath,

    [string]$ProjectName = "Rain",

    [string]$Destination = "",

    [string]$Include = "*.md",

    [string]$Exclude = ".obsidian/,Private/,99-Templates/",

    [int]$WatchInterval = 0,

    [switch]$NoWait
)

$ErrorActionPreference = "Stop"

$ResolvedVaultPath = (Resolve-Path -LiteralPath $VaultPath).Path

if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = "viking://resources/projects/$ProjectName/obsidian-vault"
}

if (-not (Get-Command ov -ErrorAction SilentlyContinue)) {
    throw "OpenViking CLI 'ov' was not found. Install it globally first: npm install -g @openviking/cli"
}

$Args = @(
    "add-resource",
    $ResolvedVaultPath,
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

Write-Host "Importing Obsidian vault into OpenViking:"
Write-Host "  Source: $ResolvedVaultPath"
Write-Host "  Target: $Destination"
Write-Host "  Include: $Include"
Write-Host "  Exclude: $Exclude"

$global:LASTEXITCODE = 0
& ov @Args
if ($LASTEXITCODE -ne 0) {
    throw "OpenViking Obsidian import failed with exit code $LASTEXITCODE."
}
