[CmdletBinding()]
param(
    [switch]$View
)

$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..\")).Path
$ConfigPath = Join-Path $ProjectRoot ".ai\promptfoo\promptfooconfig.yaml"

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Host "Promptfoo is not enabled for this project."
    Write-Host "Run the overlay installer with -EnablePromptfoo if this project has prompts, agents, RAG, model calls, or generated text behavior."
    exit 0
}

if (-not (Get-Command promptfoo -ErrorAction SilentlyContinue)) {
    throw "promptfoo was not found. Install it globally with: npm install -g promptfoo"
}

Push-Location $ProjectRoot
try {
    & promptfoo eval -c $ConfigPath

    if ($View) {
        & promptfoo view
    }
}
finally {
    Pop-Location
}
