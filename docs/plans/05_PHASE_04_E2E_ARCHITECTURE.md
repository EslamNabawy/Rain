# 05 — PHASE 04: Real E2E Signaling + Architecture Extraction

**Master ref:** `01_IMPLEMENTATION_MASTER_PLAN.md` · **Backlog:** `02_ENGINEERING_BACKLOG.md` (TASK-001, TASK-003, TASK-004)
**Goal:** (a) Per-pair X25519 signaling with random-salt envelopes (TASK-001); (b) App-layer unit tests + split the 9,212-line test (TASK-003); (c) Extract call/runtime god-objects into focused coordinators (TASK-004).
**Why now:** TASK-001/002's key home exists (P3 TASK-015). TASK-006 (P1) made `failed` terminal → safe to extract.
**Estimated effort:** 4–6 weeks. **Risk:** HIGH (crypto breaking; XL refactor).
**Prerequisites:** P3 complete (TASK-015 + TASK-002 merged).
**Exit criteria:** P4 DoD (§10). **Deliverables:** per-pair E2E; no `lib/` file >800 lines; coverage floor 40%.

---

## TASK-001 — Per-Pair X25519 Signaling + Random Salt  (H-1 + M-6)

### Overview
- **Objective:** Replace the app-wide shared root key with per-user identity keypairs (TASK-015) + per-friendship X25519 ECDH → per-pair root; derive signaling keys via HKDF bound to both usernames + session id + **random per-envelope salt**. Keep envelope `v`/`alg`/`aad` format; bump to `v=2` with `v=1` fallback.
- **Business value:** Turns "obfuscation" into real end-to-end signaling confidentiality — the core privacy promise.
- **Technical value:** Removes DEBT-001 + DEBT (M-6 constant salt).
- **Dependencies:** TASK-015 (keypair + store). **Risk:** HIGH (breaking change).

### Current State
- `packages/protocol_brain/lib/adapters/signaling_cipher.dart:6-40,158-167`: `SignalingCipher.fromKeyMaterial(singleRootKey)`; `_salt` constant `"rain-signaling-v1"`; `_deriveRoomKey` uses only `(rootKey, roomId, purpose)`.
- `app_environment.dart:122-127`: `signalingEncryptionKey` is a build `dart-define` singleton.
- `Identity` (TASK-015) now has `signingPublicKey`; `IdentityKeyRepository` provides private key.

### Target State
- `SignalingCipher.forPair({required String pairKeyMaterial, ...})` factory; HKDF info includes `from`/`to`/`sessionId`; per-envelope random 16-byte salt transmitted in envelope.
- Envelope gains `v:2` + `kex` (per-pair ephemeral pubkey or pre-shared pair-key id). Decrypt tries `v=2` then falls back to `v=1` shared-root for N weeks (backward-compat with already-shipped builds).
- `envelopeVersion` becomes `2`; `SignalingCipher.demo()` still `v=1` for tests.

### Implementation Breakdown
**Task 1.1 — Versioned envelope model** (1d)
- MODIFY `signaling_cipher.dart`: add `envelopeVersion = 2`; add `kex`/`salt` fields to envelope map; keep `v=1` decrypt path.
- Validation: `dart analyze`; `signaling_cipher_test.dart` still green for `v=1`.

**Task 1.2 — Per-pair key derivation** (3d)
- Add `SignalingCipher.forPair(pairRootKey)`; HKDF info = `from=$a;to=$b;session=$id;room=$roomId;purpose=$purpose;v=2`; random salt per `encryptPayload`.
- `app_environment` provides `pairKeyResolver` (looks up `IdentityKeyRepository` + peer pubkey from `users/$peer/signingPublicKey`).
- Validation: unit test — two different pairs from same root produce **different** keys; same `(roomId,purpose)` across runs produces **different** ciphertext (random salt).

**Task 1.3 — Wire into Firebase adapter** (3d)
- MODIFY `firebase_adapter.dart`: `encryptPayload`/`decryptPayload` use `forPair` resolved per call peer; include `kex`/random salt. Keep AAD binding (`from`/`to`/`ts`).
- Validation: emulator contract test — Alice↔Bob encrypted with pair key; a third party holding only the build root **cannot** decrypt (assert decrypt throws).

**Task 1.4 — Interop + fallback window** (2d)
- Keep `v=1` shared-root path for N weeks; `README`/vault note the deprecation date.
- Validation: mixed `v=1`/`v=2` peers interoperate in emulator.

**Task 1.5 — `validateForRelease` update** (1d)
- MODIFY `app_environment.validateForRelease()`: require `pairKeyResolver` ready (keypair present) for prod; reject demo key (already done) + missing identity keypair.
- Validation: test rejects release build with no keypair.

### File-Level Changes
- MODIFY `packages/protocol_brain/lib/adapters/signaling_cipher.dart`
- MODIFY `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- MODIFY `apps/rain/lib/core/config/app_environment.dart`
- MODIFY `packages/protocol_brain/test/signaling_cipher_test.dart`

### Code-Level Changes
- Classes: `SignalingCipher` gains `forPair` + `v=2` envelope.
- Models: envelope map adds `kex`/`salt`/`v`.
- DI: `pairKeyResolver` provider (Riverpod) injected into cipher factory.
- Error handling: `SignalingEncryptionException` gains `peerKeyMissing`/`keyNotFound`.
- Logging: redact `kex` in sanitizer (already sanitizes envelopes).

### Testing Plan
- Unit: per-pair key diff; random-salt diff; `v=1` fallback decrypt.
- Integration/emulator: third-party-can't-decrypt; mixed-version interop.
- Edge: peer pubkey missing (graceful `peerKeyMissing`); key rotation.
- Regression: existing `signaling_cipher_test` + `voice_call_rtdb_rules_contract_test` green.
- Acceptance: signaling confidentiality is per-pair, not app-wide.

### Validation Checklist
□ Per-pair keys differ □ Random salt works □ `v=1` fallback □ Third-party decrypt fails □ Analyze+test green

### Rollback
Envelope version is additive; revert `signaling_cipher.dart` to `v=1` path if `v=2` interop fails. No schema change.

---

## TASK-003 — App-Layer Unit Tests + Split 9k Test  (H-3 + L-4)

### Overview
- **Objective:** Add per-file unit tests for `apps/rain/lib/application/**`; split `friend_flow_test.dart` (9,212) into per-flow files; add CI coverage floor 40% on `apps/rain/lib`.
- **Business/Technical value:** Regression net for the riskiest layer; localized failures. Removes DEBT-003.
- **Dependencies:** none (parallelizable with TASK-001). **Risk:** LOW.

### Current State
- `apps/rain/lib` = 112 source files, **0** mirror tests. `friend_flow_test.dart` = 9,212 lines (single file).
- `runtime_providers.dart` (1,261 lines) unmirrored.

### Target State
- `test/application/state/runtime_providers_test.dart`, `test/application/runtime/*_test.dart` per coordinator.
- `friend_flow_test.dart` → `friend_add_flow_test.dart`, `friend_remove_flow_test.dart`, `friend_block_flow_test.dart`, `file_transfer_flow_test.dart`, `voice_call_flow_test.dart` (each <1,500 lines).
- CI coverage gate: `flutter test --coverage`; fail if `apps/rain/lib` < 40%.

### Implementation Breakdown
**Task 3.1 — Provider unit tests** (3d)
- CREATE `apps/rain/test/application/state/runtime_providers_test.dart` using `ProviderContainer` with faked repositories.
- Validation: `flutter test` green; covers generation-scoped providers.

**Task 3.2 — Coordinator unit tests** (as TASK-004 extracts them)
- For each extracted coordinator (Lifecycle/MediaBinding/SignalingBridge/Lock), CREATE a `test/application/runtime/<name>_test.dart`.
- Validation: per-coordinator green.

**Task 3.3 — Split `friend_flow_test.dart`** (3d)
- Extract flow groups into per-flow files; keep shared helpers in `test/utils/`.
- Validation: each new file < 1,500 lines; total suite green.

**Task 3.4 — Coverage gate** (1d)
- ADD to `ci.yml`: `flutter test --coverage apps/rain`; parse `coverage/lcov.info`; fail < 40%.
- Validation: gate red when mocked-low; green on current.

### File-Level Changes
- CREATE `apps/rain/test/application/**`
- CREATE/MODIFY per-flow test files
- MODIFY `.github/workflows/ci.yml`

### Validation Checklist
□ ≥1 mirror test per provider/state file □ `friend_flow_test.dart` <1,500 □ Coverage gate active □ Analyze+test green

### Rollback
Tests only — delete added files; remove CI gate.

---

## TASK-004 — Decompose God-Object Call/Runtime Files  (H-4)

### Overview
- **Objective:** Extract `voice_call_runtime.dart` (3,106) → `VoiceCallLifecycleCoordinator` / `VoiceCallMediaBinding` / `VoiceCallSignalingBridge` / `VoiceCallLockCoordinator`; split `firebase_adapter.dart` (2,912) → per-domain adapters; split `rain_runtime_controller.dart` (2,573). Add CI line-limit gate (fail > 1,000).
- **Business/Technical value:** Reviewable, testable call engine. Removes DEBT-004.
- **Dependencies:** TASK-006 (P1, `failed` terminal) done. **Risk:** HIGH (XL refactor — golden-test first).

### Current State
- `voice_call_runtime.dart` = 3,106 lines (GREW 3,084→3,106 since audit despite prior extraction).
- `firebase_adapter.dart` = 2,912; `rain_runtime_controller.dart` = 2,573.
- Prior extractions exist: `VoiceCallMediaCoordinator`, `VoiceCallSessionStateCoordinator`, `VoiceCallSignalingCleanupCoordinator`, `VoiceCallPreflightCoordinator`, `VoiceCallReconnectCoordinator`, `VoiceCallRoomCoordinator`, `VoiceCallTerminalReconciler` (under `apps/rain/lib/application/runtime/voice_call/`).

### Target State
- `voice_call_runtime.dart` (orchestrator) < 400 lines, delegating to:
  - `VoiceCallLifecycleCoordinator` (FSM: preflight→ringing→connecting→active→ending→failed)
  - `VoiceCallMediaBinding` (media session create/dispose → owns `VoiceCallMediaCoordinator`)
  - `VoiceCallSignalingBridge` (Firebase watch/offer/answer/ICE + cleanup)
  - `VoiceCallLockCoordinator` (activeVoicePairs/Users claim/reclaim)
- `firebase_adapter.dart` → `presence_adapter.dart`, `session_adapter.dart`, `voice_lock_adapter.dart`, `ice_adapter.dart`.
- CI gate: fail any non-generated `lib/` file > 1,000 lines.

### Implementation Breakdown
**Task 4.1 — Characterization/golden tests (BEFORE moving code)** (3d)
- CREATE `apps/rain/test/voice_call_runtime_golden_test.dart` capturing current behavior (FSM transitions, teardown order, lock claim/reclaim).
- Validation: golden green on current code (pinned).

**Task 4.2 — Extract `VoiceCallMediaBinding`** (4d)
- MOVE media create/dispose from `voice_call_runtime.dart` into `voice_call_media_binding.dart`; delegates to existing `VoiceCallMediaCoordinator`.
- Validation: golden + `voice_call_runtime_media_path_test` green.

**Task 4.3 — Extract `VoiceCallLockCoordinator`** (3d)
- MOVE lock logic (uses existing `voice_lock_reclaim_policy.dart`) into `voice_call_lock_coordinator.dart`.
- Validation: lock contract tests green.

**Task 4.4 — Extract `VoiceCallSignalingBridge`** (4d)
- MOVE `_watchFirebaseVoiceCall` + send paths into `voice_call_signaling_bridge.dart`.
- Validation: signaling contract + emulator tests green.

**Task 4.5 — Extract `VoiceCallLifecycleCoordinator`** (4d)
- MOVE FSM orchestration (post TASK-006 terminal `failed`) into `voice_call_lifecycle_coordinator.dart`.
- Validation: FSM + golden green.

**Task 4.6 — Split `firebase_adapter.dart`** (4d)
- Split into `presence_/session_/voice_lock_/ice_adapter.dart` under `packages/protocol_brain/lib/adapters/`.
- Validation: adapter tests green.

**Task 4.7 — Split `rain_runtime_controller.dart`** (3d)
- Extract command handlers into `runtime_command_handlers.dart`.
- Validation: runtime tests green.

**Task 4.8 — CI line-limit gate** (1d)
- ADD to `ci.yml`: script failing any non-generated `lib/` `.dart` file > 1,000 lines.
- Validation: gate red on a temp 1,200-line file.

### File-Level Changes
- CREATE `apps/rain/lib/application/runtime/voice_call/voice_call_media_binding.dart`, `voice_call_lock_coordinator.dart`, `voice_call_signaling_bridge.dart`, `voice_call_lifecycle_coordinator.dart`
- CREATE `packages/protocol_brain/lib/adapters/{presence,session,voice_lock,ice}_adapter.dart`
- CREATE `apps/rain/lib/application/runtime/runtime_command_handlers.dart`
- MODIFY `voice_call_runtime.dart`, `firebase_adapter.dart`, `rain_runtime_controller.dart` (delegators)
- MODIFY `.github/workflows/ci.yml`

### Code-Level Changes
- Classes: 4 new coordinators + 4 adapters + command handlers.
- Interfaces: narrow coordinator interfaces (mirror existing coordinator pattern).
- DI: Riverpod providers wire coordinators (R-5 in `03_ARCHITECTURE_REFACTOR_PLAN.md`).
- Feature-flag: each extraction behind `VoiceCallArchV2` flag; keep old path until new green 1 week.

### Testing Plan
- Characterization: golden test (4.1) gates every extraction.
- Unit: per-coordinator.
- Integration: existing `voice_call_*` suite.
- Edge: terminal `failed` no-resurrection (TASK-006/016); lock reclaim under concurrency.
- Regression: full `melos run test` green.
- Acceptance: no `lib/` file > 800 lines; CI line gate active.

### Validation Checklist
□ Golden green pre/post each extraction □ No lib/ file >800 □ Line gate active □ Analyze+test green

### Rollback
Feature-flag per coordinator → revert flips flag, old path restored. Each extraction is a new file → clean git revert.

---

## 10. Phase 4 Exit / DoD
- [ ] TASK-001: `signaling_cipher_test` proves per-pair keys differ + random salt; third-party decrypt fails; `v=1` fallback works.
- [ ] TASK-003: ≥1 mirror test per provider/state file; `friend_flow_test.dart` <1,500; coverage gate 40%.
- [ ] TASK-004: no `lib/` file >800 lines; line-limit CI gate active; golden tests green throughout.
- [ ] `dart run melos run analyze` + `test` green.
- [ ] CONTINUITY + vault (architecture note, ADR-010 Option B done) updated; `check_obsidian_vault.ps1` green.

## 11. Phase Summary
- **Completed:** Real per-pair E2E; app-layer test net; call engine decomposed.
- **Remaining:** P5 polish (fuzz finish, a11y, CODEOWNERS, docs).
- **Known issues:** TASK-001 is breaking — mitigated by versioned envelopes + fallback window. TASK-004 long pole — golden tests first.
- **Metrics:** `lib/` max file lines (target <800); coverage % (target ≥40); per-pair key isolation (test-proven).
- **Go/No-Go:** **GO** if DoD met. **No-Go** if golden tests red after any extraction or `v=2` interop fails.

## 12. Decisions Log (P4)
- Envelope `v=2` additive with `v=1` fallback window (N weeks, documented) — protects already-shipped builds.
- TASK-003 runs **concurrently** with TASK-001 (tests additive) to shorten the long pole.
- TASK-004 extractions feature-flagged individually — no big-bang refactor.
