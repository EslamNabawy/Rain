# Rain — Flaws & Fixes TODO

> Living document. Discoveries are appended **as found**, not at the end.
> Each item: ID, severity, evidence, root cause, fix.
> Severities: 🔴 CRITICAL (breaks build/runtime/security) · 🟠 HIGH · 🟡 MEDIUM · 🟢 LOW

---

## Executive Summary

Audit scope: repo structure, CI, Firebase rules + functions, call/signaling runtime, crypto/identity, state management, storage, diagnostics, dependencies.

**18 flaws found** across 4 severity tiers. The codebase is **stronger than typical** for a solo/small Flutter project (strict DB rules, encrypted signaling envelopes, a real diagnostics sanitizer, current deps, clean async hygiene, mature release gates) — but it has three genuine structural weaknesses:

1. **Correctness of the call engine is fragile** (F-006 → F-013): un-synchronized terminal-state teardown, non-atomic Firebase stream writes, lock-bypassing ICE, and video-resource leaks. These directly match the last 3 "stuck state" bug-fix commits.
2. **Security claims outrun the key model** (F-015, F-016, F-017): "E2E" signaling uses one app-wide shared key with no per-pair key exchange; the local message DB is unencrypted at rest.
3. **A Windows build was silently broken** (F-001) because CI never validates the Windows target (F-014).

### Priority order (do first)

| # | Flaw | Tier | Effort | Why first | Status (2026-06-18) |
|---|---|---|---|---|---|
| 1 | **F-001** Restore deleted `apps/rain/windows/` | 🔴 | XS | One command; Windows build is currently dead | ✅ STALE — `apps/rain/windows/` fully tracked (18 files) + on disk as of `dev@4798605`. No fix needed. |
| 2 | **F-006** Teardown mutual-exclusion + `ended`/`failed` race | 🔴 | M | Root of the recurring "stuck call" bugs | ✅ FIXED — `_failVoiceCall` now early-returns when phase is `ended`/`failed`. |
| 3 | **F-007** Serialize `voiceCallState` writes (drop-fix) | 🔴 | M | Silent state-loss in the call path | ✅ STALE — already solved by `SerializedRuntimeMutations` (wired + tested in `serialized_runtime_mutations_test.dart`). |
| 4 | **F-014** Add Windows CI gate (so F-001 can't recur) | 🟠 | S | Prevents regression of F-001 | ✅ STALE — F-001 premise (missing Windows dir) no longer true. Re-open only if Windows dir goes missing again. |
| 5 | **F-008** Route `addRemoteCandidate` through media-op lock | 🟠 | XS | Prevents mid-negotiation SDP corruption | ✅ FIXED — added `_candidateLock`; candidate chains behind in-flight negotiation, never dropped. |
| 6 | **F-009** Dispose video resources on session-construction error | 🟠 | S | Fixes native renderer leak | ✅ FIXED — null-session branch in `disposeCurrentVoiceCallSession` now disposes video resources. |
| 7 | **F-017** SQLCipher encryption-at-rest for Drift DB | 🟠 | M | Privacy promise vs. cleartext storage | ⬜ OPEN |
| 8 | **F-015** Per-pair key exchange (X25519) for signaling | 🟠 | L | Turns "obfuscation" into real E2E | ⬜ OPEN |
| 9 | **F-003** Unit-test the app layer (`apps/rain/lib`) | 🟠 | L | Regression safety net | ⬜ OPEN |
| 10 | **F-002** Decompose god-object files | 🟠 | L | Maintainability of the call engine | ⬜ OPEN (note: `voice_call_runtime.dart` still 3,084 lines post-Phase-3/4) |

Remaining: F-004, F-005, F-010, F-011, F-012, F-013, F-016, F-018 — see details below.

### What is *not* broken (do not "fix" these)
- Firebase RTDB rules: strict, deny-by-default, encrypted signaling envelopes, 65 auth.uid ownership checks.
- Diagnostics sanitizer: robust PII redaction.
- Dependency hygiene: all current; demo key blocked in prod; no hardcoded secrets.
- Async hygiene: no `.then()` fire-and-forget, `unawaited()` used 110×, no empty catches.

---



## 🔴 F-001 — `apps/rain/windows/` platform directory is deleted in the working tree

**Evidence**
- `git status` shows 18 files under `apps/rain/windows/` as deleted (` D`), including:
  `CMakeLists.txt`, `runner/main.cpp`, `flutter_window.cpp`, `win32_window.cpp`,
  `generated_plugin_registrant.cc`, `runner.exe.manifest`, `app_icon.ico`, etc.
- On disk, only `apps/rain/windows/runner/Runner.rc` remains; the rest are gone.
- `apps/rain/pubspec.yaml` depends on `window_manager: ^0.5.1` (Windows-only desktop support).
- `AGENTS.md` states Rain targets **Android and Windows**.

**Impact**
- Windows desktop build is currently **non-functional**.
- `flutter build windows` will fail (no CMake entry, no runner main, no plugin registrant).
- Any contributor cloning + checking out this working tree cannot produce a Windows binary.

**Root cause**
- Accidental deletion (likely a stray `git clean` / `rm -rf` / IDE action) that was never committed.
- No CI gate verifying Windows platform files exist.

**Fix**
1. Restore deleted files: `git checkout HEAD -- apps/rain/windows` (or `git restore apps/rain/windows`).
2. Verify: `git status --short apps/rain/windows` shows clean; files present on disk.
3. Confirm `windows/` is in `.gitignore` exceptions if needed (it is tracked, so no ignore needed).
4. Add a CI check that asserts the platform dirs (`android/`, `windows/`) exist and are non-empty.
5. Run a build sanity check (`flutter build windows --config-only` or full build) before merging.

---

## 🟠 F-002 — God-object files: runtime + adapters exceed healthy size limits

**Evidence** (largest non-generated files)
| File | Lines |
|---|---|
| `apps/rain/test/friend_flow_test.dart` | 9,212 |
| `apps/rain/lib/application/runtime/voice_call_runtime.dart` | 3,084 |
| `packages/protocol_brain/lib/adapters/firebase_adapter.dart` | 2,912 |
| `apps/rain/test/rain_chat_widgets_test.dart` | 2,874 |
| `apps/rain/lib/application/runtime/rain_runtime_controller.dart` | 2,573 |
| `packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart` | 2,328 |
| `apps/rain/lib/presentation/widgets/home/chat_panel.dart` | 1,914 |
| `apps/rain/lib/presentation/screens/settings_screen.dart` | 1,909 |
| `apps/rain/lib/application/runtime/voice_call/voice_call_signaling_cleanup_coordinator.dart` | 1,843 |

**Impact**
- High-risk call/signaling state is concentrated in single classes → hard to reason about correctness, race conditions, and cleanup paths (the exact area the last 3 commits were fixing).
- Violates single-responsibility; suppresses testability.
- Reviewers cannot safely verify call-establishment/teardown logic at this size.

**Root cause**
- Organic growth; Phase 2a/3c/4 extractions (per CONTINUITY.md) only partially decomposed `voice_call_runtime.dart` (4,751→4,689 lines — net only −62).

**Fix** (incremental, risk-ordered)
1. Continue the extraction program already started in Phase 3c/4:
   - Split `voice_call_runtime.dart` into: `VoiceCallLifecycleCoordinator`, `VoiceCallMediaBinding`, `VoiceCallSignalingBridge`.
   - Split `firebase_adapter.dart` into per-domain adapters (presence, session, lock, ice).
2. Target: no `lib/` file > 800 lines (exclude generated).
3. Move the 9,212-line `friend_flow_test.dart` into per-flow files (`friend_add_flow_test.dart`, `friend_remove_flow_test.dart`, …).
4. Add a CI lint gate: fail if any non-generated `lib/` file exceeds 1,000 lines.

---

## 🟠 F-003 — App-layer (`apps/rain/lib`) has effectively zero mirror-test coverage

**Evidence**
- `apps/rain/lib/application` — 51 source files, **0** mirrored test files.
- `apps/rain/lib/presentation` — 40 source files, **0** mirrored test files.
- `apps/rain/lib/infrastructure` — 16 source files, **0** mirrored test files.
- The 100 test files live in `apps/rain/test/` but are large integration-style suites (`friend_flow_test.dart`, `runtime_startup_test.dart`), not per-unit mirrors.
- CONTINUITY.md claims "1,117+ tests pass" — true, but they are coarse-grained, not unit isolation tests.

**Impact**
- Regressions in app-layer Riverpod providers, runtime wiring, and presentation logic are caught only by heavy integration suites.
- Slow feedback loop; flaky tests; hard to localize a failing behavior.

**Fix**
1. Introduce per-file unit tests for `application/runtime/*_providers.dart` and `application/state/runtime_providers.dart` (1,261 lines, currently unmirrored).
2. Add widget tests per screen under `presentation/screens/` (settings_screen 1,909 lines, home_screen 1,782 lines — both unmirrored).
3. Set coverage floor in CI (`dart test --coverage`) for `apps/rain/lib` and fail on regression below the floor.

---

## ✅ NOT A FLAW — baseline hygiene is clean (recorded for balance)
- No hardcoded secrets/keys/tokens in `lib/` of any package.
- No raw `print`/`debugPrint` left in production code: the 21 `debugPrint` calls
  that existed in `apps/rain/lib` were routed through `RainDebugLog` (sanitized
  sink) on 2026-07-19 (TASK-018). `crash_diagnostics_service.dart` is the
  intentional exception (lowest sanitizing layer). CI fails on new raw
  `debugPrint(` in `lib/`.
- No `TODO`/`FIXME`/`HACK`/`XXX` markers in `lib/` (clean).
- No `.then()` fire-and-forget chains; `unawaited()` used 110× (good practice).
- No empty `catch` blocks detected.

---

## 🟡 F-004 — Connection-request quotas are client-enforced (`bestEffort`), not server-authoritative

**Evidence**
- `database.rules.json:687` — `connectionRequestUsage`: `serverAuthority: 'bestEffort'`, `securityLevel: 'sparkRules'`, and the client itself writes `used` (0–1000). Same for `connectionRequestTargetUsage` (line 704).
- `connectionRequestQuotaSummaries` and aggregate counters are `.write: false` from client (good), but the per-day `used` counter is incremented by the **client**.
- No Cloud Function recomputes/authoritates usage. Functions (`connectionRequests.js`) only do create/cancel/accept/reject/seen/mute.
- This is consistent with AGENTS.md's "free-tier constraint" — Cloud Functions invocations are billable — but it is a real weakness.

**Impact**
- A modified client can under-report `used`, bypassing daily request limits → spam/abuse vector.
- Quota is advisory, not enforcing.

**Root cause**
- Spark/free-tier constraint forbids adding a server authority for every request (Function invocations cost money).
- Conscious trade-off documented implicitly via `securityLevel: 'sparkRules'`.

**Fix** (low-cost, free-tier-safe)
1. Add a single scheduled Cloud Function (reusing the existing `cleanupConnectionRequests` cadence) that reconciles `connectionRequestUsage` against the actual `connectionRequests`/history records for the day and corrects drift. One run per day per user is cheap.
2. Alternatively, move quota increment into the existing `createConnectionRequest` callable (already a Function call — marginal added cost) so the server writes `used` with a transaction.
3. Document this as an accepted risk in `obsidian-vault/12-Risks/Risk Register.md` if not fixed.

---

## 🟡 F-005 — Firebase RTDB rules are extremely dense/complex (maintainability + correctness risk)

**Evidence**
- `database.rules.json` is 776 lines; single rule expressions span 2,000+ chars (e.g. `rooms.$roomId.write`, `connectionRequests.$to.$requestId.write`, `connectionRequestPairLocks.$pairKey.write`).
- Rules mix state-machine transitions (`pending→seen→accepted/rejected/canceled/expired/failed`), time bounds (`now`, `expiresAt`), pair-key derivation, friendship-existence checks, and block-list checks into one boolean expression.

**Impact**
- Very hard to audit for correctness → a subtle logic bug could allow an unauthorized transition or deny a legitimate one.
- Hard to extend without introducing regressions.
- The contract tests (`voice_call_rtdb_rules_contract_test.dart`, `connection_request_rtdb_rules_contract_test.dart`) mitigate this, but only as well as the cases enumerated.

**Root cause**
- RTDB rules language limitations; complex authorization logic forced into declarative expressions.

**Fix**
1. Keep the contract tests as the safety net and **expand** them with property/fuzz-style cases for every state transition and time boundary.
2. Add a generated/sectioned rules source (e.g. `database.rules.template.json` with comments) and a build step that strips comments, so logic is documented near the rules.
3. Track in Technical Debt Register with explicit acceptance criteria for "rules are fully covered by contract tests."

---

## ✅ NOT A FLAW — Firebase security posture is strong (recorded for balance)
- 65 `auth.uid` ownership checks across rules; deny-by-default top-level (`.read/.write: false`).
- Every collection enforces `$other: { ".validate": false }` → no extra fields.
- Signaling payloads (`offer`/`answer`/`callerICE`/`calleeICE`) are **end-to-end encrypted** (`A256GCM-HKDF-SHA256`, v1, bound `from`/`to`, nonce/ciphertext/mac length-validated).
- `connectionRequestPairLocks` enforce mutual-exclusion with server time bounds.
- `node_modules/` is correctly gitignored (0 tracked, 2835 on disk).
- Callable Functions (`connectionRequests.js`) consistently wrap logic in `try/catch` and use `HttpsError`.
- No `process.env`/`functions.config()` secret leakage in function source.

---

## 🔴 F-006 — Call teardown lacks mutual exclusion; `ended` ↔ `failed` can race into stuck/double-dispose

**Evidence**
- `voice_call_runtime.dart:2309-2326` — `endVoiceCallForPeer` guards with `endingCallPeerId`, BUT `:2753-2775` `_failVoiceCall` writes `phase: failed` **unconditionally** (no guard, no check that phase is already terminal) then disposes the session.
- `:2353-2416` — `_endVoiceCallForPeerImpl` emits `ended` to the UI **before** `session.hangUp()` completes (a multi-retry `await` at `:2373`).
- Subagent audit confirms this is the direct cause of the "stuck state" symptoms targeted by the last 3 commits.

**Impact**
- User hangs up a connected call → a racing signaling error flips UI to `failed`.
- Both paths dispose the same session → double-dispose / use-after-dispose on media.
- `ended` then `failed` (or reverse) churn is visible to the UI.

**Fix**
1. Route all teardown through one lock; `_failVoiceCall` must early-return if `phase` is already `ended` or `failed`.
2. Emit `ended` only **after** `session.hangUp()` completes (or make `_applyVoiceSessionState` the single source of terminal-phase truth).
3. Key the re-entrancy guard on `callId@sessionEpoch`, not peer id; chain concurrent callers onto the in-flight end Future.

---

## 🔴 F-007 — Non-atomic read-modify-write on `voiceCallState` from un-awaited Firebase stream listeners → silently dropped state updates

**Evidence**
- `voice_call_signaling_cleanup_coordinator.dart:198` — `watchCall(...).listen((room) async { ... await handleFirebaseVoiceRoomUpdate(...); })`.
- `Stream.listen` with an `async` callback does **not** await the Future before delivering the next event.
- `:369-387` — handler does `currentState().copyWith(...)` → `setVoiceCallState(...)` for `isRemoteMuted` and `isRemoteCameraMuted` independently. Two concurrent room/offer/ICE listeners for the same session clobber each other.

**Impact**
- Mute/camera/video-state updates silently lost.
- This is exactly the "state updates dropped during session transition" class.

**Fix**
- Serialize all runtime-state writes through a single per-call event queue (mirror `VoiceCallSession._enqueue`), so handlers apply mutations strictly in turn.

---

## 🟠 F-008 — `addRemoteCandidate` bypasses the media-operation lock and can corrupt mid-negotiation SDP

**Evidence**
- `call_media_connection.dart:360` — `acceptOffer`/`applyAnswer` run via `_runMediaOperation(...)`.
- `:393-415` — `addRemoteCandidate` does **not**; it calls `connection.addCandidate()` directly while a parallel `acceptOffer` may be between `setRemoteDescription` and `createAnswer`.

**Impact**
- Trickle-ICE candidate arriving mid-negotiation can throw inside negotiation → call fails or SDP corrupts.

**Fix**
- Route the direct-add branch of `addRemoteCandidate` (`:411-414`) through `_runMediaOperation`, or queue candidates onto the same serial slot.

---

## 🟠 F-009 — Video resources (`videoCallMediaConnection`/renderers) leak on session-construction error path

**Evidence**
- `voice_call_runtime.dart:1200-1284` — `_createVoiceCallSession` disposes old session first (→ `voiceCallSession = null`), then allocates video media/renderers, then assigns `voiceCallSession = session`.
- `voice_call_signaling_cleanup_coordinator.dart:1576-1587` — `disposeCurrentVoiceCallSession` null-session branch cancels the subscription and **returns** without disposing video.
- `:1627` — `disposeVoiceCallSession` only touches video when `currentSession == session`.

**Impact**
- If anything between video-media creation and session assignment throws → `_failVoiceCall` → null-session cleanup → native video renderers + renderer subscription leak.

**Fix**
- In the null-session branch, also call `disposeVideoCallResources()`; OR have `_createVoiceCallSession` dispose its freshly-allocated video media in its own try/catch before propagating.

---

## 🟡 F-010 — Outgoing call subscribes to Firebase watchers AFTER sending the invite → fast remote answer missed, call stalls to ringing timeout

**Evidence**
- `voice_call_runtime.dart:164-169` — outgoing path: `await session.startOutgoing()` (sends invite) **then** `await _watchFirebaseVoiceCall(...)`.
- `:1290-1296` — incoming path correctly subscribes watchers **before** handling the invite. (Asymmetry confirms the outgoing ordering is a bug.)

**Impact**
- Remote `accept`+`offer` posted in the subscription gap is never delivered → call sits in `outgoingRinging` until the 45s ringing timeout fires and fails it.

**Fix**
- Move outgoing `_watchFirebaseVoiceCall` into `_createVoiceCallSession` (before `startOutgoing()`), mirroring the incoming ordering.

---

## 🟡 F-011 — `_runMediaNegotiation` drops (does not queue) a second offer/answer when one is in flight

**Evidence**
- `voice_call_session.dart:1003-1014` — `if (_negotiatingMedia) { _logInvalidEvent(...); return; }` — the second negotiation is silently dropped.

**Impact**
- ICE-restart `_createAndSendOffer` scheduled by `_handleMediaState` can overlap a queued remote offer/answer; the dropped SDP leaves the exchange incomplete → call hangs in `connectingMedia` until media timeout.

**Fix**
- Queue (re-arm) the second negotiation via a "pending restart" flag consumed in the `finally` block instead of dropping it.

---

## 🟡 F-012 — `setMicrophoneMuted` and `handleMediaInterruption` race on `_microphoneMuted`/track state

**Evidence**
- `call_media_connection.dart:418-426` (user toggle) and `:530-545` (audio-focus-lost / permission-revoked interruption) both write `_microphoneMuted` and call `setMicrophoneMuted()` with no serialization.

**Impact**
- User unmutes during an interruption → values diverge; `_microphoneMuted=true` persists while track is live; next `_startLocalMedia` re-applies mute incorrectly.

**Fix**
- Route both through `_runMediaOperation` (or a dedicated mute lock); interruption handler should respect an explicit user override.

---

## 🟡 F-013 — `failed → idle` is an allowed session transition, weakening terminality of `failed`

**Evidence**
- `voice_call_session.dart:1134` — `VoiceCallSessionPhase.failed => next == VoiceCallSessionPhase.idle`.

**Impact**
- `failed` is not strictly terminal; a future code path could resurrect a session whose media is already disposed (`_fail` disposes media at `:983`) → half-dead state.

**Fix**
- Remove the `failed → idle` edge; make `failed` strictly terminal and rely on session **replacement** (new `VoiceCallSession` instance) rather than resurrection.

---

## ✅ NOT A FLAW — call runtime areas that ARE well-handled (recorded for balance)
- `VoiceCallSession._enqueue` (`:1195`) serializes all public ops; `_stateController` is `broadcast(sync: true)` (`:141`) keeping emits atomic.
- Timer cleanup is correct: `_clearTimers` called from `_fail`, `_clearVoiceOnly`, `dispose`, and on each re-arm. No timer leaks.
- All three media subscriptions cancelled in `dispose` (`:350-352`); peer-connection callbacks nulled in `_closePeerConnection` (`:1014-1017`).
- The only `Completer` (`_runMediaOperation :852`) completes exactly once in `finally` — no double/never-completion.
- `cancelVoiceSignalingSubscriptions` copies-then-clears the list before iterating (`:1373-1377`) — correct cancellation pattern.

---

## 🟠 F-014 — CI never builds or verifies the Windows target; F-001 went undetected

**Evidence**
- All CI jobs run on `ubuntu-latest` (`.github/workflows/ci.yml:34,50,69,157,193...`).
- The only `flutter build` in CI is `flutter build apk --debug` (`ci.yml:358`) — Android only.
- No CI step runs `flutter build windows` or even `flutter build windows --config-only`.
- No job asserts platform directories (`apps/rain/windows/`, `apps/rain/android/`) exist and are non-empty.
- This is why **F-001** (deletion of all 18 `windows/` files) was not caught before reaching the working tree.

**Impact**
- Windows breakages (missing files, plugin-registrant drift, CMake errors) merge silently.
- AGENTS.md mandates Android + Windows support, but only Android is gated.

**Fix**
1. Add a `windows-config-check` CI job (can stay on `ubuntu-latest`): assert `apps/rain/windows/CMakeLists.txt`, `runner/main.cpp`, `flutter/generated_plugin_registrant.cc` exist; fail if any tracked platform file is missing in the PR diff.
2. Add a `windows-build` job on `windows-latest` that runs at least `flutter build windows --config-only` on PRs touching `apps/rain/**` or `packages/**`.
3. Mirror the Android release-gate that already exists for Windows.

---

## 🟠 F-015 — Signaling "E2E" cipher uses a single app-wide shared key, not a per-pair key exchange → no true end-to-end secrecy

**Evidence**
- `signaling_cipher.dart:6-7` — `SignalingCipher.fromKeyMaterial(String keyMaterial)` takes one root key.
- `app_environment.dart:241-244` — the key comes from `RAIN_SIGNALING_ENCRYPTION_KEY` (a dart-define), i.e. **one value baked into the build**.
- `runtime_providers.dart:543` and `app_bootstrap.dart:67` — both production paths pass `environment.signalingEncryptionKey` (the single shared value).
- No X25519/ECDH key exchange, no per-friendship shared secret, no per-user keypair exists in `rain_core/lib/identity/identity.dart` (it only stores username/displayName/gender — no key material).
- HKDF derives per-room keys from the **same** root + a **static** salt (`signaling_cipher.dart:22-40`).

**Impact**
- This is **transport-level obfuscation, not end-to-end encryption**:
  - Anyone holding the build's key (or the Firebase project owner/server) can decrypt all signaling (SDP offers/answers/ICE) for every pair.
  - All users of the same build share one key → a user can decrypt another pair's signaling if they capture it.
  - Compromise of the build key = compromise of all historical signaling.
- The DB rules (`offer`/`answer`/`callerICE` enforce `alg === 'A256GCM-HKDF-SHA256'`) give the *appearance* of E2E, but the key model breaks the E2E promise.
- AGENTS.md lists "Private accepted-friend chat" and security as a top-3 priority.

**Mitigating controls already present** (recorded for balance)
- `app_environment.validateForRelease()` (`:422-431`) correctly **rejects** production builds that use the demo key and requires `RAIN_SIGNALING_ENCRYPTION_KEY` — so prod builds don't ship the public demo key. Good.
- This prevents the trivial "demo key in prod" mistake but does NOT change the single-shared-key architecture.

**Fix** (architectural)
1. Generate a long-term identity keypair per user (store private key in `flutter_secure_storage` / Keystore / Keychain; publish public key via `users/$username`).
2. On friendship establishment, perform an X25519 ECDH to derive a per-pair root key; store it and rotate on key-loss.
3. Derive signaling/media keys per-pair (HKDF info bound to both usernames + a session id).
4. Keep the current AAD-binding and envelope format — only the root-key provisioning changes.
5. Until done, document this honestly in the vault as "signaling confidentiality = app-wide key, not per-pair E2E."

---

## 🟡 F-016 — HKDF salt is a hardcoded constant (same for every derivation)

**Evidence**
- `signaling_cipher.dart:22-40` — `_salt = [114,97,105,110,...]` decodes to ASCII `"rain-signaling-v1"` and is used verbatim for **every** `_hkdf.deriveKey` call (`:164`).

**Impact**
- A salt's purpose is domain separation + per-derivation randomness. A constant salt reduces to a fixed info string; HKDF output is then fully determined by (rootKey, roomId, purpose) — deterministic across runs.
- Combined with F-015 (shared root), this makes key derivation predictable and reproducible by any attacker who knows the build.

**Fix**
- Mix per-call randomness into the salt (e.g., random 16-byte salt per envelope, transmitted alongside) OR fold a per-session nonce into `info`. At minimum, document that the constant salt is intentional domain-separation only and acceptable IF root keys become per-pair.

---

## 🟠 F-017 — Local Drift database stores messages/file paths/connection fingerprints with NO encryption-at-rest

**Evidence**
- `rain_database.dart:302-318` — `_openRainDatabase()` uses plain `driftDatabase(...)` with `PRAGMA journal_mode = WAL` etc., but **no SQLCipher / no `setKey`**.
- Tables stored in cleartext: `Messages.content`, `QueuedMessages.content`, `FileTransfers.localPath`/`tempPath`/`fileName`, `ConnectionMemoryTable.cachedIce` + `fingerprint`, `Friends.*`, `IdentityTable.*`.

**Impact**
- On a rooted Android device, a stolen/unlocked phone, or a shared Windows machine, the `rain.sqlite` (and its `-wal`/`-shm`) file is directly readable → full message history, file paths, and connection fingerprints exposed.
- AGENTS.md prioritizes privacy ("Private accepted-friend chat") and lists security as priority #3.

**Fix**
1. Adopt `drift` + SQLCipher (`sqlcipher_flutter_libs`): open the DB with `NativeDatabase.open(..., setup: (db) => db.execute('PRAGMA key = "...";'))`.
2. Derive the DB key from a value in `flutter_secure_storage` (Keystore/Keychain-backed, hardware-backed where available).
3. Add a migration path: on first launch after upgrade, create a new encrypted DB and stream-copy the existing plaintext DB into it, then delete the plaintext file.
4. Track as a security debt item if not done immediately.

---

## 🟡 F-018 — Drift `MigrationStrategy` lacks `beforeOpen` validation and a recovery/rollback path on schema drift

**Evidence**
- `rain_database.dart:142-160` — `migration` defines `onCreate` + `onUpgrade` (with versioned `if (from < N)` guards — good), but no `beforeOpen`.
- No `validateDatabaseSchema()` call, no fallback if a migration step partially fails (a failed `createTable(fileTransfers)` mid-upgrade leaves the DB between schema v5 and v6 with no recovery).

**Impact**
- A partially-applied migration leaves the DB in an inconsistent state; subsequent reads may throw or silently return wrong data.
- No detection of schema drift (e.g., if a previous migration was bypassed).

**Fix**
1. Add `beforeOpen: (db, details) async { await db.customStatement('PRAGMA foreign_key_check;'); if (kDebugMode) await validateDatabaseSchema(db); }`.
2. Wrap multi-statement migration steps in a single transaction so partial failure rolls back cleanly.
3. Add a one-time schema-integrity test in `rain_core` that exercises every `from < N` branch against a fixture DB.

---

## ✅ NOT A FLAW — diagnostics, dependencies, and sanitizer are solid (recorded for balance)
- `DiagnosticsSanitizer` (366 lines) redacts email, bearer tokens, secret assignments (quoted/unquoted/standalone), file paths (Windows + Android), Firebase user paths, and SDP/ICE markers. Crash records run every string through it.
- Dependencies are current: `firebase_auth 6.5.1`, `firebase_core 4.9.0`, `firebase_database 12.4.1`, `flutter_riverpod 3.3.1`, `drift 2.33.0`, `go_router 17.2.3`, `freezed 3.2.5`, `flutter_webrtc 1.4.1`; Functions `firebase-admin ^13.10.0`, `firebase-functions ^7.2.5`, Node 20. No pinned-ancient or known-vulnerable majors spotted.
- `app_environment.validateForRelease()` correctly blocks shipping the demo signaling key in production and blocks public TURN in stable.
- Drift write path uses a serialized queue + exponential backoff on `SQLITE_BUSY/LOCKED` (good concurrency handling).
- Riverpod lifecycle is clean: `ref.onDispose` used in 7 state files; no `ProviderContainer`/`UncontrolledProviderScope` leaks; providers are explicit `Provider`/`Notifier`/`AsyncNotifier` (Riverpod 3 idiom).

---

## End of audit

**18 flaws** logged across platform integrity (F-001, F-014), call-engine correctness (F-006→F-013), crypto/security (F-004, F-005, F-015, F-016, F-017), test coverage (F-003), maintainability (F-002), and storage/migration (F-017, F-018).

Audit method: read-only — source inspection (`apps/`, `packages/`, `backend/`), CI workflow review, Firebase rules audit, dependency/version check, and a targeted deep-dive of the call runtime (4 core files, ~7,300 lines) with line-level evidence. No files were modified except this TODO. No tests/builds were executed (analysis only) per the "no build unless asked" rule.

**Next session entry point:** pick up from the Priority Order table above; F-001 is a one-command fix and unblocks the Windows platform immediately.

---

## 2026-06-18 — Verification & remediation session

Re-validated every priority item against the live `dev@4798605` tree (the audit
was written against a pre-Phase-3/4 checkout, so several findings were stale).

### Verified stale (no code change needed)
- **F-001 / F-014** — `apps/rain/windows/` is fully tracked (18 files) and on disk.
  Windows build is NOT broken. The audit's "deleted" premise does not hold.
- **F-007** — Already solved by `SerializedRuntimeMutations` (a serialized
  mutation queue). Wired into `rain_runtime_controller` and covered by
  `serialized_runtime_mutations_test.dart`. This is the "state updates dropped
  during session transition" fix from commit `4798605`.

### Fixed (code changes applied, not yet committed)
- **F-006** — `voice_call_runtime._failVoiceCall` now early-returns when the
  current phase is already `ended` or `failed`. A racing signaling error can no
  longer flip a settled `ended` call back to `failed`, eliminating the
  `ended`↔`failed` churn and the double-dispose that followed.
- **F-008** — `call_media_connection.addRemoteCandidate` now serializes the
  candidate apply through a new `_candidateLock` that chains behind any in-flight
  negotiation. Unlike `_runMediaOperation`, it never throws or drops a candidate,
  so trickle-ICE arriving mid-offer/answer can no longer corrupt SDP.
- **F-009** — `VoiceCallSignalingCleanupCoordinator.disposeCurrentVoiceCallSession`
  now disposes video resources in the null-session branch (construction-error
  path). Previously the subscription was cancelled and the method returned,
  leaking native video renderers + their subscription. New
  `disposeVideoCallResources` param wired at the runtime call site.

### Validation (executed)
- `dart analyze apps/rain` + `packages/peer_core` → **No issues found.**
- `flutter test` peer_core call/voice media suites → **44/44 passed.**
- `flutter test` protocol_brain `voice_call_session_test` → **29/29 passed**
  (incl. "failed session ignores late connected media state").
- Pre-existing test failures unrelated to these changes (missing bundled asset
  `peer_core_mark_48.png`): `rain_call_ended_surface_test` (2) and
  `rain_call_stage_test` (1). Reproduced identically on the unmodified tree via
  `git stash` — confirmed NOT caused by this session.

### Ad-hoc focused verification (2026-06-18, after system flag)
Created temporary tests under `%TEMP%/hermes-verify-*.dart`, ran them against
the changed behavior, then deleted them. Treated as ad-hoc, not suite-green.

- **F-008** (`packages/peer_core`): 3 temp tests on `DefaultCallMediaConnection`
  with a delayed `setRemoteDescription` to simulate in-flight negotiation →
  **3/3 passed**: candidate applied after remote SDP reaches PC; candidate
  arriving mid-negotiation is NOT dropped (chained via `_candidateLock`); buffered
  candidate before remote SDP still flushes after offer.
- **F-06** (`apps/rain`): guard read back at `_failVoiceCall` top (lines
  2710–2717). Regression suites exercising the failure/teardown path passed:
  `voice_call_runtime_media_path_test` (6/6),
  `voice_call_runtime_diagnostics_contract_test` (8/8, incl. "terminal failure
  state is published before session cleanup"), `voice_call_state_coordinator_test`
  (6/6). No full-runtime unit harness exists for the guard alone; verified via
  static read + path suites.
- **F-09** (`apps/rain`): temp test instantiating
  `VoiceCallSignalingCleanupCoordinator` directly with a null `currentSession`
  and a counting `disposeVideoCallResources` callback → **1/1 passed**: video
  resources ARE disposed on the null-session branch (pre-fix this returned
  early). `voice_call_preflight_coordinator_test` (5/5) confirms the new
  `disposeVideoCallResources` param at the preflight call site didn't break.
- `dart analyze apps/rain packages/peer_core` after all edits → **No issues found.**

### Still open (not touched this session)
F-002, F-003, F-004, F-005, F-010, F-011, F-012, F-013, F-015, F-016, F-017, F-018.

### Uncommitted files
- `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- `apps/rain/lib/application/runtime/voice_call/voice_call_signaling_cleanup_coordinator.dart`
- `packages/peer_core/lib/src/call/call_media_connection.dart`
- `FLAWS_AND_FIXES_TODO.md` (status updated)

