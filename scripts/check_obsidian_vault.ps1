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
  '00-Dashboard/Production Readiness.md',
  '01-Product/Vision.md',
  '01-Product/Requirements.md',
  '01-Product/User Personas.md',
  '01-Product/User Flows.md',
  '01-Product/Feature Matrix.md',
  '01-Product/Roadmap.md',
  '01-Roadmap/Master Roadmap.md',
  '01-Roadmap/30 Day Plan.md',
  '01-Roadmap/60 Day Plan.md',
  '01-Roadmap/90 Day Plan.md',
  '01-Roadmap/Sprint Planning.md',
  '01-Roadmap/Critical Path.md',
  '02-Architecture/System Architecture.md',
  '02-Architecture/Frontend Architecture.md',
  '02-Architecture/Backend Architecture.md',
  '02-Architecture/Database Architecture.md',
  '02-Architecture/Infrastructure Architecture.md',
  '02-Architecture/Design Decisions.md',
  '02-Architecture/Technical Debt.md',
  '02-Epics/Epic Index.md',
  '02-Epics/Architecture Stabilization Epic.md',
  '02-Epics/Signaling Reliability Epic.md',
  '02-Epics/Database Scalability Epic.md',
  '02-Epics/File Transfer Optimization Epic.md',
  '02-Epics/Security Hardening Epic.md',
  '02-Epics/CI-CD Modernization Epic.md',
  '02-Epics/Production Validation Epic.md',
  '03-Architecture/Current Architecture.md',
  '03-Architecture/Target Architecture.md',
  '03-Architecture/Refactoring Strategy.md',
  '03-Architecture/VoiceCallRuntime Refactor.md',
  '03-Architecture/CallStartCoordinator.md',
  '03-Architecture/CallLeaseManager.md',
  '03-Architecture/CallMediaCoordinator.md',
  '03-Architecture/CallTerminalReconciler.md',
  '03-Architecture/CallDiagnosticsRecorder.md',
  '03-Features/Feature Index.md',
  '04-API/API Overview.md',
  '04-API/Endpoints.md',
  '04-API/Contracts.md',
  '04-Signaling/Signaling Architecture.md',
  '04-Signaling/Lease Management.md',
  '04-Signaling/Call State Machine.md',
  '04-Signaling/Presence Management.md',
  '05-Database/Database Schema.md',
  '05-Database/Migrations.md',
  '05-Firebase/Firebase Architecture.md',
  '05-Firebase/Rules Strategy.md',
  '05-Firebase/Emulator Coverage.md',
  '06-Database/Database Architecture.md',
  '06-Database/Index Strategy.md',
  '06-Database/Pagination Strategy.md',
  '06-Database/Migration Plan.md',
  '06-Development/Coding Standards.md',
  '06-Development/Project Conventions.md',
  '06-Development/Environment Setup.md',
  '06-Development/Build Process.md',
  '07-File Transfers/Streaming Architecture.md',
  '07-File Transfers/Backpressure Strategy.md',
  '07-Testing/Test Strategy.md',
  '07-Testing/Coverage Report.md',
  '07-Testing/QA Findings.md',
  '08-Security/Security Roadmap.md',
  '08-Security/Privacy Review.md',
  '08-Security/Diagnostics Sanitization.md',
  '08-Security/Security Review.md',
  '08-Security/Permissions Matrix.md',
  '08-Security/Risk Register.md',
  '09-Operations/Deployment.md',
  '09-Operations/Monitoring.md',
  '09-Operations/Incident Response.md',
  '09-Operations/Backup Strategy.md',
  '09-Testing/Test Strategy.md',
  '09-Testing/Coverage Dashboard.md',
  '09-Testing/Emulator Test Matrix.md',
  '10-DevOps/CI-CD Roadmap.md',
  '10-DevOps/Release Gates.md',
  '10-Research/Research Notes.md',
  '10-Research/Competitor Analysis.md',
  '11-Decisions/ADR-001.md',
  '11-Decisions/ADR-002.md',
  '11-Decisions/ADR-003.md',
  '11-Technical Debt/Technical Debt Register.md',
  '12-Risks/Risk Register.md',
  '12-Tasks/Backlog.md',
  '12-Tasks/Current Sprint.md',
  '12-Tasks/Technical Tasks.md',
  '13-Blockers/BLOCKERS.md',
  '13-Bugs/Open Bugs.md',
  '13-Bugs/Fixed Bugs.md',
  '14-Blockers/BLOCKERS.md',
  '14-Decisions/ADR-001.md',
  '15-AI/AI Context.md',
  '15-AI/AI Instructions.md',
  '15-AI/Project Memory.md',
  '15-Tasks/Backlog.md',
  '15-Tasks/Active Sprint.md',
  '15-Tasks/Completed Tasks.md',
  '16-Diagrams/System Diagrams.md',
  '16-Diagrams/Sequence Diagrams.md',
  '16-Diagrams/Entity Relationships.md',
  '16-Progress/Weekly Progress.md',
  '16-Progress/Milestones.md',
  '17-Audit/Original Audit.md',
  '17-Audit/Audit Resolution Tracker.md'
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

$inboundCounts = @{}
$outboundCounts = @{}
foreach ($file in $markdownFiles) {
  $title = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
  if (-not $inboundCounts.ContainsKey($title)) {
    $inboundCounts[$title] = 0
    $outboundCounts[$title] = 0
  }
}

foreach ($file in $markdownFiles) {
  $title = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
  $text = Get-Content -Path $file.FullName -Raw
  $matches = [regex]::Matches($text, $linkPattern)
  $outboundCounts[$title] += $matches.Count
  foreach ($match in $matches) {
    $target = $match.Groups[1].Value.Trim()
    if ($inboundCounts.ContainsKey($target)) {
      $inboundCounts[$target] += 1
    }
  }
}

$missingInbound = $inboundCounts.GetEnumerator() |
  Where-Object { $_.Value -eq 0 } |
  Select-Object -ExpandProperty Key |
  Sort-Object -Unique

$missingOutbound = $outboundCounts.GetEnumerator() |
  Where-Object { $_.Value -eq 0 } |
  Select-Object -ExpandProperty Key |
  Sort-Object -Unique

if ($missingInbound.Count -gt 0) {
  Write-Error ("Vault notes without inbound wiki-links:`n" + ($missingInbound -join "`n"))
}

if ($missingOutbound.Count -gt 0) {
  Write-Error ("Vault notes without outbound wiki-links:`n" + ($missingOutbound -join "`n"))
}

Write-Host "Obsidian vault check passed. Markdown files: $($markdownFiles.Count)."
