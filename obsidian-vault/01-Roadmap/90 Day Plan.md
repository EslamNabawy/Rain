# 90 Day Plan

Last updated: 2026-06-03

## Goal

Reach production-readiness confidence by completing validation gates, documenting remaining risks, and proving release artifacts come from the latest validated state.

Related: [[Master Roadmap]], [[Production Readiness]], [[Launch Readiness]], [[Release Gates]], [[High-Risk Work]].

## Day 61-75: Production Validation Systems

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-021: ARMv7/low-power performance budget | P1 | [[Release Gates]], [[Frontend Architecture]] | 3 days | Low-power tier expectations are explicit and tested. | Tests cover static/low-power visual path and diagnostics summary. |
| TASK-004: ICE/TURN failure classification completion | P1 | TASK-001, [[CallDiagnosticsRecorder]] | 3 days | Diagnostics distinguish Firebase, permission, ICE, TURN, media, first-frame failures. | Export tests include sanitized timeline and failure taxonomy. |
| TASK-023: Offline request guardrails | P0 | [[Connection Request Notifications]], [[Presence Management]] | 3 days | Offline request quota is spent only after offline confirmation. | Runtime, adapter, rules, and widget tests pass. |

## Day 76-90: Launch Gate Closure

| Item | Priority | Dependencies | Estimated Effort | Success Criteria | Definition Of Done |
| --- | --- | --- | --- | --- | --- |
| TASK-022: Continuous vault/memory maintenance | P2 | [[Project Memory]], [[Documentation Workflow]] | 1 day setup | Documentation remains a release artifact. | Vault validation is required and memory update rule is documented. |
| Launch blocker closure | P0 | [[Launch Blockers]], all P0 tasks | 5 days review | No P0 blocker remains open. | [[Launch Readiness]] and [[Production Readiness]] are updated with evidence. |
| Final release gate proof | P0 | [[Release Gates]], [[Coverage Dashboard]] | 3 days | Release artifacts prove commit, version, channel, tests, and rules state. | Validated workflow passes and release notes link validation evidence. |

## 90 Day Exit Criteria

- No open P0 launch blockers.
- Production readiness score is updated with evidence.
- Hard release gate validates app, Firebase, update, docs, and artifact metadata.
- Known remaining risks are explicit and accepted or deferred.

## 90 Day Definition Of Done

- [[Launch Readiness]] says whether public release is allowed.
- [[Production Readiness]] contains final scores and evidence.
- [[Audit Resolution Tracker]] shows completed/deferred status for all findings.
- [[Project Memory]] and [[Lessons Learned Index]] are updated.
- `.\scripts\check_obsidian_vault.ps1` passes.
