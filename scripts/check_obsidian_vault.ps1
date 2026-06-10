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
  '01-Roadmap/Parallel Work Streams.md',
  '01-Roadmap/Launch Blockers.md',
  '01-Roadmap/Quick Wins.md',
  '01-Roadmap/High-Risk Work.md',
  '02-Architecture/System Architecture.md',
  '02-Architecture/Frontend Architecture.md',
  '02-Architecture/Backend Architecture.md',
  '02-Architecture/Database Architecture Overview.md',
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
  '03-Architecture/Architecture Refactor Plan Index.md',
  '03-Architecture/VoiceCallRuntime Refactor.md',
  '03-Architecture/VoiceCallRuntime Refactor Plan.md',
  '03-Architecture/Firebase Lease Management Refactor Plan.md',
  '03-Architecture/Presence Management Refactor Plan.md',
  '03-Architecture/Message Loading Refactor Plan.md',
  '03-Architecture/File Transfer Runtime Refactor Plan.md',
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
  '07-Testing/Test Strategy Findings.md',
  '07-Testing/Coverage Report.md',
  '07-Testing/QA Findings.md',
  '08-Security/Security Roadmap.md',
  '08-Security/Privacy Review.md',
  '08-Security/Diagnostics Sanitization.md',
  '08-Security/Security Review.md',
  '08-Security/Permissions Matrix.md',
  '08-Security/Security Risk View.md',
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
  '11-Decisions/ADR-004.md',
  '11-Decisions/ADR-005.md',
  '11-Decisions/ADR-006.md',
  '11-Decisions/ADR-007.md',
  '11-Decisions/ADR-008.md',
  '11-Decisions/ADR-009.md',
  '11-Technical Debt/Technical Debt Register.md',
  '11-Technical Debt/Debt Categories.md',
  '11-Technical Debt/Debt Prioritization.md',
  '11-Technical Debt/Architecture Debt.md',
  '11-Technical Debt/Scalability Debt.md',
  '11-Technical Debt/Security Debt.md',
  '11-Technical Debt/Performance Debt.md',
  '11-Technical Debt/Testing Debt.md',
  '11-Technical Debt/DevOps Debt.md',
  '11-Technical Debt/UX Debt.md',
  '12-Risks/Risk Register.md',
  '12-Risks/Risk Categories.md',
  '12-Risks/Risk Matrix.md',
  '12-Tasks/Audit Task Summary.md',
  '12-Tasks/Current Sprint.md',
  '12-Tasks/Technical Tasks.md',
  '13-Blockers/Blocker Index.md',
  '13-Bugs/Open Bugs.md',
  '13-Bugs/Fixed Bugs.md',
  '14-Blockers/BLOCKERS.md',
  '14-Blockers/Blocker Resolution Plan.md',
  '15-AI/AI Context.md',
  '15-AI/AI Instructions.md',
  '15-Tasks/Backlog.md',
  '15-Tasks/Active Sprint.md',
  '15-Tasks/Completed Tasks.md',
  '16-Diagrams/System Diagrams.md',
  '16-Diagrams/Sequence Diagrams.md',
  '16-Diagrams/Entity Relationships.md',
  '16-Progress/Weekly Progress.md',
  '16-Progress/Milestones.md',
  '17-Audit/Original Audit.md',
  '17-Audit/Audit Resolution Tracker.md',
  '18-Lessons Learned/Lessons Learned Index.md',
  '18-Lessons Learned/Lessons Learned.md',
  '18-Lessons Learned/Engineering Insights.md',
  '18-Lessons Learned/Continuous Learning Rules.md',
  '18-Lessons Learned/Improvement Backlog.md',
  '18-Lessons Learned/Optimization Opportunities.md',
  '18-Lessons Learned/Project Metrics.md',
  '18-Lessons Learned/Recommended Next Actions.md',
  '18-Lessons Learned/Regression Lessons.md',
  '18-Lessons Learned/Release Lessons.md',
  '18-Lessons Learned/Architecture Lessons.md',
  '18-Lessons Learned/Continuous Improvement Log.md',
  '19-AI Memory/AI Memory Index.md',
  '19-AI Memory/Durable Facts.md',
  '19-AI Memory/Session Handoff.md',
  '19-AI Memory/Prompt Library.md',
  '19-AI Memory/AI Operating Notes.md',
  'AI-Memory/Project Memory.md',
  '20-Knowledge Graph/Knowledge Graph Index.md',
  '20-Knowledge Graph/Repository Map.md',
  '20-Knowledge Graph/Domain Map.md',
  '20-Knowledge Graph/Dependency Map.md',
  '20-Knowledge Graph/Decision Map.md',
  '20-Knowledge Graph/Feature Map.md',
  '20-Knowledge Graph/System Ownership Map.md',
  '99-Templates/Templates Index.md',
  '99-Templates/ADR Template.md',
  '99-Templates/Architecture Note Template.md',
  '99-Templates/Feature Template.md',
  '99-Templates/Risk Template.md',
  '99-Templates/Technical Debt Template.md',
  '99-Templates/Blocker Template.md',
  '99-Templates/Roadmap Phase Template.md',
  '99-Templates/Lesson Learned Template.md',
  '99-Templates/Progress Update Template.md'
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

$titleToPaths = @{}
foreach ($file in $markdownFiles) {
  $title = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
  if (-not $titleToPaths.ContainsKey($title)) {
    $titleToPaths[$title] = New-Object System.Collections.Generic.List[string]
  }
  $relative = Resolve-Path -Path $file.FullName -Relative
  $titleToPaths[$title].Add($relative)
}

$duplicateTitles = New-Object System.Collections.Generic.List[string]
foreach ($entry in $titleToPaths.GetEnumerator()) {
  if ($entry.Value.Count -gt 1) {
    $duplicateTitles.Add("$($entry.Key): $($entry.Value -join ' | ')")
  }
}

if ($duplicateTitles.Count -gt 0) {
  $uniqueDuplicateTitles = $duplicateTitles | Sort-Object -Unique
  Write-Error ("Duplicate Obsidian note titles:`n" + ($uniqueDuplicateTitles -join "`n"))
}

$noteTitles = @{}
foreach ($title in $titleToPaths.Keys) {
  $noteTitles[$title] = $true
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

$semanticErrors = New-Object System.Collections.Generic.List[string]

function Add-SemanticError {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $script:semanticErrors.Add($Message) | Out-Null
}

function Get-VaultMarkdown {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath
  )

  $path = Join-Path $VaultRoot $RelativePath
  if (-not (Test-Path -Path $path -PathType Leaf)) {
    Add-SemanticError "$RelativePath is missing and cannot be semantically validated."
    return ''
  }

  return Get-Content -Path $path -Raw
}

function Test-MeaningfulValue {
  param(
    [AllowNull()]
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $false
  }

  $normalized = $Value.Trim()
  $emptyMarkers = @('-', '...', 'TBD', 'TODO', 'N/A', 'None', 'Unknown')
  return -not ($emptyMarkers -contains $normalized)
}

function Split-MarkdownTableRow {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Line
  )

  $trimmed = $Line.Trim()
  if ($trimmed.StartsWith('|')) {
    $trimmed = $trimmed.Substring(1)
  }
  if ($trimmed.EndsWith('|')) {
    $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
  }

  $cells = New-Object System.Collections.Generic.List[string]
  foreach ($cell in ($trimmed -split '\|')) {
    $cells.Add($cell.Trim()) | Out-Null
  }
  return $cells.ToArray()
}

function Get-MarkdownTablesByHeader {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath,
    [Parameter(Mandatory = $true)]
    [string]$HeaderPattern
  )

  $text = Get-VaultMarkdown $RelativePath
  if ($text.Length -eq 0) {
    return @()
  }

  $lines = $text -split "`r?`n"
  $tables = New-Object System.Collections.Generic.List[object]

  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -notmatch $HeaderPattern) {
      continue
    }

    $headers = @(Split-MarkdownTableRow $lines[$i])
    $rows = New-Object System.Collections.Generic.List[object]

    for ($j = $i + 2; $j -lt $lines.Count; $j++) {
      $line = $lines[$j]
      if (-not $line.Trim().StartsWith('|')) {
        break
      }

      $cells = @(Split-MarkdownTableRow $line)
      if (($cells -join '') -match '^-+$') {
        continue
      }

      $row = [ordered]@{}
      for ($k = 0; $k -lt $headers.Count; $k++) {
        $value = ''
        if ($k -lt $cells.Count) {
          $value = $cells[$k]
        }
        $row[$headers[$k]] = $value
      }
      $rows.Add([pscustomobject]$row) | Out-Null
    }

    $tables.Add([pscustomobject]@{
      Path = $RelativePath
      HeaderLine = $i + 1
      Headers = $headers
      Rows = $rows.ToArray()
    }) | Out-Null
  }

  return $tables.ToArray()
}

function Get-MarkdownTableByHeader {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath,
    [Parameter(Mandatory = $true)]
    [string]$HeaderPattern,
    [Parameter(Mandatory = $true)]
    [string]$TableName
  )

  $tables = @(Get-MarkdownTablesByHeader $RelativePath $HeaderPattern)
  if ($tables.Count -eq 0) {
    Add-SemanticError "$RelativePath missing required table: $TableName."
    return $null
  }

  return $tables[0]
}

function Get-CellValue {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Row,
    [Parameter(Mandatory = $true)]
    [string]$Header
  )

  $property = $Row.PSObject.Properties[$Header]
  if ($null -eq $property) {
    return ''
  }
  return [string]$property.Value
}

function Assert-RequiredHeaders {
  param(
    [AllowNull()]
    [object]$Table,
    [Parameter(Mandatory = $true)]
    [string]$TableName,
    [Parameter(Mandatory = $true)]
    [string[]]$RequiredHeaders
  )

  if ($null -eq $Table) {
    return
  }

  foreach ($header in $RequiredHeaders) {
    if (-not ($Table.Headers -contains $header)) {
      Add-SemanticError "$($Table.Path) $TableName missing required header '$header'."
    }
  }
}

function Assert-RequiredCells {
  param(
    [AllowNull()]
    [object]$Table,
    [Parameter(Mandatory = $true)]
    [string]$TableName,
    [Parameter(Mandatory = $true)]
    [string]$KeyHeader,
    [Parameter(Mandatory = $true)]
    [string[]]$RequiredHeaders
  )

  if ($null -eq $Table) {
    return
  }

  if ($Table.Rows.Count -eq 0) {
    Add-SemanticError "$($Table.Path) $TableName has no data rows."
    return
  }

  foreach ($row in $Table.Rows) {
    $key = Get-CellValue $row $KeyHeader
    if (-not (Test-MeaningfulValue $key)) {
      $key = "line $($Table.HeaderLine)"
    }

    foreach ($header in $RequiredHeaders) {
      $value = Get-CellValue $row $header
      if (-not (Test-MeaningfulValue $value)) {
        Add-SemanticError "$($Table.Path) $TableName row '$key' missing meaningful '$header'."
      }
    }
  }
}

function Assert-RecentLastUpdated {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath,
    [int]$MaxAgeDays = 45
  )

  $text = Get-VaultMarkdown $RelativePath
  $match = [regex]::Match($text, '(?m)^Last updated:\s*(?<Date>\d{4}-\d{2}-\d{2})\s*$')
  if (-not $match.Success) {
    Add-SemanticError "$RelativePath missing parseable 'Last updated: YYYY-MM-DD'."
    return
  }

  $lastUpdated = [datetime]::MinValue
  if (-not [datetime]::TryParseExact(
      $match.Groups['Date'].Value,
      'yyyy-MM-dd',
      [System.Globalization.CultureInfo]::InvariantCulture,
      [System.Globalization.DateTimeStyles]::None,
      [ref]$lastUpdated)) {
    Add-SemanticError "$RelativePath has invalid Last updated date '$($match.Groups['Date'].Value)'."
    return
  }

  $today = (Get-Date).Date
  if ($lastUpdated.Date -le $today -and ($today - $lastUpdated.Date).Days -gt $MaxAgeDays) {
    Add-SemanticError "$RelativePath Last updated date is stale: $($match.Groups['Date'].Value)."
  }
}

function Assert-AllowedCellValues {
  param(
    [AllowNull()]
    [object]$Table,
    [Parameter(Mandatory = $true)]
    [string]$TableName,
    [Parameter(Mandatory = $true)]
    [string]$KeyHeader,
    [Parameter(Mandatory = $true)]
    [string]$ValueHeader,
    [Parameter(Mandatory = $true)]
    [string[]]$AllowedValues
  )

  if ($null -eq $Table) {
    return
  }

  foreach ($row in $Table.Rows) {
    $key = Get-CellValue $row $KeyHeader
    $value = Get-CellValue $row $ValueHeader
    if ((Test-MeaningfulValue $value) -and -not ($AllowedValues -contains $value)) {
      Add-SemanticError "$($Table.Path) $TableName row '$key' has unsupported $ValueHeader '$value'."
    }
  }
}

function Assert-PriorityRowsHaveNextAction {
  param(
    [AllowNull()]
    [object]$Table,
    [Parameter(Mandatory = $true)]
    [string]$TableName,
    [Parameter(Mandatory = $true)]
    [string]$KeyHeader,
    [Parameter(Mandatory = $true)]
    [string]$PriorityHeader,
    [Parameter(Mandatory = $true)]
    [string]$NextActionHeader
  )

  if ($null -eq $Table) {
    return
  }

  foreach ($row in $Table.Rows) {
    $priority = Get-CellValue $row $PriorityHeader
    if ($priority -notmatch 'P0|P1') {
      continue
    }

    $key = Get-CellValue $row $KeyHeader
    $nextAction = Get-CellValue $row $NextActionHeader
    if (-not (Test-MeaningfulValue $nextAction)) {
      Add-SemanticError "$($Table.Path) $TableName P0/P1 row '$key' has no meaningful $NextActionHeader."
    }
  }
}

function Get-RegisterSections {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RelativePath,
    [Parameter(Mandatory = $true)]
    [string]$IdPattern
  )

  $text = Get-VaultMarkdown $RelativePath
  $pattern = "(?ms)^### (?<Id>${IdPattern}):(?<Heading>[^\r\n]*)(?<Body>.*?)(?=^### ${IdPattern}:|^## |\z)"
  $sections = New-Object System.Collections.Generic.List[object]
  foreach ($match in [regex]::Matches($text, $pattern)) {
    $body = $match.Groups['Body'].Value
    $fields = @{}
    foreach ($fieldMatch in [regex]::Matches($body, '(?m)^- (?<Key>[A-Za-z][A-Za-z /-]+):\s*(?<Value>.*)$')) {
      $fields[$fieldMatch.Groups['Key'].Value.Trim()] = $fieldMatch.Groups['Value'].Value.Trim()
    }

    $sections.Add([pscustomobject]@{
      Id = $match.Groups['Id'].Value
      Heading = $match.Groups['Heading'].Value.Trim()
      Body = $body
      Fields = $fields
      Path = $RelativePath
    }) | Out-Null
  }

  return $sections.ToArray()
}

function Assert-SectionRequiredFields {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Sections,
    [Parameter(Mandatory = $true)]
    [string]$RegisterName,
    [Parameter(Mandatory = $true)]
    [string[]]$RequiredFields
  )

  if ($Sections.Count -eq 0) {
    Add-SemanticError "$RegisterName has no parseable register sections."
    return
  }

  foreach ($section in $Sections) {
    foreach ($field in $RequiredFields) {
      if (-not $section.Fields.ContainsKey($field) -or -not (Test-MeaningfulValue $section.Fields[$field])) {
        Add-SemanticError "$($section.Path) $($section.Id) missing meaningful '$field'."
      }
    }
  }
}

function Test-SectionHasEvidence {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Body
  )

  return $Body -match '(?i)(progress|passed|validated|validation|evidence|workflow|run\s+\d+|https?://|\[\[Project Metrics\]\])'
}

$semanticFiles = @(
  '17-Audit/Audit Resolution Tracker.md',
  '11-Technical Debt/Technical Debt Register.md',
  '12-Risks/Risk Register.md',
  '14-Blockers/BLOCKERS.md',
  '18-Lessons Learned/Project Metrics.md',
  '18-Lessons Learned/Recommended Next Actions.md',
  '20-Knowledge Graph/Repository Map.md'
)

foreach ($relativePath in $semanticFiles) {
  Assert-RecentLastUpdated $relativePath
}

$auditMatrix = Get-MarkdownTableByHeader `
  '17-Audit/Audit Resolution Tracker.md' `
  '^\|\s*#\s*\|\s*Audit Finding\s*\|\s*Epic\s*\|\s*Feature\s*\|\s*Task\s*\|\s*Status\s*\|\s*Next Step\s*\|' `
  'audit resolution matrix'
Assert-RequiredHeaders $auditMatrix 'audit resolution matrix' @('#', 'Audit Finding', 'Epic', 'Feature', 'Task', 'Status', 'Next Step')
Assert-RequiredCells $auditMatrix 'audit resolution matrix' '#' @('Audit Finding', 'Epic', 'Feature', 'Task', 'Status', 'Next Step')

$auditSarOverlay = Get-MarkdownTableByHeader `
  '17-Audit/Audit Resolution Tracker.md' `
  '^\|\s*SAR ID\s*\|\s*Existing Audit Rows\s*\|\s*Primary Phase\s*\|\s*Owner\s*\|\s*Priority\s*\|\s*Evidence Required\s*\|\s*Release Impact\s*\|\s*Status\s*\|' `
  'senior audit resolution overlay'
Assert-RequiredHeaders $auditSarOverlay 'senior audit resolution overlay' @('SAR ID', 'Existing Audit Rows', 'Primary Phase', 'Owner', 'Priority', 'Evidence Required', 'Release Impact', 'Status')
Assert-RequiredCells $auditSarOverlay 'senior audit resolution overlay' 'SAR ID' @('Existing Audit Rows', 'Primary Phase', 'Owner', 'Priority', 'Evidence Required', 'Release Impact', 'Status')
Assert-PriorityRowsHaveNextAction $auditSarOverlay 'senior audit resolution overlay' 'SAR ID' 'Priority' 'Evidence Required'

$riskOverlay = Get-MarkdownTableByHeader `
  '12-Risks/Risk Register.md' `
  '^\|\s*SAR ID\s*\|\s*Existing Risks\s*\|\s*Owner\s*\|\s*Severity\s*\|\s*Detection Strategy\s*\|\s*Release Impact\s*\|\s*Status\s*\|' `
  'senior audit risk overlay'
Assert-RequiredHeaders $riskOverlay 'senior audit risk overlay' @('SAR ID', 'Existing Risks', 'Owner', 'Severity', 'Detection Strategy', 'Release Impact', 'Status')
Assert-RequiredCells $riskOverlay 'senior audit risk overlay' 'SAR ID' @('Existing Risks', 'Owner', 'Severity', 'Detection Strategy', 'Release Impact', 'Status')

$activeRiskRegister = Get-MarkdownTableByHeader `
  '12-Risks/Risk Register.md' `
  '^\|\s*ID\s*\|\s*Category\s*\|\s*Risk\s*\|\s*Impact\s*\|\s*Probability\s*\|\s*Severity\s*\|\s*Mitigation\s*\|\s*Detection Strategy\s*\|\s*Owner\s*\|\s*Related Links\s*\|\s*Status\s*\|' `
  'active risk register'
Assert-RequiredHeaders $activeRiskRegister 'active risk register' @('ID', 'Category', 'Risk', 'Impact', 'Probability', 'Severity', 'Mitigation', 'Detection Strategy', 'Owner', 'Related Links', 'Status')
Assert-RequiredCells $activeRiskRegister 'active risk register' 'ID' @('Category', 'Risk', 'Impact', 'Probability', 'Severity', 'Mitigation', 'Detection Strategy', 'Owner', 'Related Links', 'Status')
Assert-AllowedCellValues $activeRiskRegister 'active risk register' 'ID' 'Probability' @('Low', 'Medium', 'High')
Assert-AllowedCellValues $activeRiskRegister 'active risk register' 'ID' 'Severity' @('Low', 'Medium', 'High', 'Critical')
Assert-AllowedCellValues $activeRiskRegister 'active risk register' 'ID' 'Status' @('Open', 'Watching', 'Mitigating', 'Mitigated', 'Accepted', 'Closed')

$blockerOverlay = Get-MarkdownTableByHeader `
  '14-Blockers/BLOCKERS.md' `
  '^\|\s*SAR ID\s*\|\s*Blocking Status\s*\|\s*Mapped Blockers\s*\|\s*Owner\s*\|\s*Exit Evidence\s*\|' `
  'senior audit blocker overlay'
Assert-RequiredHeaders $blockerOverlay 'senior audit blocker overlay' @('SAR ID', 'Blocking Status', 'Mapped Blockers', 'Owner', 'Exit Evidence')
Assert-RequiredCells $blockerOverlay 'senior audit blocker overlay' 'SAR ID' @('Blocking Status', 'Mapped Blockers', 'Owner', 'Exit Evidence')

$debtSections = @(Get-RegisterSections '11-Technical Debt/Technical Debt Register.md' 'TD-\d{3}')
Assert-SectionRequiredFields $debtSections 'technical debt register' @(
  'Category',
  'Status',
  'Priority',
  'Owner',
  'Title',
  'Description',
  'Risk',
  'Files Affected',
  'Related Systems',
  'Roadmap Tasks',
  'Resolution Strategy'
)

foreach ($section in $debtSections) {
  $priority = $section.Fields['Priority']
  $status = $section.Fields['Status']
  if ((Test-MeaningfulValue $status) -and -not (@('Open', 'In Progress', 'Mitigating', 'Mitigated', 'Closed', 'Accepted') -contains $status)) {
    Add-SemanticError "$($section.Path) $($section.Id) has unsupported Status '$status'."
  }
  if ((Test-MeaningfulValue $priority) -and -not (@('P0', 'P1', 'P2', 'P3') -contains $priority)) {
    Add-SemanticError "$($section.Path) $($section.Id) has unsupported Priority '$priority'."
  }
  if ($priority -match 'P0|P1' -and $status -notmatch 'Closed|Accepted' -and -not (Test-MeaningfulValue $section.Fields['Resolution Strategy'])) {
    Add-SemanticError "$($section.Path) $($section.Id) is P0/P1 and has no meaningful Resolution Strategy."
  }
  if ($status -match 'Closed|Accepted' -and -not (Test-SectionHasEvidence $section.Body)) {
    Add-SemanticError "$($section.Path) $($section.Id) is $status without validation or acceptance evidence."
  }
}

$blockerSections = @(Get-RegisterSections '14-Blockers/BLOCKERS.md' 'BLK-\d{3}')
Assert-SectionRequiredFields $blockerSections 'blocker register' @(
  'Status',
  'Severity',
  'Owner',
  'Type',
  'Related Risks',
  'Related Roadmap Tasks',
  'Related Debt',
  'Impact',
  'Workaround Strategy',
  'Parallel Progress Path',
  'Exit Criteria',
  'Detection Strategy'
)

foreach ($section in $blockerSections) {
  $severity = $section.Fields['Severity']
  $status = $section.Fields['Status']
  if ((Test-MeaningfulValue $severity) -and -not (@('Low', 'Medium', 'High', 'Critical') -contains $severity)) {
    Add-SemanticError "$($section.Path) $($section.Id) has unsupported Severity '$severity'."
  }
  if ($status -match 'Closed' -and -not (Test-SectionHasEvidence $section.Body)) {
    Add-SemanticError "$($section.Path) $($section.Id) is closed without validation evidence."
  }
  if ($severity -match 'High|Critical' -and $status -notmatch 'Closed|Accepted' -and -not ($section.Body -match '(?m)^- Resolution Plan:')) {
    Add-SemanticError "$($section.Path) $($section.Id) is High/Critical and has no Resolution Plan."
  }
}

$evidenceTables = @(Get-MarkdownTablesByHeader `
  '18-Lessons Learned/Project Metrics.md' `
  '^\|\s*Date\s*\|\s*Branch\s*\|\s*Base Commit\s*\|\s*Scope\s*\|\s*Command\s*\|\s*Result\s*\|\s*Evidence\s*\|')

if ($evidenceTables.Count -eq 0) {
  Add-SemanticError '18-Lessons Learned/Project Metrics.md missing evidence ledger tables.'
}

foreach ($table in $evidenceTables) {
  Assert-RequiredHeaders $table 'evidence ledger' @('Date', 'Branch', 'Base Commit', 'Scope', 'Command', 'Result', 'Evidence')
  Assert-RequiredCells $table 'evidence ledger' 'Scope' @('Date', 'Branch', 'Base Commit', 'Scope', 'Command', 'Result', 'Evidence')
  Assert-AllowedCellValues $table 'evidence ledger' 'Scope' 'Result' @('Passed', 'Failed', 'Skipped', 'Blocked')

  foreach ($row in $table.Rows) {
    $scope = Get-CellValue $row 'Scope'
    $date = Get-CellValue $row 'Date'
    $baseCommit = (Get-CellValue $row 'Base Commit').Trim('`')
    $result = Get-CellValue $row 'Result'
    $evidence = Get-CellValue $row 'Evidence'

    if ($date -notmatch '^\d{4}-\d{2}-\d{2}$') {
      Add-SemanticError "$($table.Path) evidence ledger row '$scope' has invalid Date '$date'."
    }
    if ($baseCommit -notmatch '^[0-9a-fA-F]{7,40}$') {
      Add-SemanticError "$($table.Path) evidence ledger row '$scope' has invalid Base Commit '$baseCommit'."
    }
    if ($result -eq 'Passed' -and $evidence -match '(?i)\b(TBD|TODO|pending)\b') {
      Add-SemanticError "$($table.Path) evidence ledger row '$scope' is Passed but evidence is pending."
    }
  }
}

if ($semanticErrors.Count -gt 0) {
  $uniqueSemanticErrors = $semanticErrors | Sort-Object -Unique
  Write-Error ("Obsidian semantic validation failed:`n" + ($uniqueSemanticErrors -join "`n"))
}

Write-Host "Obsidian vault check passed. Markdown files: $($markdownFiles.Count)."
