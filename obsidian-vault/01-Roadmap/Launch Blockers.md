# Launch Blockers

Last updated: 2026-06-05

## Purpose

Track audit-derived blockers that must close before public launch.

Related: [[Master Roadmap]], [[Critical Path]], [[BLOCKERS]], [[Risk Register]], [[Launch Readiness]].

## Blockers

| Blocker | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| PC/mobile voice-video reliability is not proven. | P0 | TASK-001, TASK-002, TASK-003, TASK-013 | 17 days | Calls start, connect, fail, and end deterministically. | Runtime tests and diagnostics prove expected state transitions. |
| False busy and stale call locks can block calls. | P0 | TASK-002, TASK-005 | 8 days | Stale locks repair once and live locks report true busy. | Emulator/fake tests cover stale/missing/corrupt/live locks. |
| Old version update prompt behavior is unreliable. | P0 | TASK-012 | 2 days | Old app versions see required or optional update correctly. | Version parser and UI tests pass. |
| Firebase rules coverage is incomplete for production. | P0 | TASK-005, TASK-018 | 9 days | Critical RTDB branches have allow/deny test coverage. | Rules/emulator tests are part of release evidence. |
| Diagnostics can hide root cause or expose private data. | P1 | TASK-004, TASK-014 | 5 days | Diagnostics classify failure cause while redacting sensitive payloads. | Phase 4 export privacy/taxonomy tests passed locally; selected-route, first-track, and first-frame diagnostics still need proof. |
| Release artifacts can be produced without enough gate proof. | P1 | TASK-015, TASK-016 | 4 days | Workflows separate fast artifacts and hard release gates. | Release documentation and workflow evidence exist. |

## Launch Blocker Definition Of Done

- No P0 blocker remains open.
- P1 blockers are closed or accepted with explicit risk owner.
- [[Production Readiness]] score is updated after evidence is collected.
