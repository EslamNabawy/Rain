# Regression Lessons

Last updated: 2026-06-03

## Purpose

Track regressions that should become tests, diagnostics, or process rules. Future phases will populate concrete entries from issue history and validation failures.

## Initial Structure

| ID | Regression | Trigger | Missing Guard | Follow-Up Test | Status |
| --- | --- | --- | --- | --- | --- |
| RL-001 | Late terminal voice signaling frames overwrote useful crash evidence. | 2026-06-03 diagnostics export. | Runtime treated expected terminal races as crash/error records. | `apps/rain/test/voice_call_runtime_diagnostics_contract_test.dart` locks late frames as diagnostics only. | [x] Covered |
| RL-002 | Android diagnostics export failed on `/document/1282` SAF handles. | Android screenshot and diagnostics export toast. | Picker return value was treated as a filesystem path. | `apps/rain/test/crash_diagnostics_service_test.dart` covers `/document/...` handles. | [x] Covered |
| RL-003 | Voice hangup could leave the other side active when session hangup failed. | User reports plus RCA terminal-state analysis. | Terminal Firebase room write ordering was not protected by a local, low-dependency regression. | `apps/rain/test/voice_call_runtime_diagnostics_contract_test.dart` locks terminal-room-before-session-hangup ordering. | [x] Covered |
| RL-004 | Failed media setup could look like a stuck connecting call or retry spam. | Voice/video failed setup reports. | Failed call surface and failure-message contracts were under-tested outside the Drift-backed runtime suite. | `apps/rain/test/rain_call_failure_messages_test.dart` and `apps/rain/test/rain_call_suite_models_test.dart`. | [x] Covered |
| RL-005 | Stale raw-online presence can revive closed peers. | App-close presence reports and Phase 05 findings. | Firebase presence contract did not explicitly lock session id, startedAt, state, and onDisconnect behavior. | `packages/protocol_brain/test/firebase_contract_test.dart` session-owned presence contract. | [x] Covered |

## Required Fields

- What broke.
- How it was discovered.
- Why existing tests missed it.
- Which test or gate prevents recurrence.

Related: [[Lessons Learned Index]], [[Test Strategy]], [[Coverage Dashboard]], [[Audit Resolution Tracker]].
