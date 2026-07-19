# 02 — Engineering Backlog (with Dependency Graph)

Source: `PROJECT_DEEP_ANALYSIS.md` + second-pass review (`01_EXECUTIVE_ACTION_PLAN.md`).
Every original finding re-evaluated; duplicates merged; false positives removed; interaction risks added (TASK-015/016/017).

---

## 2.1 Backlog (grouped by priority)

### Critical
> No business-ending CRITICALs exist. Highest-risk work is HIGH.

### High

#### TASK-001 — Per-pair signaling key exchange (X25519) + random salt
- **Description:** Replace app-wide shared root key with per-user identity keypair (stored in secure storage, see TASK-015) + per-friendship X25519 ECDH → per-pair root. Derive signaling/media keys via HKDF bound to both usernames + session id + random per-envelope salt. Keep envelope `v`/`alg`/`aad` format.
- **Acceptance:** `signaling_cipher_test.dart` covers per-pair key derivation; a unit test proves two different pairs produce different keys from the same root; random salt makes identical `(roomId,purpose)` produce different ciphertext across runs.
- **Effort:** L  **Priority:** HIGH  **Risk:** HIGH (crypto change; breaks compatibility with old builds → version envelopes)
- **Files:** `packages/protocol_brain/lib/adapters/signaling_cipher.dart`, `packages/rain_core/lib/identity/identity.dart`, `apps/rain/lib/core/config/app_environment.dart`, `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- **Outcome:** Real E2E signaling confidentiality, not shared-key obfuscation.
- **Depends on:** TASK-015 (secure key store + identity keypair column).
- **Confidence:** High.

#### TASK-002 — SQLCipher encryption-at-rest for Drift DB
- **Description:** Add `sqlcipher_flutter_libs`; open DB with `NativeDatabase.open(..., setup: (db) => db.execute('PRAGMA key = "...";'))`. Key derived from `flutter_secure_storage` (TASK-015). One-time migration: on first post-upgrade launch, create encrypted DB, stream-copy plaintext in, delete plaintext file.
- **Acceptance:** `rain_database_test.dart` asserts DB file is not plaintext-readable; migration copies all rows; old plaintext file deleted; `beforeOpen` validates key.
- **Effort:** M  **Priority:** HIGH  **Risk:** MED (data-migration failure path must be robust)
- **Files:** `packages/rain_core/lib/database/rain_database.dart`, `packages/rain_core/pubspec.yaml`, `packages/rain_core/lib/identity/identity.dart`
- **Outcome:** Message history / file paths / fingerprints encrypted on device.
- **Depends on:** TASK-015.
- **Confidence:** High.

#### TASK-003 — App-layer unit tests + split 9,212-line test file
- **Description:** Add per-file unit tests for `application/runtime/*_providers.dart` and `application/state/runtime_providers.dart` (1,261 lines, unmirrored). Add widget tests per screen. Split `apps/rain/test/friend_flow_test.dart` (9,212) into `friend_add_flow_test.dart`, `friend_remove_flow_test.dart`, `file_transfer_flow_test.dart`, etc.
- **Acceptance:** `apps/rain/lib` has ≥1 mirror test per provider/state file; `friend_flow_test.dart` < 1,500 lines; CI coverage floor (e.g. 40%) enforced.
- **Effort:** L  **Priority:** HIGH  **Risk:** LOW
- **Files:** `apps/rain/test/*`, `apps/rain/lib/application/**`
- **Outcome:** Regression safety net for riskiest layer.
- **Confidence:** High.

#### TASK-004 — Decompose god-object call/runtime files (<800 lines)
- **Description:** Continue Phase-3/4 extraction. Split `voice_call_runtime.dart` (3,106) → `VoiceCallLifecycleCoordinator`, `VoiceCallMediaBinding`, `VoiceCallSignalingBridge`. Split `firebase_adapter.dart` (2,912) → per-domain adapters (presence/session/lock/ice). Split `rain_runtime_controller.dart` (2,573) → command handlers. Add CI lint gate: fail any non-generated `lib/` file > 1,000 lines.
- **Acceptance:** No `lib/` file > 800 lines (excl. generated); extraction covered by focused unit tests; CI gate present.
- **Effort:** XL  **Priority:** HIGH  **Risk:** HIGH (large refactor; must keep behavior identical — characterize with golden tests first)
- **Files:** `apps/rain/lib/application/runtime/voice_call_runtime.dart`, `packages/protocol_brain/lib/adapters/firebase_adapter.dart`, `apps/rain/lib/application/runtime/rain_runtime_controller.dart`, `.github/workflows/ci.yml`
- **Outcome:** Reviewable, testable call engine.
- **Depends on:** TASK-006 (remove `failed→idle` first, so extracted lifecycle owns a clean terminal state machine).
- **Confidence:** High.

#### TASK-015 — Secure key store + identity keypair (DISCOVERED, BLOCKING)
- **Description:** Add `flutter_secure_storage` to `apps/rain/pubspec.yaml` + `rain_core`/`peer_core` as needed. Add `Identity` keypair columns (`signingPublicKey`, `signingPrivateKeyCiphertext`?) — private key wrapped by OS keystore. Provide `KeyStoreService` (Keystore/Keychain-backed) + `IdentityKeyRepository`. Publish public key via `users/$username`.
- **Acceptance:** `KeyStoreService` round-trips a secret on Android + Windows; `Identity` migration adds keypair columns; public key persisted to RTDB under auth-uid ownership.
- **Effort:** M  **Priority:** HIGH  **Risk:** MED
- **Files:** `apps/rain/pubspec.yaml`, `packages/rain_core/lib/identity/identity.dart`, `packages/rain_core/lib/database/rain_database.dart`, NEW `apps/rain/lib/infrastructure/security/key_store_service.dart`
- **Outcome:** Hardware-backed secret store; foundation for TASK-001 + TASK-002.
- **Blocks:** TASK-001, TASK-002.
- **Confidence:** High.

### Medium

#### TASK-005 — Move outgoing Firebase watcher before `startOutgoing()`
- **Description:** In `voice_call_runtime.dart:163-169`, swap order so `_watchFirebaseVoiceCall(...)` (creation inside `_createVoiceCallSession`) runs **before** `session.startOutgoing()`. Mirror incoming path (`:1290-1296`).
- **Acceptance:** Outgoing-call integration test proves a fast remote `accept`+`offer` delivered in the subscription window; no 45s ringing timeout regression.
- **Effort:** XS  **Priority:** MED  **Risk:** LOW
- **Files:** `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- **Outcome:** Eliminates missed-answer outgoing calls.
- **Confidence:** High.

#### TASK-006 — Remove `failed → idle` session transition
- **Description:** Delete `VoiceCallSessionPhase.failed => next == VoiceCallSessionPhase.idle` (`voice_call_session.dart:1134`). Make `failed` strictly terminal; callers must construct a new `VoiceCallSession` to retry.
- **Acceptance:** State-machine unit test asserts `failed→idle` rejected; existing teardown tests still green.
- **Effort:** XS  **Priority:** MED  **Risk:** LOW
- **Files:** `packages/protocol_brain/lib/src/voice_call_session.dart`, `packages/protocol_brain/test/voice_call_session_test.dart`
- **Outcome:** No half-dead session resurrection.
- **Blocks/related:** TASK-004 (clean terminal state for extraction), TASK-016.
- **Confidence:** High.

#### TASK-007 — Serialize mute state through media lock
- **Description:** Route `setMicrophoneMuted` (`:438`) and `handleMediaInterruption` (`:543`) through `_runMediaOperation` (or dedicated `_muteLock`). Interruption handler must respect explicit user override.
- **Acceptance:** Unit test: user unmute during audio-focus-lost leaves `_microphoneMuted=false` and track live.
- **Effort:** S  **Priority:** MED  **Risk:** LOW
- **Files:** `packages/peer_core/lib/src/call/call_media_connection.dart`
- **Outcome:** No mute/interrupt divergence.
- **Confidence:** High.

#### TASK-008 — Add `beforeOpen` schema validation + transactional migrations
- **Description:** In `rain_database.dart:142-160`, add `beforeOpen` that runs `PRAGMA foreign_key_check` + `validateDatabaseSchema(db)` (debug). Wrap multi-statement `onUpgrade` steps in a transaction.
- **Acceptance:** `rain_database_test.dart` exercises every `from < N` branch; simulated partial-upgrade rolls back cleanly.
- **Effort:** S  **Priority:** MED  **Risk:** LOW
- **Files:** `packages/rain_core/lib/database/rain_database.dart`
- **Outcome:** No silent DB corruption on partial upgrade.
- **Confidence:** High.

#### TASK-016 — Session-replacement discipline (DISCOVERED)
- **Description:** Audit all `VoiceCallSession` reuse sites. Enforce: after `failed`/`ending`, any new call constructs a **new** instance (never re-`startOutgoing` on a disposed one). Add a guard in `VoiceCallRuntime` rejecting reuse of a terminal session.
- **Acceptance:** Test: attempting to reuse a `failed` session throws / is ignored; new call creates fresh instance.
- **Effort:** S  **Priority:** MED  **Risk:** LOW
- **Files:** `apps/rain/lib/application/runtime/voice_call_runtime.dart`, `packages/protocol_brain/lib/src/voice_call_session.dart`
- **Outcome:** Closes the `failed→idle` resurrection hole end-to-end.
- **Related to:** TASK-006.
- **Confidence:** Medium (interaction inferred; not executed).

#### TASK-017 — RTDB rules fuzz/property contract harness (DISCOVERED)
- **Description:** Add a property-based harness that generates random legal/illegal state transitions + time-boundary probes against `database.rules.json` in the Firebase emulator; assert deny/allow matches a spec table. Add a commented `database.rules.template.json` + build step stripping comments.
- **Acceptance:** ≥200 generated transition cases pass; documented rules source compiles to deployed rules byte-for-byte.
- **Effort:** M  **Priority:** MED  **Risk:** LOW
- **Files:** `backend/firebase/database.rules.json`, NEW `backend/firebase/database.rules.template.json`, `apps/rain/test/*_rules_fuzz_test.dart`
- **Outcome:** Rules correctness no longer depends on enumerated cases.
- **Confidence:** High.

### Low

#### TASK-018 — Route `debugPrint` through sanitizer + fix stale audit doc
- **Description:** Replace the 27 `debugPrint` calls in `lib/` (e.g. `crash_diagnostics_service.dart:252,298,367`, `sound_effects_service.dart` ×8, `desktop_shell_controller.dart:84,93,100,122`) with `RainDebugLogService`. Add CI scan (grep) failing if count > 0. Correct `FLAWS_AND_FIXES_TODO.md` "0 print" claim.
- **Acceptance:** `grep -rn 'debugPrint(' apps/rain/lib` returns 0; doc corrected.
- **Effort:** S  **Priority:** LOW  **Risk:** LOW (note: `debugPrint` is a release no-op in Flutter — cosmetic/privacy-hygiene only)
- **Files:** listed above + `FLAWS_AND_FIXES_TODO.md`
- **Outcome:** Clean logs; doc integrity.
- **Confidence:** High (but downgraded from MED — not a leak).

#### TASK-019 — Add root LICENSE file
- **Description:** Choose a license (e.g. `MIT` or `Apache-2.0`) and add `LICENSE` at repo root. `README.md:364` already admits none exists.
- **Acceptance:** `LICENSE` present; CI/README link valid.
- **Effort:** XS  **Priority:** LOW  **Risk:** LOW
- **Files:** `LICENSE` (new), `README.md`
- **Outcome:** Legal distribution clarity for public repo.
- **Confidence:** High.

#### TASK-020 — Clean untracked root artifacts
- **Description:** Remove or gitignore `IDEA.md`, `deps.txt` (stray dumps) from repo root. Keep `FLAWS_AND_FIXES_TODO.md` if still wanted, else archive.
- **Acceptance:** `git status` clean of stray root files; `.gitignore` covers editor dumps.
- **Effort:** XS  **Priority:** LOW  **Risk:** LOW
- **Files:** `.gitignore`, root
- **Outcome:** Repo hygiene.
- **Confidence:** High.

#### TASK-021 — Add Windows build/config check to merge-gate CI
- **Description:** Extend `ci.yml` + `main-merge-gate.yml` with a `windows-config-check` (assert `apps/rain/windows/CMakeLists.txt`, `runner/main.cpp`, `flutter/generated_plugin_registrant.cc` exist) and a `windows-build` job on `windows-2022` running `flutter build windows --config-only` for PRs touching `apps/rain/**` or `packages/**`.
- **Acceptance:** PR deleting a Windows file fails merge-gate; Windows build sanity runs on touched PRs.
- **Effort:** S  **Priority:** LOW  **Risk:** LOW
- **Files:** `.github/workflows/ci.yml`, `.github/workflows/main-merge-gate.yml`
- **Outcome:** Windows breakage can't merge silently (closes residual F-014).
- **Confidence:** High.

---

## 2.2 Dependency Graph

```text
TASK-015 (key store + identity keypair)        [HIGH, foundation]
 ├── BLOCKS → TASK-001 (per-pair E2E signaling)
 ├── BLOCKS → TASK-002 (SQLCipher DB key)
 └── RELATED → TASK-017 (publish public key via users/$username)

TASK-006 (remove failed→idle)               [MED]
 ├── BLOCKS → TASK-004 (clean terminal for extraction)
 ├── RELATED → TASK-016 (session-replacement discipline)
 └── SHOULD COMPLETE BEFORE TASK-004

TASK-005 (watcher ordering)                 [MED, XS]  — INDEPENDENT, do first
TASK-007 (mute lock)                       [MED, S]   — INDEPENDENT
TASK-008 (beforeOpen validation)             [MED, S]   — INDEPENDENT
TASK-016 (session reuse guard)              [MED, S]   — RELATED to TASK-006
TASK-017 (rules fuzz)                      [MED, M]   — INDEPENDENT (needs emulator)
TASK-018 (debugPrint cleanup)              [LOW, S]   — INDEPENDENT
TASK-019 (LICENSE)                        [LOW, XS]  — INDEPENDENT
TASK-020 (root cleanup)                    [LOW, XS]  — INDEPENDENT
TASK-021 (windows merge-gate)              [LOW, S]   — INDEPENDENT
TASK-003 (app unit tests)                  [HIGH, L]  — INDEPENDENT (parallelizable w/ TASK-004)
TASK-004 (god-object split)                [HIGH, XL] — AFTER TASK-006
```

### Independent fixes (can parallelize immediately)
TASK-005, TASK-007, TASK-008, TASK-017, TASK-018, TASK-019, TASK-020, TASK-021, TASK-003.

### Blocking fixes (must sequence)
TASK-015 → TASK-001, TASK-002.
TASK-006 → TASK-004.

### Parallelizable work
- Sprint stability track: TASK-005/007/008/016 concurrently (all small, isolated).
- Crypto track: TASK-015 then (TASK-001 + TASK-002) in parallel once store lands.
- Test track: TASK-003 runs alongside TASK-004 extraction (tests first, then extract).

### High-risk refactors
- **TASK-004 (XL):** god-object split. Mitigate with golden/characterization tests before moving code.
- **TASK-001 (L, crypto):** breaking change to envelope key model; requires versioned envelopes + old-build interop plan.
- **TASK-002 (M, data migration):** irreversible plaintext→ciphertext migration; needs verified rollback.

---

## 2.3 Per-Issue Re-evaluation Table (status / confidence / complexity / time)

| Task | Orig | Status | Confidence | Complexity | Est. time | Knowledge |
|---|---|---|---|---|---|---|
| 001 | H-1+M-6 | OPEN | High | L | 3–4 wk | Dart crypto, HKDF, RTDB envelope contract |
| 002 | H-2 | OPEN | High | M | 1–2 wk | Drift/SQLCipher, keystore, migration |
| 003 | H-3+L-4 | OPEN | High | L | 2–3 wk | Riverpod 3, widget test, CI coverage |
| 004 | H-4 | OPEN | High | XL | 4–6 wk | call FSM, Riverpod, golden tests |
| 005 | M-1 | OPEN | High | XS | 0.5 d | call runtime ordering |
| 006 | M-2 | OPEN | High | XS | 0.25 d | session FSM |
| 007 | M-3 | OPEN | High | S | 1 d | WebRTC media op locking |
| 008 | M-4 | OPEN | High | S | 1 d | Drift migrations |
| 015 | NEW | OPEN | High | M | 1–2 wk | Keystore/Keychain, identity schema |
| 016 | NEW | OPEN | Medium | S | 1 d | session lifecycle |
| 017 | NEW (M-5) | OPEN | High | M | 1 wk | RTDB emulator, property testing |
| 018 | M-7 (downgraded) | OPEN | High | S | 1 d | logging/sanitizer |
| 019 | L-1 | OPEN | High | XS | 0.25 d | legal |
| 020 | L-2 | OPEN | High | XS | 0.25 d | gitignore |
| 021 | L-3 | OPEN | High | S | 1 d | GitHub Actions |

*Removed false-positives: M-8 (already server-enforced), M-7-as-leak (release no-op).*
