# Phase 1: Architecture & Planning

Objectives
- Validate and align the OpenCode integration plan with six skills.
- Define system boundaries, interfaces, and data contracts to enable safe Phase 2 execution.
- Produce an explicit dependency graph to guide task rollouts and gating.

System Context
- OpenCode-based multi-agent workflow to implement a full-stack system using six skills:
  - tdd-workflow
  - security-review
  - backend-patterns
  - coding-standards
  - verification-loop
  - api-design
- The architecture leverages a planner, architect, and a set of domain agents (backend/frontend/db), with gatekeepers (code reviewer, security reviewer) and a verification/e2e pipeline.

Key Decisions
- Pattern choices: repository, service, middleware; API contracts defined by Architect; data models scoped to validation tasks.
- Data models (high level):
  - TaskUnit: id, description, inputs, outputs, status, dependencies
  - Plan: list of TaskUnits with done criteria
- Interfaces:
  - Backend surface: REST endpoints for plan/discovery, unit execution, and status reports
  - Frontend surface: UI to visualize plan, progress, and gating results (optional in Phase 1)
  - DB surface: lightweight store for tasks and results (mocked in Phase 1; not needed if read-only)
- Non-functional: ensure deterministic unit outputs, idempotent unit definitions, and auditable gating.

Architecture Diagram (ASCII)
```
                            +-----------------+
                            | Planner (Sonnet) |
                            +--------+--------+
                                     |
                                     v
                            +--------+--------+
                            | Architect (Opus) |
                            +--------+--------+
                                     |
            +------------------------+------------------------+
            |                         |                        |
            v                         v                        v
  Backend Agent (Sonnet)   Frontend Agent (Sonnet)   Database Agent (Sonnet)
            |                         |                        |
            v                         v                        v
   Gatekeepers: Code Reviewer Haiku, Security Reviewer Sonnet
                                     |
                                     v
                               Verification (Sonnet)
                                      |
                                      v
                                 E2E Runner (Haiku)
```

Data Models (high level)
- TaskUnit: { id, title, inputs, outputs, status, doneCondition, dependencies }
- Plan: { id, name, units: TaskUnit[] }

API Contracts (high level)
- POST /api/v1/plan: submit task description, receive plan_id and units
- GET /api/v1/plan/{plan_id}: fetch plan state, unit statuses, and next actions
- POST /api/v1/unit/{unit_id}/execute: trigger unit execution; gate through reviewers

Risks & Mitigations
- Risk: scope creep between planner and architect. Mitigation: strict per-unit scope and validation gates.
- Risk: misalignment of interfaces across backend/frontend/db. Mitigation: early, explicit interface specs and contract tests.

Deliverables for Phase 1
- Architecture doc (this file)
- Dependency graph for Phase 2 (see dependency graph in plans/)
- Plan for Phase 2 with per-unit done criteria

Notes
- Phase 1 focuses on alignment and plan stabilization; no production code changes in this phase beyond documentation.
