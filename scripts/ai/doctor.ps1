[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\")).Path

function Test-CommandPresent {
    param(
        [string]$Name,
        [bool]$Required = $false
    )

    $Command = Get-Command $Name -ErrorAction SilentlyContinue

    if ($Command) {
        Write-Host "[ok] ${Name}: $($Command.Source)"
        return $true
    }

    $LocalBin = Join-Path $HOME ".local\bin"
    $LocalCandidates = @(
        Join-Path $LocalBin "$Name.exe",
        Join-Path $LocalBin "$Name.ps1",
        Join-Path $LocalBin "$Name.cmd"
    )

    foreach ($Candidate in $LocalCandidates) {
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            Write-Host "[ok] ${Name}: $Candidate"
            Write-Host "[info] $LocalBin is not on PATH in this shell. Restart the shell or prepend it to PATH."
            return $true
        }
    }

    if ($Required) {
        Write-Host "[missing] $Name"
    }
    else {
        Write-Host "[optional missing] $Name"
    }

    return $false
}

Write-Host "AI overlay doctor"
Write-Host "Project: $ProjectRoot"
Write-Host ""

$MissingRequired = $false

if (-not (Test-CommandPresent -Name "python" -Required $true)) {
    $MissingRequired = $true
}

if (-not (Test-CommandPresent -Name "node" -Required $true)) {
    $MissingRequired = $true
}

if (-not (Test-CommandPresent -Name "ov" -Required $true)) {
    $MissingRequired = $true
}

if (-not (Test-CommandPresent -Name "openviking-server" -Required $true)) {
    $MissingRequired = $true
}

Test-CommandPresent -Name "promptfoo" -Required $false | Out-Null

Write-Host ""

$AgentsPath = Join-Path $ProjectRoot "AGENTS.md"
if (Test-Path -LiteralPath $AgentsPath -PathType Leaf) {
    $Agents = Get-Content -LiteralPath $AgentsPath -Raw
    if ($Agents -match "<!-- AI-OVERLAY:START -->") {
        Write-Host "[ok] AGENTS.md overlay block found"
    }
    else {
        Write-Host "[warn] AGENTS.md exists but overlay block was not found"
    }
}
else {
    Write-Host "[warn] AGENTS.md not found"
}

if (Test-Path -LiteralPath (Join-Path $ProjectRoot ".ai") -PathType Container) {
    Write-Host "[ok] .ai folder found"
}
else {
    Write-Host "[warn] .ai folder not found"
}

if (Test-Path -LiteralPath (Join-Path $ProjectRoot ".ai\promptfoo\promptfooconfig.yaml") -PathType Leaf) {
    Write-Host "[ok] Promptfoo config found"
}
else {
    Write-Host "[info] Promptfoo config not enabled for this project"
}

Write-Host ""
Write-Host "Context7 is configured globally in Codex/MCP, not per project. This script cannot verify it from the filesystem."
Write-Host "Start OpenViking separately before importing: openviking-server"

if ($MissingRequired) {
    exit 1
}
