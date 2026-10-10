# Refactor Targets

Rules for every target (from the orchestrator): move code without behavior change in one commit, improve in a second commit; each migration step leaves `ANALYZE`, `FORMAT` and the package tests green; the characterization tests in "Safety net" are written first and must pass before any move. Line counts are from HEAD `601647c`.

## 1. `voice_call_runtime.dart` (2,947 lines)

**Current shape**
- One `extension VoiceCallRuntime on RainRuntimeController` (`voice_call_runtime.dart:38`) that adds about 120 methods and private helpers to the 2,423-line controller; state lives on the controller (fields `voiceCallState`, `voiceCallSession`, `acceptingVoiceCallId`, ...).
- Responsibilities, by line range: start flow and failure mapping (`:77-345`), accept/reject/hangup/controls (`:346-730`), incoming entry, frame dispatch and invite handling (`:731-1165`), session creation, signaling watchers and room reconciliation (`:1185-1470`), ICE batching and frame send/encrypt (`:1442-1590`, `:1903-1977`), session-state application and failure recording (`:1591-1830`), media connection factories and renderer handling (`:2021-2148`), cleanup and terminal-write handling (`:2157-2570`), reconnect grace (`:2571-2640`).
- Existing coordinators already extracted in `application/runtime/voice_call/`: `voice_call_preflight_coordinator.dart`, `voice_call_media_coordinator.dart`, `voice_call_signaling_cleanup_coordinator.dart` (1,828 lines, contains the 340-line `sendVoiceFrameObject`), `voice_call_state_coordinator.dart`, `voice_call_session_state_coordinator.dart`, `voice_call_reconnect_coordinator.dart`, `voice_call_room_coordinator.dart`, `voice_call_terminal_reconciler.dart`, `voice_call_error_coordinator.dart`.

**Target shape**
- `voice_call_runtime.dart`: only public entry points (`startVoiceCall`, `acceptVoiceCall`, `rejectVoiceCall`, `hangUpVoiceCall`, controls, `handleVoiceCallFrame`), each one 5-20 lines delegating to a coordinator. Target under 500 lines.
- `voice_call/voice_call_invite_coordinator.dart`: `_handleVoiceInvite*`, `_prepareIncomingVoiceInvite`, replace-for-retry, glare tie-break (SIG-001).
- `voice_call/voice_call_frame_io.dart`: `_sendVoiceFrame`, `_encryptVoiceFrame`, `_decryptVoiceFrame`, ICE batching and budget recording.
- `voice_call/voice_call_end_coordinator.dart`: `_endVoiceCallForPeerImpl`, terminal-write race settlement, `cleanupStaleVoiceCallArtifacts` hooks (SIG-003).
- `voice_call/voice_call_media_factory.dart`: audio/video `VoiceMediaConnection` factories and renderer callbacks.
- Split the 340-line `sendVoiceFrameObject` into guard, build, write, record steps (max 60 lines each).

**Migration steps**
1. Add characterization tests (below); no production edits.
2. Extract `voice_call_media_factory.dart` (pure construction, no state): move and re-point calls. Tests green.
3. Extract `voice_call_frame_io.dart` (stateless apart from the ICE batcher passed in). Tests green.
4. Extract `voice_call_end_coordinator.dart`; keep `endVoiceCallForPeer` as a one-line delegate. Tests green.
5. Extract `voice_call_invite_coordinator.dart`; keep `_IncomingVoiceInviteDisposition` as a public enum in that file. Tests green.
6. Second commit series (behavior): glare tie-break, `_isExpiredVoiceCallStartBlock` fallback (APP-002), `notifyPeer` on ringing timeout (SIG-005), session-level candidate queue (SIG-002).
7. Delete dead helpers reported by `ANALYZE` (`unused_element`).

**Safety net**
- `apps/rain/test/voice_call_runtime_media_path_test.dart` and `voice_call_state_coordinator_test.dart` stay as they are.
- New `apps/rain/test/voice_call_invite_dispositions_test.dart`: table test of `_prepareIncomingVoiceInvite` for each (current phase, same/different peer, same/different callId) combination, using `FakeVoiceSignalingAdapter`.
- New `voice_call_end_paths_test.dart`: hangup in each phase, terminal already closed, terminal write failure, expiry.
- `packages/protocol_brain/test/voice_call_session_test.dart` keeps the FSM table.

**Risk**: H. Central call path, state held on the controller, behavior covered mostly by one 5,000-line `friend_flow_test.dart` plus emulator tests that only CI runs.

**Linked findings**: SIG-001, SIG-002, SIG-003, SIG-005, APP-001, APP-002, APP-004, QUAL-001, TEST-004, DOC-001

## 2. `firebase_adapter.dart` (3,046 lines at HEAD)

**Current shape**
- One class `FirebaseSignalingAdapter implements SignalingAdapter, VoiceSignalingAdapter, ConnectionRequestAdapter` with: cipher routing (`:29-220`), emulator setup (`:220`), identity and presence JSON (`:244-336`), legacy room API (`:337`, `:2337-2460`, `:2796-2920`), voice call create, locks, reclaim and cleanup (`:344-1420`), auth, register, login, delete account (`:1428-1920`), search and friends (`:1924-2155`), connection-request callables (`:2158-2325`), presence, ICE and voice offers (`:2454-2790`), validation helpers (`:2926-3040`).
- Zero unit-test coverage (TEST-001); registration rollback logic lives in the same file as everything else (GIT-001).

**Target shape** (files under `packages/protocol_brain/lib/adapters/firebase/`, the class keeps its public API)
- `realtime_database_port.dart`: the small interface (get, set, update, remove, push, onDisconnect, listen) plus `FirebaseRealtimeDatabasePort` over the SDK and an in-memory fake in `lib/src/testing/`.
- `firebase_auth_flow.dart`: register, login, rollback, reauthenticate, delete account.
- `firebase_presence.dart`: presence JSON, heartbeat, `onDisconnect`.
- `firebase_voice_calls.dart`: create/accept/end, locks and reclaim, cleanup, inbox.
- `firebase_legacy_rooms.dart`: `rooms/*` offer/answer/ICE (kept until removed).
- `firebase_social.dart`: search, friends, blocks.
- `firebase_connection_request_functions.dart`: the callable path (and the `cloud_functions` import, ARCH-004).
- `signaling_payload_crypto.dart`: `_resolvePairCipher`, `_encryptSignalingPayload`, `_decryptSignalingPayload`.

**Migration steps**
1. Introduce `RealtimeDatabasePort`; make the adapter use it through a private `_db` field (no behavior change; SDK-backed port). Tests green.
2. Add unit tests on the in-memory port for registration rollback, `cleanupStaleVoiceCallArtifacts` decisions, lock reclaim, cipher routing (v=1 and v=2).
3. Move `signaling_payload_crypto.dart` (pure functions over a cipher resolver).
4. Move auth flow, then presence, then voice calls, one commit each, the main class delegating.
5. Move the callable path and make `FirebaseFunctions` lazy.
6. Remove legacy rooms if `Grep` shows no caller (decision for the owner).

**Safety net**: the CI emulator suites (`integration_*_test.dart`) must be green before each move; add `firebase_adapter_register_test.dart` and `firebase_adapter_cleanup_test.dart` against the fake port before step 3.

**Risk**: H. Every backend call passes through this file and local verification is limited to the emulator suites.

**Linked findings**: GIT-001, ARCH-002, ARCH-004, SEC-001, SEC-002, SIG-003, TEST-001, TEST-002, QUAL-001

## 3. `rain_runtime_controller.dart` (2,423 lines)

**Current shape**
- `class RainRuntimeController with WidgetsBindingObserver` (`:203`) owns presence resolution and caching (`:473-650`), peer connection coordinator snapshots, `start()` (268 lines, `:708`), heartbeat and presence (`:1006-1115`), friend actions, `connectPeer` (242 lines, `:1210`), network loss/available handling (`:1484-1660`), logout, account deletion and shutdown (`:1670-1940`, `:2373-2560`), messaging and file send entry points (`:1984-2297`), lifecycle observer (`:2340`). Behavior is further spread over four extensions in sibling files: `VoiceCallRuntime`, `FileTransferRuntime`, `FriendRuntime`, `ConnectionRequestRuntime`.

**Target shape**
- `runtime_lifecycle.dart`: start/shutdown/logout/account deletion/lifecycle observer (with the `APP-001` rule: no presence-offline while a call or transfer is active).
- `runtime_presence.dart`: heartbeat, online/offline, resolver cache (`ResolvedBackendPresence`).
- `runtime_connectivity.dart`: network lost/available, `connectPeer`/`disconnectPeer`.
- `rain_runtime_controller.dart`: field holder and composition root only, under 600 lines.
- Each extension becomes a coordinator class that receives a narrow interface instead of `this`.

**Migration steps**
1. Characterization tests for `start`, `connectPeer`, `handleNetworkLost`, `beginLogOut` (below).
2. Extract `runtime_presence.dart` (stateless functions + cache object), controller keeps delegating getters.
3. Extract `runtime_lifecycle.dart` (shutdown and account deletion sequences, which already use a step-runner `runStep`).
4. Split `start()` into named steps (bootstrap, listeners, initial sync) with no logic change.
5. Split `connectPeer` into preflight, attempt, outcome recording.
6. Convert the four extensions to coordinator classes one at a time, starting with `FileTransferRuntime` (APP-003, APP-004, DB-002).

**Safety net**: `runtime_startup_test.dart`, `runtime_network_loss_test.dart`, `session_lifecycle_providers_test.dart`, `runtime_interaction_guard_test.dart` exist; add `runtime_presence_lifecycle_test.dart` for pause/resume with and without an active call.

**Risk**: H. The controller is the single owner of all runtime state; hidden coupling through extensions (R-008 in the risk register).

**Linked findings**: APP-001, APP-003, APP-004, APP-005, DB-002, QUAL-001, DOC-001

## 4. `connection_request_rtdb_adapter.dart` (2,183 lines)

**Current shape**
- `RtdbOnlyConnectionRequestAdapter` (`:67`) in `rtdbOnly` mode implements create/cancel/accept/reject/seen/mute/unmute (`:191-516`), quota (`:552-600`), watchers (`:602-632`), cleanup of malformed and expired mirror rows and pair locks (`:633-1130`), terminal transitions with transaction retries (`:1130-1416`), payload reads, usage counters and quota rollback (`:1417-1700`), pair-lock rollback (`:1790`), and helper value classes (`:2076-2236`). `createConnectionRequest` is 185 lines.

**Target shape** (folder `packages/protocol_brain/lib/src/connection_request/rtdb/`)
- `rtdb_connection_request_adapter.dart`: public methods only (about 400 lines).
- `rtdb_request_transitions.dart`: terminal/seen transitions.
- `rtdb_request_cleanup.dart`: mirror/pair-lock cleanup and expiry reconciliation.
- `rtdb_request_quota.dart`: usage counters, reservation, rollback, mute checks.
- `rtdb_request_paths.dart`: mirror path value classes and day-key helpers.

**Migration steps**
1. Keep `connection_request_rtdb_adapter_test.dart` and `connection_request_rtdb_rules_contract_test.dart` untouched as the net.
2. Move value classes and path helpers (pure).
3. Move quota functions (pass the database and clock explicitly).
4. Move cleanup, then transitions.
5. Split `createConnectionRequest` into validation, quota reserve, pair-lock claim, write, rollback.

**Safety net**: add `connection_request_rtdb_fake_port_test.dart` after target 2 step 1 (reuse `RealtimeDatabasePort`).

**Risk**: M. Behavior is well covered (73 % per Phase 0) and runs in rtdbOnly mode (default).

**Linked findings**: ARCH-002, BE-001, QUAL-001, TEST-001

## 5. `chat_panel.dart` (1,830 lines) and `home_screen.dart` (1,687 lines)

**Current shape**
- `chat_panel.dart` holds `_ChatPanel`/`_ChatPanelState` (build 187 lines, `_buildCommandHeader` 213, `_showLinkCommandDialog` 179, `_buildMessages` 149) and is a library part of the home screen; `home_screen.dart` holds `HomeScreen`, `_HomeScreenState` (build 222 lines), `_ConnectionStatus` computation (`_connectionStatusForDiagnostics`, 124 lines) and layout modes (`DesktopChatLayoutMode`). Coverage: 23 % and 27 %.

**Target shape**
- `widgets/home/chat_header.dart`, `chat_message_list.dart`, `chat_composer_area.dart`, `link_command_dialog.dart` as separate files; `chat_panel.dart` composes them (under 400 lines).
- `application/state/connection_status_presenter.dart`: pure function from `ConnectionDiagnostics` to the view model, moved out of the widget; `home_screen.dart` only lays out panes.

**Migration steps**
1. Widget tests for the header, the message list states (empty, loading, error) and the connection status presenter (golden values for each `canChat`/online/connection combination).
2. Move `_connectionStatusForDiagnostics` to the presenter (pure).
3. Extract `link_command_dialog.dart` then `chat_header.dart`, then message list, one commit each.
4. Remove the `part of` link once the panel no longer needs private access.

**Safety net**: `chat_panel_connectivity_test.dart`, `rain_chat_widgets_test.dart`, `root_screen_test.dart`; add `connection_status_presenter_test.dart`.

**Risk**: L. Presentation-only; keep APIs of public widgets.

**Linked findings**: QUAL-001, TEST-005

## 6. `protocol_brain` public barrel

**Current shape**: `protocol_brain.dart` re-exports 21 symbols from `peer_core` plus `firebase_adapter.dart` (`:44`), `connection_request_rtdb_adapter.dart` (`:51`) and `src/testing/fake_connection_request_adapter.dart` (`:57`). `rain_core` imports the whole barrel for five types (ARCH-001).

**Target shape**
- `protocol_brain.dart`: interfaces, contracts, value types, `DefaultProtocolBrain`.
- `protocol_brain_firebase.dart`: `FirebaseSignalingAdapter`, `RtdbOnlyConnectionRequestAdapter`, `SignalingCipher`.
- `testing.dart`: all fakes (`FakeConnectionRequestAdapter`, `FakeVoiceSignalingAdapter`, `LiveSmokePeerCore`).
- Shared value types (`ConnectionMemory`, `ConnectionMemoryStore`, `VoiceCallFrame`, `VoiceCallFrameType`, `CallMediaMode`) move to a dependency-free package `rain_models` (new workspace member, no third-party dependencies) that both `rain_core` and `protocol_brain` import.

**Migration steps**
1. Add `testing.dart` exporting the fakes; keep old exports. Switch tests and app to `testing.dart`.
2. Add `protocol_brain_firebase.dart`; switch `app_bootstrap.dart` and `runtime_providers.dart` imports. Remove the adapter exports from the main barrel.
3. Remove the fake export from the main barrel.
4. Create `packages/rain_models` with the five types and re-export them from `protocol_brain` for one release; switch `rain_core` imports.
5. Add the new package to the root `pubspec.yaml` workspace and melos scripts.

**Safety net**: `architecture_boundaries_test.dart` (protocol_brain) and `apps/rain/test/architecture_layers_test.dart` assert import rules; extend them with the new boundaries first.

**Risk**: M. Mechanical, but touches imports in many files; `workspace_contract_test.dart` may assert the package list and need updating.

**Linked findings**: ARCH-001, ARCH-002, ARCH-003, ARCH-004, ARCH-005

## 7. CI workflow set

**Current shape**: 8 workflows (`ci.yml` 12 jobs, `main-merge-gate.yml` 8, `rain-ci-cd.yml` 4, `documentation-vault.yml` 1, four release workflows); `develop` filter typo, no SHA pinning, mixed artifact-action majors, failing vault and audit gates (CI-001..CI-005).

**Target shape**
- `ci.yml`: jobs `quality` (format, analyze), `unit` (matrix per package), `backend` (functions lint/test + rules tests), `emulator` (integration), `android-debug` and `windows-config` (PR to `main` only), `vault` (non-blocking on PR, blocking on `main`), `required-checks` aggregator.
- `release.yml`: dispatch/tag, `needs` CI success on the same SHA, environment-protected secrets, builds both platforms, publishes a draft release.
- Delete `main-merge-gate.yml`, `rain-ci-cd.yml`, `build-artifacts.yml`, `fast-release.yml`, `validated-release.yml`, `documentation-vault.yml` (folded into `ci.yml`).
- `.github/dependabot.yml`: `github-actions`, `npm` (functions), `pub` weekly.

**Migration steps**
1. T3.3 and T3.4 first (branch filter, npm audit).
2. Add the rules test job (after BE-001) and SHA-pin third-party actions.
3. Fold unique jobs into `ci.yml`; run both sets in parallel on a test branch for a week.
4. Remove the old workflows in one commit after the required-check names are updated in GitHub branch protection (owner action).

**Safety net**: `packages/protocol_brain/test/ci_contract_test.dart` and `release_contract_test.dart` assert workflow content; update them in the same commits.

**Risk**: M. Branch protection depends on job names; changes can block merges until the owner updates required checks.

**Linked findings**: CI-001, CI-002, CI-003, CI-004, CI-005, CI-006, CI-007, BE-001, BE-002

## 8. Signaling adapter decorators and fakes

**Current shape**: `DebugSignalingAdapter` (1,280 lines, 66 overrides), `NoopSignalingAdapter` (468), `FakeVoiceSignalingAdapter` (868), `FakeConnectionRequestAdapter` (527) each re-implement the `SignalingAdapter` surface of 33 asynchronous members.

**Target shape**
- `ForwardingSignalingAdapter` (abstract, delegates every member to an inner adapter) in `protocol_brain`; `LoggingSignalingAdapter extends ForwardingSignalingAdapter` overrides only the methods it wants to log through one `invoke(name, call)` helper.
- `NoopSignalingAdapter` stays explicit; fakes share a `FakeRealtimeState` with the in-memory database port from target 2.

**Migration steps**
1. Add `ForwardingSignalingAdapter` with a test that every `SignalingAdapter` member is forwarded (reflection-free: a fake inner adapter records calls).
2. Rewrite `DebugSignalingAdapter` as a subclass; delete forwarding stubs. Existing debug logging tests stay green.
3. Point the fakes at the shared fake state after target 2 step 2.

**Safety net**: `rain_debug_log_service_test.dart` and the adapter contract tests in `packages/protocol_brain/test/`.

**Risk**: L.

**Linked findings**: QUAL-004, TEST-001, TEST-002
