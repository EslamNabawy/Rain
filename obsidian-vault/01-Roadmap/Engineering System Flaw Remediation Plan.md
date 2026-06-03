# Engineering System Flaw Remediation Plan

Last updated: 2026-06-03

## Purpose

This plan analyzes flaws in Rain's current Obsidian-driven engineering operating system and defines the remediation path before Phase 9 automation work begins.

Scope: repository governance, documentation quality, knowledge graph integrity, task tracking, validation, and continuous improvement. This is not an app-code refactor plan.

Related: [[Project Home]], [[Project Memory]], [[Master Roadmap]], [[Technical Debt Register]], [[Risk Register]], [[BLOCKERS]], [[Engineering Insights]], [[Improvement Backlog]], [[Project Metrics]], [[Recommended Next Actions]], [[Knowledge Graph Index]], [[Continuous Learning Rules]].

## Executive Assessment

The repository has a strong written operating model, but the current system still depends too much on manual discipline. The highest-risk flaw is not missing documentation; it is weak enforcement. The vault says documentation is mandatory, lessons must be captured, roadmap progress must be updated, and blockers must never stop progress, but the current validator mostly checks required files and wiki-link existence.

The operating system is useful, but it is not yet production-grade. It must become measurable, canonical, and gate-enforced.

## Flaw Register

| ID | Severity | Flaw | Impact | Root Cause | Professional Fix |
| --- | --- | --- | --- | --- | --- |
| ESF-001 | Critical | Manual-only governance enforcement. | Future sessions can skip required reading or post-change doc updates without detection. | `AGENTS.md` defines rules, but tooling does not verify them. | Add machine-readable session and completion gates in Phase 9. |
| ESF-002 | Critical | Duplicate note titles create ambiguous Obsidian links. | `[[Risk Register]]`, `[[BLOCKERS]]`, `[[Backlog]]`, `[[Test Strategy]]`, and similar links can resolve to the wrong note. | Bootstrap phases preserved older folder layouts instead of canonicalizing them. | Define canonical source notes, convert secondary notes to clearly named views, and add duplicate-title validation. |
| ESF-003 | High | Vault validator is structural, not semantic. | A stale roadmap, wrong phase state, outdated metrics, or contradicted blocker status can pass validation. | Current checker validates files, links, inbound links, and outbound links only. | Extend validation to duplicate titles, required front-matter/status fields, stale dates, and phase consistency. |
| ESF-004 | High | Task status is fragmented and not machine-readable. | Roadmap tasks, backlog items, audit tracker entries, recommended actions, and lessons can drift. | Task information is written in prose tables across many notes. | Add a canonical task ledger or strict task schema and generate views from it. |
| ESF-005 | High | Metrics are static snapshots. | Scores and counts can look authoritative while being stale. | Metrics are manually updated after phases. | Generate or verify risk/debt/blocker/task counts from source notes. |
| ESF-006 | High | No evidence ledger for validation runs. | A task can be marked done without durable proof of tests, vault checks, or release gates. | Validation evidence is described in roadmaps but not tracked centrally. | Create a validation evidence log tied to tasks, commits, commands, and outcomes. |
| ESF-007 | High | Lessons learned are required but unenforced. | The project can repeat failures after implementation cycles. | Lesson capture is a rule, not a gate. | Add a completion checklist requiring lesson entry or explicit "no new lesson" entry. |
| ESF-008 | Medium | Ownership and aging are weak. | Risks, blockers, and debt can remain open without review pressure. | Owners are role labels; review dates and aging are not tracked consistently. | Add owner, review cadence, opened date, last reviewed date, and aging status fields. |
| ESF-009 | Medium | Recommendation generation is manual. | Recommended next actions can lag behind current risks and blockers. | Recommendations are updated by authors, not computed from priority signals. | Add a recommendation scoring rule driven by P0/P1 debt, blockers, and dependency order. |
| ESF-010 | Medium | Knowledge graph can become noisy. | Future sessions may read too much or follow weak links instead of canonical notes. | Many notes link broadly, and duplicate note titles reduce precision. | Add canonical "read-first" paths and view notes that explicitly defer to source notes. |
| ESF-011 | Medium | No stale-document detection. | Notes can keep old phase, branch, commit, metric, or blocker information. | `Last updated` is human maintained. | Add stale-date checks for active operational notes. |
| ESF-012 | Medium | No release-readiness evidence tie-in. | Release decisions can be disconnected from vault status. | Release gates and vault governance are documented separately. | Link hard release workflow outputs to the validation evidence log and dashboard. |

## Dependency-Driven Remediation Phases

### Phase 00: Canonical Source Lock

- Purpose: Decide which notes are authoritative before changing validators or automations.
- Dependencies: Existing vault structure, [[Project Memory]], [[Master Roadmap]], [[Technical Debt Register]], [[Risk Register]], [[BLOCKERS]].
- Actions:
  - Identify every duplicated note title.
  - Choose one canonical note for each duplicated domain.
  - Mark non-canonical notes as redirects, views, or legacy notes.
  - Update [[Project Home]] to point only at canonical sources.
- Success criteria:
  - Every major domain has exactly one source-of-truth note.
  - Secondary notes clearly link back to the canonical note.
- Definition of done:
  - Duplicate-title remediation plan is complete and ready for execution.
  - No source-of-truth domain is ambiguous.

### Phase 01: Duplicate Note And Link Ambiguity Cleanup

- Purpose: Remove the highest-risk knowledge graph ambiguity.
- Dependencies: Phase 00.
- Actions:
  - Rename or repurpose duplicate `Risk Register`, `BLOCKERS`, `Backlog`, `Test Strategy`, `Database Architecture`, and `ADR-001` notes.
  - Replace ambiguous wiki-links with canonical links.
  - Add validator check that fails on duplicate note titles unless explicitly allowlisted.
- Success criteria:
  - Plain Obsidian links resolve predictably.
  - The vault checker detects accidental duplicate note names.
- Definition of done:
  - Duplicate title report is clean or contains only approved aliases.
  - Vault validation passes.

### Phase 02: Machine-Readable Task, Risk, Debt, And Blocker Schema

- Purpose: Make project status verifiable instead of prose-only.
- Dependencies: Phase 01.
- Actions:
  - Define required fields for tasks, risks, debt, blockers, improvements, and lessons.
  - Add stable IDs and normalized statuses.
  - Add opened date, last reviewed date, owner, priority, and linked validation evidence fields.
  - Keep Markdown readable, but parseable by PowerShell.
- Success criteria:
  - Status data can be checked by script without interpreting paragraphs.
  - Every P0/P1 item links to an owner, dependency, and next action.
- Definition of done:
  - Schema documented in [[Project Conventions]] or a vault governance note.
  - Sample parser validates the critical notes.

### Phase 03: Validation Evidence Ledger

- Purpose: Record proof that work actually passed validation.
- Dependencies: Phase 02.
- Actions:
  - Create a central validation evidence note.
  - Record command, date, commit, target task, result, and artifact path or workflow URL.
  - Link evidence from roadmap tasks, blockers, debt, and release readiness.
- Success criteria:
  - A task cannot be considered closed without linked evidence or accepted risk.
  - Release readiness can be audited from the vault.
- Definition of done:
  - Evidence ledger has an entry format and first baseline entries.

### Phase 04: Vault Validator Expansion

- Purpose: Convert governance rules into hard checks.
- Dependencies: Phases 01-03.
- Actions:
  - Extend `scripts/check_obsidian_vault.ps1`.
  - Add checks for duplicate titles, stale active notes, required status fields, missing evidence links, and current phase consistency.
  - Keep checks deterministic and fast.
- Success criteria:
  - Validator catches the current known flaws.
  - False positives are limited by clear allowlists.
- Definition of done:
  - Vault validation becomes the hard docs gate for future implementation completion.

### Phase 05: Lesson Capture Gate

- Purpose: Stop repeated failures from escaping into the next cycle.
- Dependencies: Phase 04.
- Actions:
  - Add a completion rule: every completed task needs a lesson entry or a "no new lesson" entry.
  - Add recurring-pattern counter rules.
  - Link new lessons to improvements and recommended next actions.
- Success criteria:
  - Completed tasks cannot silently skip learning capture.
  - Repeated patterns promote into improvement backlog items.
- Definition of done:
  - Validator or checklist catches missing lesson capture for completed tasks.

### Phase 06: Metrics And Recommendation Generation

- Purpose: Make dashboard scores and next actions traceable.
- Dependencies: Phases 02-05.
- Actions:
  - Generate or verify counts for blockers, risks, debt, lessons, improvement items, and active tasks.
  - Define a scoring rule for [[Recommended Next Actions]].
  - Mark manual metrics as estimates when they cannot be computed.
- Success criteria:
  - Dashboard numbers do not drift silently.
  - Recommended actions reflect actual P0/P1 blockers and dependency order.
- Definition of done:
  - [[Project Metrics]] documents generated and manual fields separately.

### Phase 07: Owner, Aging, And Review Loop

- Purpose: Prevent risks, blockers, and debt from becoming permanent background noise.
- Dependencies: Phase 02.
- Actions:
  - Add opened date and review deadline to each active P0/P1 item.
  - Flag overdue blocker reviews.
  - Add cadence to [[Weekly Progress]] and [[Current Sprint]].
- Success criteria:
  - Aging critical items are visible.
  - Owners can see what requires review before release work.
- Definition of done:
  - Review cadence is documented and validator warns on overdue critical items.

### Phase 08: Release Gate Integration

- Purpose: Connect documentation quality to artifact trust.
- Dependencies: Phases 03-06.
- Actions:
  - Require vault validation before hard release artifact publication.
  - Include validation evidence link in release notes or workflow summary.
  - Record release workflow runs in the evidence ledger.
- Success criteria:
  - Testers can distinguish fast artifacts from hard-gated artifacts.
  - Release artifacts have commit, version, channel, and validation status.
- Definition of done:
  - [[Release Gates]] links to evidence requirements and workflow behavior.

### Phase 09: Continuous Improvement Automation

- Purpose: Make the self-improvement system self-checking.
- Dependencies: Phases 04-08.
- Actions:
  - Add scripts for status extraction, stale note detection, next-action ranking, and evidence reporting.
  - Keep scripts PowerShell-first because this repo is currently Windows-oriented.
  - Avoid overbuilding dashboards until the schemas stabilize.
- Success criteria:
  - Future sessions get a reliable preflight report.
  - The vault exposes contradictions before implementation starts.
- Definition of done:
  - Phase 9 Codex Automation Layer can start with clear scope.

## Commit-Style Improvement Log

These are discrete improvements that should not be bundled silently:

- `docs: declare canonical vault source policy`
- `docs: remove duplicate Obsidian note ambiguity`
- `tools: detect duplicate vault note titles`
- `docs: define parseable task risk debt blocker schema`
- `docs: add validation evidence ledger`
- `tools: validate stale operational notes`
- `tools: validate completed task evidence links`
- `docs: require lesson or no-new-lesson entry per completed task`
- `tools: verify dashboard metrics against source registers`
- `docs: add owner aging review model`
- `ci: wire vault validation into hard release gate`
- `tools: generate recommended next action candidates`

## Immediate Next Action

Start with Phase 00 and Phase 01 before writing more automation. Automation built on ambiguous sources will preserve the current flaws instead of fixing them.

## Non-Goals

- Do not refactor app code in this remediation plan.
- Do not create a paid backend dependency.
- Do not replace Obsidian Markdown with an external project management tool.
- Do not make every vault note machine-readable immediately; start with critical operational notes.

## Acceptance Criteria

This remediation is successful when:

- The vault has no uncontrolled duplicate note titles.
- Critical project status is parseable and validated.
- Completed tasks require linked validation evidence.
- Lessons and recommendations cannot be skipped silently.
- Release artifacts can point to a vault-backed validation record.
- Future AI sessions can run one preflight and see current phase, risks, blockers, debt, next actions, and stale-document warnings.
