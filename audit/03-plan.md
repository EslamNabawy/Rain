# Phased Fix Plan

Source: `audit/01-findings.md` (65 findings), `audit/02-refactor-targets.md`. Order: restore a green baseline (Phase 3), fix P1 then P2 with effort S/M (Phase 4), reconcile `main` and `dev` (Phase 5), sync the vault and report (Phase 6). Every Phase 4 card writes its test first. Tool ids (ANALYZE, FORMAT, TEST_PKG, TEST_ALL, FN_TEST, VAULT, RULES_TEST) are defined in `audit/prompts/rain-orchestrator.xml`.

## Phase 3: Restore green baseline

| Task | What | Findings | Verify |
|---|---|---|---|
| T3.1 | `git checkout HEAD -- packages/protocol_brain/lib/adapters/firebase_adapter.dart`; test only if the adapter can be faked without new dependencies (it cannot: no fake for `FirebaseAuth`/`FirebaseDatabase`, see TEST-001; record "TEST gap: see TEST-001") | GIT-001 | ANALYZE; FORMAT; TEST_PKG(packages/protocol_brain) |
| T3.2 | Update only the `Last updated` line in the 7 stale vault registers to today's date | CI-004 | VAULT |
| T3.3 | `.github/workflows/ci.yml:12` `develop` -> `dev` | CI-001 | `Get-Content .github/workflows/ci.yml -TotalCount 16` |
| T3.4 | `npm audit fix` (no `--force`) in `backend/firebase/functions` | BE-002, CI-005 | FN_TEST; `npm audit --omit=dev` shows no critical |
| T3.5 | Full baseline check, record in STATE.md | all | ANALYZE; FORMAT; TEST_ALL; FN_TEST |

## Phase 4: Execute the fix plan

Cards in execution order. P1 cards first (T4.01-T4.07), then P2 by dependency.

#### T4.01 RTDB rules test harness
- Findings: BE-001
- Files: `backend/firebase/rules-test/package.json` (new), `backend/firebase/rules-test/run.js` (new), `backend/firebase/rules-test/cases/*.js` (new), `.github/workflows/ci.yml` (add job step after T3.3)
- Steps:
  1. Create `rules-test/package.json` with one devDependency, `@firebase/rules-unit-testing` (version resolved with `npm view @firebase/rules-unit-testing version` at execution), script `test: node run.js`.
  2. `run.js` starts `initializeTestEnvironment` against the emulator at `localhost:9000` with `database.rules.json`, runs every module in `cases/` and exits non-zero on any failure.
  3. Cases (assertSucceeds / assertFails): own `users/<name>` row create; second account cannot create the same `users/<name>`; `userSearch/<name>` write only by owner; `presence/<name>` spoof denied; `rooms/<a:b>` third-user write denied; `voiceCalls/<id>` offer/answer by wrong uid denied; `activeVoicePairs` second creator denied; `connectionRequests` direct write denied; unauthenticated read denied everywhere.
  4. Add a CI step `npx firebase-tools@<pinned from scripts/ci_run_firebase_emulators.sh> emulators:exec --only database "node rules-test/run.js"` to the existing `firebase-backend` job.
- Tests: `backend/firebase/rules-test/cases/users.js` test "second account cannot claim existing username"; `cases/voice_calls.js` test "third user cannot write offer".
- Verify: RULES_TEST; FN_TEST
- Commit: test(rules): add RTDB rules unit tests with the database emulator
- Effort: L
- Depends on: T3.5

#### T4.02 Make identity key publish non-fatal at registration
- Findings: SEC-001
- Files: `apps/rain/lib/application/state/identity_providers.dart`, `apps/rain/test/auth_identity_source_of_truth_test.dart`
- Steps:
  1. In `IdentityController.register` (`identity_providers.dart:124-166`) wrap `ensureKeyPair` + `publishIdentitySigningKey` in its own `try/catch`; on failure call the existing runtime event/error recorder with source `identity-key-publish` and continue.
  2. Do not sign out on that failure; the identity is saved and the key publish is retried by T4.17 on next login.
- Tests: `apps/rain/test/auth_identity_source_of_truth_test.dart` add "register succeeds and keeps session when publishIdentitySigningKey throws" using a Noop/Fake adapter subclass that throws.
- Verify: TEST_PKG(apps/rain); ANALYZE
- Commit: fix(identity): do not fail registration when the signing key cannot be published
- Effort: S
- Depends on: T3.5

#### T4.03 Allow `users/<name>/signingPublicKey` in the rules
- Findings: SEC-001
- Files: `backend/firebase/database.rules.json`, `backend/firebase/rules-test/cases/users.js`
- Steps:
  1. Add under `users/$username` a child `signingPublicKey` with `.validate`: `newData.isString() && newData.val().length == 44` and `.write`: `root.child('users/' + $username + '/uid').val() === auth.uid && (!data.exists() || newData.val() === data.val())` (immutable once set; rotation is a future ADR).
  2. Keep `$other: .validate false`.
- Tests: `cases/users.js` "owner can write signingPublicKey once", "owner cannot change it", "other user cannot write it", "wrong length rejected".
- Verify: RULES_TEST
- Commit: fix(rules): allow owner-written immutable signingPublicKey under users
- Effort: M
- Depends on: T4.01

#### T4.04 Reclaim expired connected call rooms from the client
- Findings: SIG-003
- Files: `packages/protocol_brain/lib/src/voice_call_cleanup_janitor.dart`, `packages/protocol_brain/lib/adapters/firebase_adapter.dart` (cleanup block at the `room.status != connected` branch), `packages/protocol_brain/test/voice_call_cleanup_janitor_test.dart` (new)
- Steps:
  1. Add a pure `VoiceCallCleanupAction decideRoomCleanup({required VoiceCallRoom? room, required int now, required String? liveCallId})` to the janitor file covering: missing room, terminal, expired non-connected, expired connected (new: `deleteExpiredConnectedRoom`, only when `room.callId != liveCallId`).
  2. Replace the inline `if/else` chain in `cleanupStaleVoiceCallArtifacts` with a call to it and a switch on the action; add the new enum value to `VoiceCallCleanupAction` and its `toJson` name.
  3. Pass the runtime's live call id through the existing `VoiceCallSignalingCleanupCoordinator.cleanupStaleVoiceCallArtifacts` call.
- Tests: `voice_call_cleanup_janitor_test.dart` "connected room past expiresAt is deleted when not the live call", "connected room is kept when it is the live call", "terminal room deleted", "missing room deletes matching locks".
- Verify: ANALYZE; TEST_PKG(packages/protocol_brain); TEST_PKG(apps/rain)
- Commit: fix(signaling): reclaim expired connected call rooms during client cleanup
- Effort: M
- Depends on: T3.5

#### T4.05 Keep presence online during active calls and transfers
- Findings: APP-001
- Files: `apps/rain/lib/application/runtime/rain_runtime_controller.dart` (`didChangeAppLifecycleState`), `apps/rain/test/runtime_presence_lifecycle_test.dart` (new)
- Steps:
  1. Add `bool get hasActiveCallOrTransfer` to the controller (`voiceCallState.hasCall` or `fileTransferStore.hasActiveTransfer...` result cached in a field updated by transfer state changes).
  2. In `AppLifecycleState.hidden/paused`, skip `_setPresenceOfflineSafely` and keep heartbeats running while `hasActiveCallOrTransfer`; when the call ends and the app is still backgrounded, mark offline.
  3. Record `presence_offline_skipped_active_call` event.
- Tests: `runtime_presence_lifecycle_test.dart` "pause with active call keeps presence online", "pause without call marks offline".
- Verify: TEST_PKG(apps/rain); ANALYZE
- Commit: fix(runtime): keep presence online while a call or transfer is active in background
- Effort: S
- Depends on: T3.5

#### T4.06 Introduce database and auth ports for the Firebase adapter
- Findings: TEST-001, GIT-001
- Files: `packages/protocol_brain/lib/adapters/realtime_database_port.dart` (new), `packages/protocol_brain/lib/adapters/firebase_auth_port.dart` (new), `packages/protocol_brain/lib/src/testing/in_memory_realtime_database.dart` (new), `packages/protocol_brain/lib/adapters/firebase_adapter.dart`, `packages/protocol_brain/test/firebase_adapter_register_test.dart` (new), `packages/protocol_brain/test/firebase_adapter_cleanup_test.dart` (new)
- Steps:
  1. Define `RealtimeDatabasePort` (get, set, update, remove, multi-path update, listen) and `FirebaseAuthPort` (createUser, signIn, signOut, currentUserUid, deleteCurrentUser) with SDK-backed implementations created by default.
  2. Move only `register`, `_rollbackNewlyCreatedAuthUser`, `cleanupStaleVoiceCallArtifacts` and `_removeActiveVoice*IfUnchanged` onto the ports; leave the rest on the SDK.
  3. Add the in-memory implementations and the two test files.
- Tests: `firebase_adapter_register_test.dart` "failed users write rolls back the new Auth user before sign-out", "permission denied maps to the taken/locked message"; `firebase_adapter_cleanup_test.dart` "deletes terminal rooms and matching locks".
- Verify: ANALYZE; FORMAT; TEST_PKG(packages/protocol_brain); TEST_PKG(apps/rain)
- Commit: refactor(protocol_brain): add database and auth ports to the Firebase adapter for unit tests
- Effort: L
- Depends on: T3.5

#### T4.07 Report database encryption state honestly
- Findings: SEC-003
- Files: `packages/rain_core/lib/database/rain_database.dart`, `apps/rain/lib/application/bootstrap/app_bootstrap.dart`, `packages/rain_core/test/rain_database_test.dart`
- Steps:
  1. After opening, run `PRAGMA cipher_version` and expose `DatabaseEncryptionState { active, inactive }` (non-empty result means active) on `RainDatabase`.
  2. In `app_bootstrap.dart` record a runtime event `db_encryption_inactive` (no key material) when inactive; correct the doc comments that say "encrypted open".
  3. Do not change the open path or regenerate keys (the option decision is the owner's, see Owner actions).
- Tests: `rain_database_test.dart` "stock sqlite reports encryption inactive".
- Verify: ANALYZE; TEST_PKG(packages/rain_core); TEST_PKG(apps/rain)
- Commit: fix(rain_core): report database encryption state instead of implying encrypted storage
- Effort: S
- Depends on: T3.5

#### T4.08 Make `DefaultPeerCore.destroy` always close and dispose
- Findings: RTC-001
- Files: `packages/peer_core/lib/src/default_peer_core.dart`, `packages/peer_core/test/peer_core_test.dart`
- Steps:
  1. In `destroy()` (`:164-193`) wrap `stopLocalAudio` and each `channel.close()` in their own `try/catch` collecting the first error.
  2. Always run `_peerConnection?.close()` then `.dispose()` and the field resets in `finally`; rethrow the first error after cleanup.
- Tests: `peer_core_test.dart` "destroy closes and disposes the peer connection when stopLocalAudio throws".
- Verify: ANALYZE; TEST_PKG(packages/peer_core)
- Commit: fix(peer_core): destroy always closes and disposes the peer connection
- Effort: S
- Depends on: T3.5

#### T4.09 Make the backpressure wait observe channel close
- Findings: RTC-002
- Files: `packages/peer_core/lib/src/data_channel_backpressure.dart`, `packages/peer_core/test/data_channel_backpressure_test.dart` (new)
- Steps:
  1. In `waitForDrain`, check `channel.state` each poll; throw `StateError('RTCDataChannel closed while waiting for drain')` when not `RTCDataChannelOpen`.
  2. Keep the polling interval and timeout; do not change thresholds.
- Tests: `data_channel_backpressure_test.dart` "throws StateError immediately when the channel closes", "returns when bufferedAmount drops".
- Verify: ANALYZE; TEST_PKG(packages/peer_core)
- Commit: fix(peer_core): stop waiting for drain when the data channel closes
- Effort: S
- Depends on: T3.5

#### T4.10 Resolve crossed call invites deterministically
- Findings: SIG-001
- Files: `apps/rain/lib/application/runtime/voice_call_runtime.dart` (`_prepareIncomingVoiceInvite`), `apps/rain/lib/application/runtime/voice_call/voice_call_preflight_coordinator.dart`, `apps/rain/test/voice_call_glare_test.dart` (new)
- Steps:
  1. Add `VoiceCallPreflightCoordinator.resolveCrossedInvite({required VoiceCallState current, required String localPeerId, required String remotePeerId})` returning `keepLocal` or `acceptRemote` using `isVoiceCallOfferOwner(local, remote)` (lower id wins).
  2. In `_prepareIncomingVoiceInvite`, when `current.isOutgoing`, same peer, and phase is `outgoingRinging` or `preflightingMic`: if `acceptRemote`, hang up the local call best-effort and return `accept`; if `keepLocal`, return `ignore` (the remote side will accept ours).
- Tests: `voice_call_glare_test.dart` "lower id keeps its outgoing call and ignores the crossed invite", "higher id yields and accepts the incoming invite".
- Verify: TEST_PKG(apps/rain); ANALYZE
- Commit: fix(calls): resolve simultaneous calls with a deterministic tie-break
- Effort: M
- Depends on: T3.5

#### T4.11 Buffer early ICE candidates and notify the peer on ringing timeout
- Findings: SIG-002, SIG-005
- Files: `packages/protocol_brain/lib/src/voice_call_session.dart`, `packages/protocol_brain/test/voice_call_session_test.dart`
- Steps:
  1. In `_handleRemoteCandidate` queue (max 64, drop oldest) candidates received in `outgoingRinging`, `preflightingMic` or `incomingRinging`; flush on entry to `connectingMedia`; clear on `failed`/`idle`.
  2. In `_armRingingTimeout` pass `notifyPeer: true`.
- Tests: `voice_call_session_test.dart` "candidate before accept is applied after connectingMedia", "ringing timeout sends hangup".
- Verify: ANALYZE; TEST_PKG(packages/protocol_brain)
- Commit: fix(calls): keep early ICE candidates and tell the callee when ringing times out
- Effort: S
- Depends on: T3.5

#### T4.12 Surface swallowed errors in call expiry and transfer cleanup
- Findings: APP-002, APP-003
- Files: `apps/rain/lib/application/runtime/voice_call_runtime.dart` (`_isExpiredVoiceCallStartBlock`), `apps/rain/lib/application/runtime/file_transfer_runtime.dart` (`failActiveTransfersForPeer`), `apps/rain/test/voice_call_state_coordinator_test.dart`, `apps/rain/test/friend_flow_test.dart`
- Steps:
  1. `_isExpiredVoiceCallStartBlock`: on error, record a runtime event and fall through to the local `sessionEpoch + _voiceCallExpiry` check.
  2. `failActiveTransfersForPeer`: record events and `errorRecorder` for the store read and per-row failures; keep going.
- Tests: `voice_call_state_coordinator_test.dart` "fetchCall error falls back to local expiry"; `friend_flow_test.dart` "failActiveTransfers records a failure when the store throws" (new test next to the existing transfer tests).
- Verify: TEST_PKG(apps/rain); ANALYZE
- Commit: fix(runtime): stop swallowing errors in call expiry and transfer cleanup
- Effort: S
- Depends on: T3.5

#### T4.13 Cover and guard the schema migrations
- Findings: DB-001
- Files: `packages/rain_core/lib/database/rain_database.dart`, `packages/rain_core/test/rain_database_test.dart`
- Steps:
  1. Guard `m.createTable(fileTransfers)` with `!await _hasTable('file_transfers')`.
  2. Add upgrade fixtures for `user_version` 2, 4 and 6.
- Tests: `rain_database_test.dart` "migration from v2 reaches v7 with identity signingPublicKey column", "migration from v4 creates file_transfers", "migration from v6 adds signingPublicKey".
- Verify: ANALYZE; TEST_PKG(packages/rain_core)
- Commit: test(rain_core): cover schema upgrades and guard file_transfers creation
- Effort: S
- Depends on: T3.5

#### T4.14 Store an incoming file offer in one transaction
- Findings: DB-002
- Files: `packages/rain_core/lib/file_transfer/file_transfer_store.dart`, `packages/rain_core/lib/messages/message_store.dart`, `packages/rain_core/lib/friends/friend_store.dart`, `apps/rain/lib/application/runtime/file_transfer_runtime.dart`, `packages/rain_core/test/file_transfer_store_test.dart`
- Steps:
  1. Add non-serialized variants (`*InTransaction`) on the three stores that take an executor and do not call `serializedTransaction` (nesting `serializedTransaction` deadlocks the write queue, `rain_database.dart:262-302`).
  2. Add `FileTransferStore.recordIncomingOffer(...)` that runs one `_database.serializedTransaction` and calls the variants (message insert if absent, unread increment, transfer upsert).
  3. Add `failTransfer(transferId, reason)` doing `markState(failed)` and the outgoing message status in one transaction; use both from `file_transfer_runtime.dart`.
- Tests: `file_transfer_store_test.dart` "recordIncomingOffer rolls back the message when the transfer upsert fails", "failTransfer updates both rows atomically".
- Verify: ANALYZE; TEST_PKG(packages/rain_core); TEST_PKG(apps/rain)
- Commit: fix(rain_core): record incoming file offers and failures atomically
- Effort: M
- Depends on: T4.13

#### T4.15 Quarantine a corrupt database instead of blocking startup
- Findings: DB-003
- Files: `packages/rain_core/lib/database/rain_database.dart`, `apps/rain/lib/application/bootstrap/app_bootstrap.dart`, `packages/rain_core/test/rain_database_test.dart`
- Steps:
  1. Add `RainDatabase.openWithRecovery(...)`: on `StateError` from `beforeOpen` (foreign-key violations) first try `DELETE` of orphan `file_transfers` rows and re-check; if still failing, rename the file to `rain.corrupt-<epochMs>.sqlite` and create a fresh database.
  2. Return a `DatabaseRecoveryNotice` the bootstrap forwards to the UI state (existing startup error surface) without exposing paths.
- Tests: `rain_database_test.dart` "orphan transfer rows are repaired", "unrepairable file is quarantined and a fresh database opens".
- Verify: ANALYZE; TEST_PKG(packages/rain_core); TEST_PKG(apps/rain)
- Commit: fix(rain_core): repair or quarantine a corrupt database at startup
- Effort: M
- Depends on: T4.13

#### T4.16 Disable Android auto-backup of app data
- Findings: SEC-004
- Files: `apps/rain/android/app/src/main/AndroidManifest.xml`, `apps/rain/android/app/src/main/res/xml/data_extraction_rules.xml` (new), `apps/rain/test/android_manifest_security_test.dart` (new)
- Steps:
  1. Set `android:allowBackup="false"` and `android:dataExtractionRules="@xml/data_extraction_rules"` on `<application>`.
  2. Create the rules file excluding `database`, `sharedpref` and `file` domains from cloud backup and device transfer.
- Tests: `android_manifest_security_test.dart` "manifest disables allowBackup and references data extraction rules" (reads the manifest file as text).
- Verify: TEST_PKG(apps/rain)
- Commit: fix(android): disable auto-backup of the local database
- Effort: S
- Depends on: T3.5

#### T4.17 Verify the identity private key exists before trusting the stored public key
- Findings: SEC-005
- Files: `packages/rain_core/lib/identity/identity_key_repository.dart`, `apps/rain/lib/infrastructure/security/flutter_secure_storage_key_store_service.dart`, `packages/rain_core/test/identity_key_repository_test.dart`, `apps/rain/lib/application/state/identity_providers.dart`
- Steps:
  1. In `ensureKeyPair`, when the DB public key exists but `_store.read(_storeId)` returns null, regenerate the pair, persist both, and report `rotated: true` through a return record.
  2. Wrap every exception type from `FlutterSecureStorage` in `KeyStoreException`.
  3. In `IdentityController.login`, call `ensureKeyPair` and re-publish the key best-effort (same handling as T4.02) when `rotated`.
- Tests: `identity_key_repository_test.dart` "regenerates the pair when the private key is missing", "returns the existing key when both exist".
- Verify: ANALYZE; TEST_PKG(packages/rain_core); TEST_PKG(apps/rain)
- Commit: fix(identity): regenerate the identity key pair when the private key is lost
- Effort: S
- Depends on: T4.02

#### T4.18 Allow-list the update URL
- Findings: SEC-007
- Files: `apps/rain/lib/infrastructure/services/force_update_service.dart`, `apps/rain/test/force_update_service_test.dart`
- Steps:
  1. Add `sanitizeUpdateUrl(String candidate, String fallback)`: require `https`, host in {`github.com`}, path prefix `/AbdogadXNabawy/Rain/` or `/EslamNabawy/Rain/`; else return fallback.
  2. Apply it where `updateUrl` is read from Remote Config (`:84`, `:293-295`, `:323`).
- Tests: `force_update_service_test.dart` "rejects non-https and foreign hosts", "accepts the GitHub releases URL".
- Verify: ANALYZE; TEST_PKG(apps/rain)
- Commit: fix(update): ignore Remote Config update URLs outside the release host
- Effort: S
- Depends on: T3.5

#### T4.19 Constrain `userSearch` queries in the rules
- Findings: SEC-006
- Files: `backend/firebase/database.rules.json`, `backend/firebase/rules-test/cases/user_search.js` (new)
- Steps:
  1. Change `userSearch` `.read` to `auth != null && query.orderByKey == true && query.limitToFirst <= 20` (the adapter uses `orderByKey` with `limitToFirst(10)`, `firebase_adapter.dart:1947-1953`); keep per-`$username` direct reads.
  2. Keep writes unchanged.
- Tests: `cases/user_search.js` "limited ordered query succeeds", "full tree read is denied", "limit above 20 is denied".
- Verify: RULES_TEST; TEST_PKG(packages/protocol_brain)
- Commit: fix(rules): require bounded ordered queries on userSearch
- Effort: M
- Depends on: T4.01

#### T4.20 Inject authentication into the TURN credential service
- Findings: ARCH-003
- Files: `apps/rain/lib/infrastructure/services/turn_credential_service.dart`, `apps/rain/lib/application/state/core_providers.dart`, `apps/rain/test/` (new `turn_credential_service_test.dart`)
- Steps:
  1. Remove the default `_defaultFirebaseIdTokenProvider` that reads `FirebaseAuth.instance`; make `idTokenProvider` required.
  2. In `core_providers.dart` supply a provider backed by the adapter (`adapterProvider`) via a small `Future<String?> idToken()` method on the app-level wrapper; drop the `firebase_auth` import from the service.
- Tests: `turn_credential_service_test.dart` "sends the injected bearer token", "does not call the broker without a token".
- Verify: ANALYZE; TEST_PKG(apps/rain)
- Commit: refactor(turn): inject the ID token provider instead of using FirebaseAuth directly
- Effort: S
- Depends on: T3.5

#### T4.21 Split the protocol_brain barrel and move fakes to a testing entry point
- Findings: ARCH-002
- Files: `packages/protocol_brain/lib/protocol_brain.dart`, `packages/protocol_brain/lib/testing.dart` (new), `packages/protocol_brain/lib/protocol_brain_firebase.dart` (new), imports in `apps/rain/lib`, `apps/rain/test`, `packages/rain_core`, `packages/protocol_brain/test`
- Steps:
  1. Create `testing.dart` exporting the three fakes; switch tests to it.
  2. Create `protocol_brain_firebase.dart` exporting `firebase_adapter.dart`, `connection_request_rtdb_adapter.dart`, `signaling_cipher.dart`; switch `app_bootstrap.dart` and `runtime_providers.dart`.
  3. Remove those exports from `protocol_brain.dart`; update `architecture_boundaries_test.dart` and `workspace_contract_test.dart` expectations.
- Tests: `packages/protocol_brain/test/architecture_boundaries_test.dart` "main barrel does not export firebase adapters or fakes".
- Verify: ANALYZE; TEST_ALL
- Commit: refactor(protocol_brain): split firebase adapters and fakes out of the main barrel
- Effort: M
- Depends on: T4.06

#### T4.22 Create `FirebaseFunctions` lazily
- Findings: ARCH-004
- Files: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`, `packages/protocol_brain/test/connection_request_firebase_contract_test.dart`
- Steps:
  1. Replace the eager `_functions = functions ?? FirebaseFunctions.instance` with a lazy getter that is only evaluated by the callable path.
  2. Do not remove the `cloud_functions` dependency (non-Spark mode still uses it).
- Tests: `connection_request_firebase_contract_test.dart` "rtdbOnly mode never touches FirebaseFunctions" (inject a functions provider that throws if called).
- Verify: ANALYZE; TEST_PKG(packages/protocol_brain)
- Commit: refactor(protocol_brain): instantiate FirebaseFunctions only for the callable backend mode
- Effort: S
- Depends on: T4.06

#### T4.23 Pin third-party actions and enable Dependabot for Actions
- Findings: CI-003
- Files: `.github/workflows/*.yml`, `.github/dependabot.yml`
- Steps:
  1. For `subosito/flutter-action` and `softprops/action-gh-release`, resolve the commit SHA of the tag in use with `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` and replace `@vN` by `@<sha> # vN` in every workflow.
  2. Add `.github/dependabot.yml` entries for `github-actions`, `npm` (`/backend/firebase/functions`) and `pub` (`/`), weekly.
  3. Change `rain-ci-cd.yml` and `documentation-vault.yml` `checkout@v4`/`artifact@v4` to the majors used elsewhere.
- Tests: `packages/protocol_brain/test/ci_contract_test.dart` add "third-party actions are pinned to a 40-hex SHA".
- Verify: TEST_PKG(packages/protocol_brain)
- Commit: ci: pin third-party actions by SHA and enable Dependabot
- Effort: S
- Depends on: T3.3

## Phase 5: Reconcile main and dev

| Task | What | Findings | Verify |
|---|---|---|---|
| T5.1 | Branch `integration/main-dev` from `audit/rain-hardening`, `git merge --no-ff origin/main`, resolve per the conflict policy in the orchestrator (audit side wins for security, crypto, call/session logic, backpressure, `rain_database`, `file_transfer_runtime`, workflows; keep both sides in vault and `CONTINUITY.md`; regenerate `rain_database.g.dart` with build_runner), push `integration/main-dev`, never merge into `main`/`dev` | GIT-002 | ANALYZE; FORMAT; TEST_ALL; FN_TEST |

## Owner actions

These need credentials, consoles, devices or a human decision and are not executed by the program.

1. Rotate or revoke, if still live, the `RAIN_ICE_SERVERS` TURN credentials and the Supabase anon key found in `apps/rain/tool/dart_defines.local.json` history (commits 0d8147c, 6ff832b) (GIT-003). History is not rewritten.
2. Restrict the Firebase API key in Google Cloud console (Android package + SHA-1, API allow-list) and decide on App Check for Android; enable per-IP sign-up throttling in the Auth console (GIT-004, SEC-006).
3. Confirm the deployed RTDB rules equal `backend/firebase/database.rules.json` (`firebase database:get /` rules export) before relying on the SEC-001 analysis, then deploy the rules from T4.03 and T4.19.
4. Decide the database encryption option (SEC-003): keep ADR-010 (plaintext) or adopt option (a) sqlite3 SQLCipher build hook with a verified migration; build and device-test on Android and Windows (R7 forbids builds in this program). Recorded as ADR-012.
5. Device tests on Android 13+ and Windows: call survives Home for 60 s and window minimize (APP-001); Android foreground service for calls (APP-001 part 2: manifest `FOREGROUND_SERVICE_MICROPHONE`); crossed invites within 50 ms (SIG-001); a 3-minute connected call on Blaze/emulator (SIG-004); file picker on `file_picker` 13.x before bumping (ARCH-006).
6. After CI consolidation (backlog CI-002), update GitHub branch protection required checks to the new job names, and protect `main` and `dev`.
7. Measure Firebase RTDB usage with 5 accounts for 24 h before changing the heartbeat interval (BE-003).
8. Decide whether `D:\Rain` replaces `C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain` as canonical and update `AGENTS.md` (DOC-006); decide when to merge `integration/main-dev` into `main`.
9. Decide the TURN broker rollout so release builds do not depend on `RAIN_ICE_SERVERS` literals (RTC-003).

## Backlog

Not scheduled in Phase 4 (P3, effort L/XL, needing devices or decisions, or covered by Phase 6 vault work):

- GIT-004 tracked Firebase client config (owner key restriction), GIT-005 dependabot branch (closes after T3.4), GIT-006 stray root plan docs and empty dirs
- ARCH-001 `rain_models` package (refactor target 6 step 4), ARCH-005 melos scripts, ARCH-006 beta/EOL dependencies, ARCH-007 stricter lints
- SEC-002 wire per-pair E2E (L, depends on T4.03 and T4.17; own ADR)
- SIG-004 refresh voice room liveness for Blaze cleanup (rules make `expiresAt` immutable; use `updatedAt` heartbeat), SIG-006 TASK-005 reproduction
- RTC-003 release TURN broker default, RTC-004 file transfer resume and free-space check
- APP-004 `brain!` after awaits, APP-005 provider disposal
- DB-004 pruning of terminal transfers and failed queue rows
- BE-003 heartbeat interval (after measurement), BE-004 emulator configuration drift
- QUAL-001 long functions (refactor targets 1-5), QUAL-002 chunk envelope parsing, QUAL-003 timeout constants, QUAL-004 adapter decorators (target 8)
- TEST-002 emulator suites against the real adapter, TEST-003 delete the skipped legacy test, TEST-004 covered case by case in Phase 4 cards, TEST-005 coverage floors
- CI-002 workflow consolidation (refactor target 7), CI-006 Flutter version pin, CI-007 demo/stable separation
- DOC-001, DOC-002, DOC-003 handled by T6.1 vault update, DOC-004 backend README fix, DOC-005 duplicate vault folders, DOC-006 owner action 8
