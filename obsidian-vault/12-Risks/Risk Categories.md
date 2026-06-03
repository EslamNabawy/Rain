# Risk Categories

Last updated: 2026-06-03

## Purpose

This note defines the risk categories used by [[Risk Register]].

Related: [[Risk Matrix]], [[BLOCKERS]], [[Technical Debt Register]], [[Master Roadmap]], [[Launch Readiness]].

## Categories

| Category | Definition | Typical Owner | Common Detection |
| --- | --- | --- | --- |
| Technical | Runtime, WebRTC, Firebase, media, state, or algorithm failures. | Engineering | Unit/integration tests, diagnostics, failure taxonomy. |
| Product | User-facing behavior, update prompts, call UX, blocked actions, or trust issues. | Product/UI | Widget tests, UX review, user-message matrix. |
| Architecture | Ownership, boundaries, duplicated truth, or cross-module coupling failures. | Engineering Lead | Architecture review, contract tests, dependency maps. |
| Scalability | Data volume, file size, Firebase usage, or low-end device growth limits. | Engineering/Ops | Load tests, migration tests, cost counters. |
| Security | Authorization, privacy, malformed writes, diagnostics leakage, or abuse. | Security/Engineering | Rules emulator tests, sanitizer tests, deny tests. |
| Operational | Release, CI/CD, smoke testing, update safety, and production workflow risks. | DevOps/QA | Release gates, artifact metadata, smoke evidence. |

## Ownership Rule

Every risk in [[Risk Register]] must have one owner area. Ownership means:

- track the risk,
- maintain mitigation,
- define detection,
- update status,
- escalate when severity changes.

## Linking Rule

Every risk must link to:

- at least one architecture or feature note,
- at least one roadmap task,
- at least one debt item in [[Technical Debt Register]] where applicable,
- a blocker in [[BLOCKERS]] if severity is Critical.

## Review Cadence

- Review Critical risks before every release workflow.
- Review High risks at sprint planning.
- Review Medium/Low risks during roadmap updates.
- Update [[Project Memory]] only when the risk model changes durably.

