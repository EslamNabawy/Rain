# 02 — PHASE 01: Call Reliability Hardening

**Master ref:** `01_IMPLEMENTATION_MASTER_PLAN.md` · **Backlog:** `02_ENGINEERING_BACKLOG.md` (TASK-005,006,007,008,016)
**Goal:** Kill the cheap, high-impact call-correctness bugs and make `failed` a strictly-terminal call state.
**Why now:** All 5 tasks are LOW-risk and independent (except 006 gates 004 later). They remove the exact race classes the last 3 commits fixed — defense-in-depth before the XL refactor.
**Estimated effort:** 1 week (5 × ≤1d tasks). **Risk:** LOW.
**Prerequisites:** `dev@6ed4a00`; `dart analyze` green (confirm at Task 1).
**Exit criteria:** P1 DoD (§10) met; `07_PRODUCTION_READINESS_CHECKLIST.md` Reliability = PARTIAL→better.
**Deliverables:** 5 merged PRs; updated `CONTINUITY.md`; vault risk/debt update.

---

## TASK-005 — Move outgoing Firebase watcher before `startOutgoing()`

### Overview
- **Objective:** Subscribe to the Firebase voice-call watcher **before** sending the outgoing invite so a fast remote answer is never missed.
- **Business value:** Eliminates "call sits in ringing then fails after 45s" — the most visible call-reliability complaint.
- **Technical value:** Symmetric call-establishment ordering with the incoming path.
- **Dependencies:** none. **Risk:** LOW.

### Current State
- `apps/rain/lib/application/runtime/voice_call_runtime.dart:163-169`:
```dart
final session = await _createVoiceCallSession(...);
await session.startOutgoing();            // sends invite FIRST
await _watchFirebaseVoiceCall(                 // subscribe AFTER (gap)
  session: session, peerId: peerId, isOutgoing: true,
);
```
- Incoming path `:1290-1296` subscribes **before** handling invite → confirms asymmetry is a bug.
- **Root cause:** watcher subscription ordered after the network send; remote `accept`+`offer` posted in the gap is lost.
- **Debt:** DEBT-008.

### Target State
- `_createVoiceCallSession(...)` (or the call to it) establishes the watcher **before** `session.startOutgoing()`.
- Data flow: create session → subscribe watcher → `startOutgoing()` → invite sent → remote answer delivered into live watcher.

### Implementation Breakdown
**Task 5.1 — Locate watcher-wiring call site** (0.5h)
- Files: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Change: confirm `_watchFirebaseVoiceCall` is invoked once per outgoing call at `:165`.
- Validation: grep proves single call site.

**Task 5.2 — Reorder** (1h)
- Swap so `_watchFirebaseVoiceCall(...)` runs before `session.startOutgoing()`. Update the `:1180-1230` outgoing helper if the watcher is created there.
- Validation: `dart analyze`; read confirms order.

**Task 5.3 — Add regression test** (2h)
- File: `apps/rain/test/voice_call_runtime_outgoing_order_test.dart` (new) OR extend `voice_call_runtime_media_path_test.dart`.
- Test: fake adapter that answers within <100ms of invite; assert `VoiceCallPhase.active` reached, no `failed`/timeout.
- Validation: `flutter test` new file green.

### File-Level Changes
- MODIFY `apps/rain/lib/application/runtime/voice_call_runtime.dart` (reorder 2 calls).
- CREATE/MODIFY test file.

### Code-Level Changes
- Functions: reorder `await _watchFirebaseVoiceCall(...)` above `await session.startOutgoing()`.
- No new classes; no DI change; logging: add a `recordRuntimeEvent(name:'outgoing_watcher_subscribed_before_invite')` for diagnosability.

### Testing Plan
- Unit: order assertion in test.
- Integration: fast-answer path.
- Edge: remote answers during invite flight (the bug case).
- Regression: existing `voice_call_runtime_*` suite stays green.
- Acceptance: 0 missed-answer outgoing calls in suite.

### Validation Checklist
□ Watcher subscribed before invite (read + test) □ No regressions □ Analyze passes □ Test passes

### Rollback
Single-file revert of `voice_call_runtime.dart`; one commit.

---

## TASK-006 — Remove `failed → idle` transition

### Overview
- **Objective:** Delete the `failed => idle` edge so a failed call is strictly terminal.
- **Business value:** Prevents a "half-dead" call UI from resurrecting.
- **Technical value:** Clean terminal state for the god-object extraction (TASK-004) that follows.
- **Dependencies:** none (but do before P4 TASK-004). **Risk:** LOW.

### Current State
- `packages/protocol_brain/lib/src/voice_call_session.dart:1134`:
```dart
VoiceCallSessionPhase.failed => next == VoiceCallSessionPhase.idle,
```
- Also `:1118` (`incomingRinging => idle`) and `:1132` (`ending => idle`) — leave those (they are legitimate pre-connection resets); remove ONLY `failed => idle`.
- **Root cause:** `failed` not modeled as terminal; a future path could re-enter a media-disposed session.
- **Debt:** DEBT-005.

### Target State
- `_canTransition` returns `false` for `failed → idle`.
- New call = new `VoiceCallSession` instance.

### Implementation Breakdown
**Task 6.1 — Remove the edge** (0.5h)
- Delete line `:1134`.
- Validation: `dart analyze`.

**Task 6.2 — Add FSM unit test** (1.5h)
- File: `packages/protocol_brain/test/voice_call_session_fsm_test.dart` (extend existing `voice_call_session_test.dart`).
- Test: `expect(session.canTransition(failed, idle), isFalse);` plus existing transitions still allowed.
- Validation: `flutter test` green.

### File-Level Changes
- MODIFY `packages/protocol_brain/lib/src/voice_call_session.dart`.
- MODIFY `packages/protocol_brain/test/voice_call_session_test.dart`.

### Code-Level Changes
- Enum/transition: remove one `switch` arm. No new model.
- Error handling: callers attempting `failed→idle` now hit the default `return false` (already present for unknown pairs).

### Testing Plan
- Unit: FSM edge test.
- Regression: existing teardown tests (which construct fresh sessions) stay green.
- Acceptance: `failed` strictly terminal.

### Validation Checklist
□ Edge removed □ FSM test green □ Analyze passes

### Rollback
Revert one line.

---

## TASK-007 — Serialize mute state through media lock

### Overview
- **Objective:** Route `setMicrophoneMuted` and `handleMediaInterruption` through the same serialization so they can't diverge.
- **Business value:** Microphone stays in the intended muted/unmuted state across OS audio-focus changes.
- **Technical value:** Closes a small race the candidate-lock fix (F-008) left behind.
- **Dependencies:** none. **Risk:** LOW.

### Current State
- `packages/peer_core/lib/src/call/call_media_connection.dart`:
  - `:438-446` `setMicrophoneMuted` writes `_microphoneMuted = muted` directly.
  - `:543-565` `handleMediaInterruption` (audioFocusLost/permissionRevoked) writes `_microphoneMuted = true` directly.
- **Root cause:** two writers, no shared lock; user unmute during interruption diverges.
- **Debt:** DEBT-006.

### Target State
- Both paths mutate `_microphoneMuted` inside `_runMediaOperation(...)` (or a dedicated `_muteLock` mirroring `_candidateLock` at `:112`).
- Interruption respects an explicit user override (don't force-mute if user explicitly unmuted during the interruption window).

### Implementation Breakdown
**Task 7.1 — Wrap user toggle in lock** (1h)
- Modify `setMicrophoneMuted` to set `_microphoneMuted` inside `_runMediaOperation('set microphone muted', ...)`.
- Validation: `dart analyze`.

**Task 7.2 — Wrap interruption + add override guard** (2h)
- In `handleMediaInterruption`, read a `_userMuteOverride` flag; if user explicitly unmuted after interruption started, skip forcing `_microphoneMuted = true`.
- Validation: analyze.

**Task 7.3 — Unit test** (1.5h)
- File: `packages/peer_core/test/call_media_connection_mute_test.dart`.
- Test: start local media; user unmute; fire audioFocusLost; assert `_microphoneMuted == false` and track enabled.
- Validation: `flutter test` green.

### File-Level Changes
- MODIFY `packages/peer_core/lib/src/call/call_media_connection.dart`.
- CREATE `packages/peer_core/test/call_media_connection_mute_test.dart`.

### Code-Level Changes
- Add `bool _userMuteOverride = false;` field.
- Functions: serialize both writers; add override flag set in `setMicrophoneMuted(false)` user path.

### Testing Plan
- Unit: divergence test (the bug).
- Edge: interruption during active user unmute; double interruption.
- Regression: existing media tests green.

### Validation Checklist
□ Both writers serialized □ Override guard works □ Test green □ Analyze passes

### Rollback
Revert `call_media_connection.dart`.

---

## TASK-008 — Add `beforeOpen` schema validation + transactional migrations

### Overview
- **Objective:** Validate DB schema on open and wrap multi-statement upgrades in a transaction.
- **Business value:** Prevents silent data corruption if a migration partially applies.
- **Technical value:** Defensive DB hygiene for the SQLCipher migration (TASK-002) that follows.
- **Dependencies:** none. **Risk:** LOW.

### Current State
- `packages/rain_core/lib/database/rain_database.dart:142-160` `MigrationStrategy` has `onCreate` + `onUpgrade` (with `if (from < N)` guards) but **no `beforeOpen`** and **no transaction** wrapping.
- `schemaVersion => 6` (`:139`); additive `addColumn`/`createTable` pattern.
- **Root cause:** partial-upgrade has no recovery; no drift detection.
- **Debt:** DEBT-007.

### Target State
- `beforeOpen: (db, details) async { await db.customStatement('PRAGMA foreign_key_check;'); if (kDebugMode) await validateDatabaseSchema(db); }`
- Multi-statement `onUpgrade` steps wrapped in `await m.transaction(() async { ... });`.

### Implementation Breakdown
**Task 8.1 — Add `beforeOpen`** (1.5h)
- Modify `MigrationStrategy` at `:142`. Import `drift` `validateDatabaseSchema` if available (drift 2.33 has it).
- Validation: analyze.

**Task 8.2 — Wrap `onUpgrade` in transaction** (1.5h)
- Wrap the `if (from < N)` block body in `await m.transaction(() async { ... });`.
- Validation: analyze.

**Task 8.3 — Test migration branches** (2h)
- File: `packages/rain_core/test/rain_database_migration_test.dart`.
- Test: build DB at v5, open at v6, assert indexes exist + foreign_key_check passes; simulate by opening a fixture.
- Validation: `flutter test` green.

### File-Level Changes
- MODIFY `packages/rain_core/lib/database/rain_database.dart`.
- CREATE/MODIFY `packages/rain_core/test/rain_database_migration_test.dart`.

### Code-Level Changes
- `MigrationStrategy` gains `beforeOpen`.
- `onUpgrade` body inside `m.transaction`.
- No model/schema change (schema stays v6).

### Testing Plan
- Unit: each `from < N` branch; `foreign_key_check` green.
- Failure: simulated partial upgrade rolls back (transaction).
- Regression: existing `rain_database_test.dart` green.

### Validation Checklist
□ beforeOpen present □ onUpgrade transactional □ Migration test green □ Analyze passes

### Rollback
Revert `rain_database.dart` (no schema change → safe).

---

## TASK-016 — Enforce fresh-session reuse guard (DISCOVERED)

### Overview
- **Objective:** Reject reuse of a terminal (`failed`/`ended`) `VoiceCallSession`; require a new instance for a new call.
- **Business value:** End-to-end closure of the `failed→idle` resurrection hole.
- **Technical value:** Couples with TASK-006.
- **Dependencies:** TASK-006. **Risk:** MEDIUM (interaction inferred, not executed — confidence Medium).

### Current State
- `apps/rain/lib/application/runtime/voice_call_runtime.dart` reuses `voiceCallSession` across lifecycle; no explicit guard rejecting reuse of a terminal session.
- **Root cause (inferred):** if a caller calls `startOutgoing()` on an already-`failed` session, media is disposed → half-dead state.
- **Debt:** DEBT-011.

### Target State
- `VoiceCallRuntime` exposes `assertFreshSession(session)` (or guards at `startOutgoing`/`acceptCall` entry) that throws/ignores if `session.state.phase` is `failed`/`ended`.
- Callers construct a **new** `VoiceCallSession` for each call.

### Implementation Breakdown
**Task 16.1 — Add guard** (1.5h)
- In `voice_call_runtime.dart`, add guard at the start of outgoing/incoming start paths: `if (session.isTerminal) { recordRuntimeEvent('stale_session_reuse_blocked'); return; }`
- Validation: analyze.

**Task 16.2 — Unit/integration test** (2h)
- File: `apps/rain/test/voice_call_session_reuse_guard_test.dart`.
- Test: drive a session to `failed`; attempt new outgoing on same instance; assert blocked + no media re-init.
- Validation: `flutter test` green.

### File-Level Changes
- MODIFY `apps/rain/lib/application/runtime/voice_call_runtime.dart`.
- CREATE `apps/rain/test/voice_call_session_reuse_guard_test.dart`.

### Code-Level Changes
- Add `bool get isTerminal => phase == failed || phase == ended;` to `VoiceCallSession` (or use existing phase check).
- Guard at runtime start paths.

### Testing Plan
- Unit: reuse-blocked test (the inferred bug).
- Edge: rapid re-call after hangup.
- Regression: existing call tests green.
- **If test disproves the assumption:** convert TASK-016 to a documentation note (DEBT-011) — do NOT force a guard that breaks valid retry.

### Validation Checklist
□ Guard present □ Reuse-blocked test green (or documented as N/A) □ Analyze passes

### Rollback
Revert `voice_call_runtime.dart`.

---

## 10. Phase 1 Exit / DoD
- [ ] All 5 tasks merged on `dev`, one commit each.
- [ ] `dart run melos run analyze` green.
- [ ] `dart run melos run test` green (incl. new P1 tests).
- [ ] Integration: fast-answer outgoing call proven; no terminal resurrection.
- [ ] `CONTINUITY.md` + vault risk/debt updated; `check_obsidian_vault.ps1` green.

## 11. Phase Summary
- **Completed:** 5 reliability fixes; call FSM now strictly terminal (`failed`); outgoing watcher correctly ordered; mute race closed; DB validates on open.
- **Remaining:** God-object extraction (P4 TASK-004) still pending — P1 made it safe to do.
- **Known issues:** TASK-016 confidence Medium (inferred); if disproven, demote to doc note.
- **Metrics:** outgoing missed-answer count (target 0); `failed→idle` transitions (target 0).
- **Go/No-Go:** **GO** if DoD met. No-Go if any P1 test red.

## 12. Decisions Log (P1)
- Kept `incomingRinging => idle` and `ending => idle` (legitimate pre-connection resets); removed only `failed => idle`.
- TASK-016 implemented as a guard, with a falsifiability test — if the inferred bug doesn't reproduce, it becomes a doc note rather than a forced change.
