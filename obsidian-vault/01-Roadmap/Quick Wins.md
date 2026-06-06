# Quick Wins

Last updated: 2026-06-05

## Purpose

Identify low-effort audit-derived improvements that can reduce risk quickly without destabilizing major systems.

Related: [[Master Roadmap]], [[30 Day Plan]], [[Production Readiness]], [[Audit Resolution Tracker]].

## Quick Wins

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-012: Add version comparison and prompt tests. | P0 | [[Version And Updates]] | 2 days | Old/current/newer version states are deterministic. | Tests pass and docs update. |
| TASK-014: Add diagnostics sanitizer tests. | P1 | [[Diagnostics Sanitization]] | 2 days | Sensitive payload keys are redacted. | Done locally 2026-06-05; recursive export/debug-log tests pass and new private fields need samples. |
| TASK-007: Add corrupt watch stream tests. | P1 | [[Firebase Architecture]] | 2 days | Corrupt inbox/room does not poison watcher. | Tests prove stream survives. |
| TASK-015: Document hard release gate matrix. | P1 | [[Release Gates]] | 1 day | Gate responsibilities are unambiguous. | CI/CD docs updated. |
| TASK-017: Define Firebase event budgets. | P1 | [[Firebase Architecture]] | 1 day | Presence/call/ICE/request budgets are documented. | Budget note and diagnostics requirements updated. |
| TASK-022: Keep memory/vault validation current. | P2 | [[Project Memory]] | 1 day setup | Future AI sessions use one memory note. | Vault checker passes and links remain healthy. |

## Quick Win Rule

Quick wins cannot replace [[Critical Path]] work. They should be done early only when they reduce risk without delaying P0 call/signaling fixes.
