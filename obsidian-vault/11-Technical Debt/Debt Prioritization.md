# Debt Prioritization

Last updated: 2026-06-03

## Purpose

This note defines how Rain ranks technical debt from [[Technical Debt Register]].

Related: [[Debt Categories]], [[Critical Path]], [[Launch Blockers]], [[High-Risk Work]], [[30 Day Plan]], [[60 Day Plan]], [[90 Day Plan]], [[Prioritized Remediation Roadmap]].

## Priority Formula

Debt priority is based on:

1. User-facing failure risk.
2. Security or privacy exposure.
3. Release-blocking impact.
4. Difficulty to diagnose after release.
5. Cost to ignore compared with cost to fix.
6. Number of systems affected.
7. Dependency position in [[Critical Path]].

## P0 Debt

| Debt | Why It Is P0 | Roadmap Task |
| --- | --- | --- |
| TD-001 | Call reliability cannot be proven while runtime ownership is mixed. | TASK-001 |
| TD-003 | False busy and stale locks can block calls globally. | TASK-002 |
| TD-004 | Stuck connecting and remote hangup failures are terminal-state failures. | TASK-003, TASK-013 |
| TD-009 | Rules regressions can deny valid users or allow malformed writes. | TASK-005 |
| TD-011 | Unauthorized signaling writes can corrupt call/request state. | TASK-005 |
| TD-017 | Release artifacts must not publish without gate evidence. | TASK-015 |
| TD-018 | Old versions must receive update prompts before backend incompatibility. | TASK-012 |
| TD-020 | Offline request guardrails must not silently block or spend quota incorrectly. | TASK-023 |

## P1 Debt

| Debt | Why It Is P1 | Roadmap Task |
| --- | --- | --- |
| TD-002 | Runtime domain concentration slows future fixes but can be phased after call split. | TASK-001, TASK-020 |
| TD-005 | Bad call UI can make working calls feel broken. | TASK-019 |
| TD-006 | Missing indexes harm larger local datasets. | TASK-008 |
| TD-007 | Missing pagination harms large chat histories and lower-end devices. | TASK-009 |
| TD-008 | File transfer pressure can crash data channels or memory. | TASK-010, TASK-011 |
| TD-010 | Diagnostics privacy must be proven before support-scale exports. | TASK-014 |
| TD-012 | Free-tier cost visibility protects Spark operating constraint. | TASK-017 |
| TD-013 | ARMv7/low-power builds need explicit budget. | TASK-021 |
| TD-015 | Contract tests prevent Firebase/app mismatch releases. | TASK-018 |
| TD-016 | Failure taxonomy is required for effective WebRTC debugging. | TASK-004 |
| TD-019 | Call surface UX must be stable before production polish. | TASK-019 |

## P2 Debt

| Debt | Why It Is P2 | Roadmap Task |
| --- | --- | --- |
| TD-014 | Broad rebuild cleanup improves performance after pagination/surface work. | TASK-020 |
| TD-016 workflow overlap portion | Workflow consolidation can follow hard gate parity. | TASK-016 |
| TD-020 documentation portion | Memory discipline is ongoing after roadmap foundation. | TASK-022 |

## Execution Rule

- Work P0 debt in [[Critical Path]] order.
- Use [[Parallel Work Streams]] for P1 debt that does not touch call runtime internals.
- A debt item cannot close until the linked roadmap task passes validation and impacted vault notes are updated.
