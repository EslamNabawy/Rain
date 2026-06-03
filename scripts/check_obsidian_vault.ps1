param(
  [string]$VaultRoot = (Join-Path (Get-Location) 'obsidian-vault')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -Path $VaultRoot -PathType Container)) {
  Write-Error "Obsidian vault not found: $VaultRoot"
}

$requiredFiles = @(
  '00-Dashboard/Project Home.md',
  '00-Dashboard/Current Status.md',
  '00-Dashboard/Launch Readiness.md',
  '01-Product/Vision.md',
  '01-Product/Requirements.md',
  '01-Product/User Personas.md',
  '01-Product/User Flows.md',
  '01-Product/Feature Matrix.md',
  '01-Product/Roadmap.md',
  '02-Architecture/System Architecture.md',
  '02-Architecture/Frontend Architecture.md',
  '02-Architecture/Backend Architecture.md',
  '02-Architecture/Database Architecture.md',
  '02-Architecture/Infrastructure Architecture.md',
  '02-Architecture/Design Decisions.md',
  '02-Architecture/Technical Debt.md',
  '03-Features/Feature Index.md',
  '04-API/API Overview.md',
  '04-API/Endpoints.md',
  '04-API/Contracts.md',
  '05-Database/Database Schema.md',
  '05-Database/Migrations.md',
  '06-Development/Coding Standards.md',
  '06-Development/Project Conventions.md',
  '06-Development/Environment Setup.md',
  '06-Development/Build Process.md',
  '07-Testing/Test Strategy.md',
  '07-Testing/Coverage Report.md',
  '07-Testing/QA Findings.md',
  '08-Security/Security Review.md',
  '08-Security/Permissions Matrix.md',
  '08-Security/Risk Register.md',
  '09-Operations/Deployment.md',
  '09-Operations/Monitoring.md',
  '09-Operations/Incident Response.md',
  '09-Operations/Backup Strategy.md',
  '10-Research/Research Notes.md',
  '10-Research/Competitor Analysis.md',
  '11-Decisions/ADR-001.md',
  '11-Decisions/ADR-002.md',
  '11-Decisions/ADR-003.md',
  '12-Tasks/Backlog.md',
  '12-Tasks/Current Sprint.md',
  '12-Tasks/Technical Tasks.md',
  '13-Bugs/Open Bugs.md',
  '13-Bugs/Fixed Bugs.md',
  '14-Blockers/BLOCKERS.md',
  '15-AI/AI Context.md',
  '15-AI/AI Instructions.md',
  '15-AI/Project Memory.md',
  '16-Diagrams/System Diagrams.md',
  '16-Diagrams/Sequence Diagrams.md',
  '16-Diagrams/Entity Relationships.md'
)

$missingRequired = @()
foreach ($relativePath in $requiredFiles) {
  $path = Join-Path $VaultRoot $relativePath
  if (-not (Test-Path -Path $path -PathType Leaf)) {
    $missingRequired += $relativePath
  }
}

if ($missingRequired.Count -gt 0) {
  Write-Error ("Missing required vault files:`n" + ($missingRequired -join "`n"))
}

$markdownFiles = Get-ChildItem -Path $VaultRoot -Recurse -File -Filter '*.md'
if ($markdownFiles.Count -eq 0) {
  Write-Error 'Obsidian vault contains no Markdown files.'
}

$noteTitles = @{}
foreach ($file in $markdownFiles) {
  $noteTitles[[System.IO.Path]::GetFileNameWithoutExtension($file.Name)] = $true
}

$missingLinks = New-Object System.Collections.Generic.List[string]
$linkPattern = '\[\[([^\]|#]+)'
foreach ($file in $markdownFiles) {
  $text = Get-Content -Path $file.FullName -Raw
  foreach ($match in [regex]::Matches($text, $linkPattern)) {
    $target = $match.Groups[1].Value.Trim()
    if ($target.Length -eq 0) {
      continue
    }
    if (-not $noteTitles.ContainsKey($target)) {
      $relative = Resolve-Path -Path $file.FullName -Relative
      $missingLinks.Add("$relative -> $target")
    }
  }
}

if ($missingLinks.Count -gt 0) {
  $uniqueMissingLinks = $missingLinks | Sort-Object -Unique
  Write-Error ("Missing Obsidian wiki-link targets:`n" + ($uniqueMissingLinks -join "`n"))
}

Write-Host "Obsidian vault check passed. Markdown files: $($markdownFiles.Count)."
