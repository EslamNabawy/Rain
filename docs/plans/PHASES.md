# Rain Master Phases

This file defines the long-term phase sequence for turning Rain into a self-documenting, self-improving engineering system.

Phase 0 is the current foundation phase. Do not proceed to Phase 1 until the user explicitly asks.

## Phase 1 - Obsidian Vault Bootstrap

### Purpose

Create or normalize the Obsidian vault structure that future documentation will live in.

### Expected Outputs

- Vault folders.
- Core dashboard notes.
- Initial indexes.
- Basic vault validation.

### Dependencies

- Phase 0 operating files.

### Success Criteria

- Required vault files exist.
- Wiki links resolve.
- Future phases have a place to write architecture, risks, roadmaps, tasks, metrics, and knowledge graph data.

## Phase 2 - Repository Discovery

### Purpose

Map the repository structure and identify the real app modules, packages, tools, workflows, and integration points.

### Expected Outputs

- Repository map.
- Package map.
- Tooling map.
- Initial dependency notes.

### Dependencies

- Phase 1 vault bootstrap.

### Success Criteria

- A future engineer can understand the repo layout without reading every file.
- No implementation plan is created before the repo is understood.

## Phase 3 - Project Memory Generation

### Purpose

Capture durable project knowledge for future AI and human sessions.

### Expected Outputs

- Project memory note.
- Business rules.
- Technical constraints.
- Known historical lessons.

### Dependencies

- Phase 2 repository discovery.

### Success Criteria

- A new session can recover project context quickly.
- Durable facts are separated from temporary speculation.

## Phase 4 - Audit to Roadmap Conversion

### Purpose

Convert audit findings and discovered problems into dependency-driven roadmap work.

### Expected Outputs

- Audit tracker.
- Master roadmap.
- Epic list.
- Critical path.

### Dependencies

- Phase 3 project memory.

### Success Criteria

- Every major finding has a roadmap destination.
- No critical issue is left as untracked chat history.

## Phase 5 - Technical Debt System

### Purpose

Create a structured way to record, rank, and resolve technical debt.

### Expected Outputs

- Technical debt register.
- Debt severity model.
- Debt resolution workflow.

### Dependencies

- Phase 4 roadmap conversion.

### Success Criteria

- Debt is explicit, prioritized, and linked to affected systems.
- New debt cannot be introduced silently.

## Phase 6 - Risk and Blocker Intelligence

### Purpose

Track risks and blockers with clear owner, impact, mitigation, and exit criteria.

### Expected Outputs

- Risk register.
- Blocker register.
- Escalation rules.

### Dependencies

- Phase 5 technical debt system.

### Success Criteria

- Critical risks are visible before release decisions.
- Blockers do not stop all work when adjacent safe work exists.

## Phase 7 - Architecture Refactor Planning

### Purpose

Plan architecture changes from current state to target state without breaking working features.

### Expected Outputs

- Current architecture notes.
- Target architecture notes.
- Refactoring strategy.
- Dependency-ordered refactor plan.

### Dependencies

- Phase 6 risk and blocker intelligence.

### Success Criteria

- Refactors have acceptance criteria and validation gates.
- High-risk runtime systems have clear boundaries before code changes.

## Phase 8 - Self-Improvement Engine

### Purpose

Create feedback loops so failures improve the process, tests, docs, and architecture.

### Expected Outputs

- Lessons learned process.
- Regression learning rules.
- Improvement backlog.
- Quality metrics plan.

### Dependencies

- Phase 7 architecture refactor planning.

### Success Criteria

- Repeated bugs generate better tests, docs, or guardrails.
- The system captures why failures happened and how to prevent repeats.

## Phase 9 - Codex Automation Layer

### Purpose

Add automation around documentation validation, roadmap upkeep, task tracking, and release readiness.

### Expected Outputs

- Automation scripts.
- CI checks for documentation health.
- Optional helper prompts or workflows.

### Dependencies

- Phase 8 self-improvement engine.

### Success Criteria

- Automation supports engineering work without hiding responsibility.
- Scripts fail clearly and do not mutate unrelated files unexpectedly.

## Phase 10 - Continuous Project Evolution

### Purpose

Operate the repository as a living engineering system.

### Expected Outputs

- Routine vault updates.
- Periodic roadmap refresh.
- Risk and debt burn-down.
- Release readiness reports.
- Knowledge graph improvements.

### Dependencies

- Phase 9 Codex automation layer.

### Success Criteria

- Project knowledge stays current.
- New features, fixes, risks, decisions, and lessons are captured continuously.
- The repo becomes easier to maintain over time.
