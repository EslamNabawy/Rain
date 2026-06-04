# AI Operating Notes

Last updated: 2026-06-04

## Purpose

Track operating notes for AI sessions that are too specific for root `AGENTS.md` but durable enough to preserve.

## Initial Notes

- Prefer PowerShell on this Windows project.
- Do not edit `D:\old project\Rain`.
- Do not modify application code during vault bootstrap work.
- Keep documentation changes linked through the vault command center and [[Templates Index]].

## Rain Autonomous Engineering System

For non-trivial Rain work, future AI sessions must explicitly identify the current workflow node. This makes incomplete work, skipped validation, and handoffs auditable.

Source-of-truth priority order:

1. Actual repository implementation.
2. Root `AGENTS.md`.
3. Root `CONTINUITY.md`.
4. [[Current Architecture]].
5. [[Project Memory]].
6. [[Risk Register]].
7. [[BLOCKERS]].
8. [[Technical Debt Register]].
9. User request.
10. External examples.

Reality enforcement:

- Never claim files, tests, builds, validation, CI, commits, or vault updates happened unless they actually happened.
- If validation was skipped, say `Not executed.`
- If vault validation was skipped after documentation changes, say `Vault validation not executed.`

Workflow nodes:

| Node | Name |
| --- | --- |
| 0 | Environment Verification |
| 1 | Knowledge Synchronization |
| 2 | Repository Discovery |
| 3 | Task Understanding |
| 4 | Impact Analysis |
| 5 | Pattern Discovery |
| 6 | Architecture Validation |
| 7 | Implementation Plan |
| 8 | Execution |
| 9 | Validation |
| 10 | Obsidian Synchronization |
| 11 | Vault Validation |
| 12 | Production Readiness Review |
| 13 | Version Control Preparation |
| 14 | Completion Report |

Related: [[AI Memory Index]], [[Project Memory]], [[AI Instructions]], [[Continuous Improvement Log]].
