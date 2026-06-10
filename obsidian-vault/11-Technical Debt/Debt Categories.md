# Debt Categories

Last updated: 2026-06-03

## Purpose

This note defines the technical debt categories used by [[Technical Debt Register]].

Related: [[Debt Prioritization]], [[Architecture Debt]], [[Scalability Debt]], [[Security Debt]], [[Performance Debt]], [[Testing Debt]], [[DevOps Debt]], [[UX Debt]], [[Master Roadmap]].

## Categories

| Category | Definition | Primary Risk | Category Note |
| --- | --- | --- | --- |
| Architecture | Debt caused by overloaded modules, unclear ownership, duplicated state truth, or weak separation of concerns. | Fixes create regressions because ownership is unclear. | [[Architecture Debt]] |
| Scalability | Debt that limits data volume, file size, message history, or Firebase/free-tier growth. | App works in small tests but fails under real usage. | [[Scalability Debt]] |
| Security | Debt that weakens rules, privacy, authorization, abuse protection, or sensitive-data handling. | Bad clients or logs can expose or corrupt data. | [[Security Debt]] |
| Performance | Debt that creates slow rendering, expensive rebuilds, low-power lag, or unnecessary CPU/I/O pressure. | App feels broken on slower devices. | [[Performance Debt]] |
| Testing | Debt caused by missing contract, emulator, integration, failure-taxonomy, or smoke tests. | Releases ship unproven behavior. | [[Testing Debt]] |
| DevOps | Debt in release gates, workflows, versioning, artifact metadata, or rollback/update safety. | Broken artifacts reach testers or old clients remain unsafe. | [[DevOps Debt]] |
| UX | Debt that creates confusing states, unsafe controls, missing feedback, or inconsistent interaction behavior. | Users cannot understand failures or recover from them. | [[UX Debt]] |

## Categorization Rules

- Assign each debt item one primary category.
- If a debt spans multiple categories, put the dominant production risk first and list secondary related systems in [[Technical Debt Register]].
- P0 security or release-gate debt outranks P1 architecture cleanup unless architecture debt directly blocks reliability.
- UX debt becomes P0 when it causes silent blocked actions, missing hangup, unsafe answer/decline, or impossible recovery.

## Review Cadence

- Review this category map at the end of every roadmap phase.
- Update [[Project Memory]] only when category rules change.
- Update [[Debt Prioritization]] when any P0 debt is closed or accepted.

