# AI Operating Notes

Last updated: 2026-06-05

## Purpose

Track operating notes for AI sessions that are too specific for root `AGENTS.md` but durable enough to preserve.

## Initial Notes

- Prefer PowerShell on this Windows project.
- Do not edit `D:\old project\Rain`.
- Do not modify application code during vault bootstrap work.
- Keep documentation changes linked through the vault command center and [[Templates Index]].

## AI Tooling Overlay

Installed in the active Rain repo on 2026-06-05.

- Root `AGENTS.md` contains a marked AI overlay block.
- `.ai/tool-routing.md` routes Context7, OpenViking, Promptfoo, Impeccable, and agency-role usage.
- `scripts/ai/import-openviking.ps1` imports repository context, Obsidian context, or both.
- Promptfoo is not enabled by default because Rain has AI operating docs but no runtime LLM behavior.
- The overlay is guidance/tooling only and must not change app runtime behavior, dependency graph, CI gates, hooks, release workflows, or deployment behavior by default.

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

## Scenario Intelligence Mode

When the task is testing strategy, scenario generation, risk discovery, QA intelligence, or failure analysis, use [[Scenario Intelligence Agent]] after the normal Rain Autonomous Engineering System startup.

Scenario-intelligence work must derive scenarios from:

- [[System Model]]
- [[Feature Map]]
- [[Dependency Map]]
- [[State Graph]]
- [[Business Rule Graph]]
- [[Assumption Register]]
- [[Failure Graph]]

Durable findings belong in the vault graph notes, risk register, debt register, blockers, or recommended next actions. Do not treat generated scenarios as validated unless the named test or check was actually executed.

Related: [[AI Memory Index]], [[Project Memory]], [[AI Instructions]], [[Continuous Improvement Log]], [[Scenario Intelligence Agent]].
