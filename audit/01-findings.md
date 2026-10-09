# Findings

Source of truth: repository at `dev` 601647c plus `audit/00-inventory.md`. Findings follow the format in `audit/prompts/rain-orchestrator.xml`.

## A. Repo health and git

### GIT-001 Uncommitted `firebase_adapter.dart` edit breaks the build and regresses registration rollback
- Severity: P0 | Confidence: High
- Location: `packages/protocol_brain/lib/adapters/firebase_adapter.dart:1469-1519`
- Evidence: (audit/00-inventory.md §3.2, observed in Phase 0)
```
flutter analyze packages/protocol_brain -> 186 issues, exit 1
dart format -> "line 3024, column 1 ... Expected to find '}'"
firebase_adapter.dart:1503 / :1509  } catch (_) {   (closing braces lost)
```
- Why it matters: working tree cannot compile; every package importing protocol_brain cannot build or test. Even if braces were restored, `_auth.signOut()` runs before `_rollbackNewlyCreatedAuthUser` (which only deletes when `currentUser?.uid == user.uid`), so each failed registration leaves an orphaned Auth user and the username is permanently unregistrable.
- Fix: restore HEAD version (T3.1); WIP preserved in `audit/wip/firebase_adapter-uncommitted.patch`.
- Effort: S

### GIT-002 `main` and `dev` diverged with 51 files changed on both sides
- Severity: P1 | Confidence: High
- Location: merge-base `4798605`; `origin/main` +25 commits, `origin/dev` +17
- Evidence: computed with `git diff --name-only 4798605 origin/{main,dev}` intersection
```
51 overlap files: apps/rain 18, packages/protocol_brain 7, packages/rain_core 5,
packages/peer_core 4, docs/audits 5, obsidian-vault 8, backend/firebase/functions 2,
.github/workflows 1 (rain-ci-cd.yml), CONTINUITY.md, README.md
```
- Why it matters: highest-risk code (`firebase_adapter.dart`, `signaling_cipher.dart`, `voice_call_session.dart`, `voice_call_runtime.dart`, `file_transfer_runtime.dart`, `rain_database.dart` and its `.g.dart`, `default_peer_core.dart`, `data_channel_backpressure.dart`) changed on both sides; a naive merge silently picks one side of security or call-logic fixes. `rain_database.g.dart` cannot be hand-merged.
- Fix: reconcile on `integration/main-dev` per the Phase 5 conflict policy; regenerate `rain_database.g.dart` with build_runner.
- Effort: L

### GIT-003 `dart_defines.local.json` is in git history (commits 0d8147c, 6ff832b)
- Severity: P0 | Confidence: High
- Location: `apps/rain/tool/dart_defines.local.json` (added `0d8147c`, removed `6ff832b`)
- Evidence:
```
git log --all -- apps/rain/tool/dart_defines.local.json
6ff832b Clean up Rain app and CI dependencies
0d8147c feat(OpenCode): Phase 1 architecture & validation artifacts ...
keys (names only): RAIN_BACKEND, RAIN_ICE_SERVERS, RAIN_UPDATE_URL, FIREBASE_DATABASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY
```
- Why it matters: values were not inspected (R5). `RAIN_ICE_SERVERS` may carry TURN credentials and `SUPABASE_ANON_KEY` is a bearer credential. They remain recoverable by anyone with read access to the repo or a clone.
- Fix: owner rotates TURN credentials and the Supabase anon key if still live (decision D5). Do not rewrite history (R2). File is gitignored now.
- Effort: S (owner action)

### GIT-004 Tracked Firebase client config (`google-services.json`, `firebase_options.dart`)
- Severity: P3 | Confidence: Medium
- Location: `apps/rain/android/app/google-services.json`, `apps/rain/lib/infrastructure/firebase/firebase_options.dart`
- Evidence: `git ls-files` lists both.
- Why it matters: client Firebase config is not secret; its safety depends on RTDB rules and API key restrictions. Severity stays P3 provided those hold; see SEC-xxx findings in section E (rules are traced in SEC checks) and the owner action on API key restrictions.
- Fix: none in repo; owner restricts the API key (Android package + SHA-1, API allow-list) in Google Cloud console.
- Effort: S (owner action)
- Confirm by: T1.5 rules trace (see SEC findings); API key restriction can only be checked in the console.

### GIT-005 Unmerged dependabot branch for `qs` / `firebase-functions`
- Severity: P3 | Confidence: High
- Location: `origin/dependabot/npm_and_yarn/backend/firebase/functions/multi-0fc86330f8`
- Evidence:
```
d857fe0 chore(deps): bump qs and firebase-functions
```
- Why it matters: it overlaps with the npm audit fix in T3.4 (and `package.json`/lock are among the 51 both-sided files), so merging it separately will conflict.
- Fix: do T3.4 `npm audit fix`; then close the dependabot branch/PR once the lock matches.
- Effort: S

### GIT-006 Stray empty root dirs and overlapping plan documents
- Severity: P3 | Confidence: High
- Location: `integration_test/`, `test_driver/`, `RAIN_DEEP_ANALYSIS_AND_PLAN.md` (39,684 B), `RAIN_ENGINEERING_OVERHAUL_PLAN.md` (55,603 B), `docs/audits/*` (11 files)
- Evidence:
```
git ls-files integration_test test_driver -> 0 files; both dirs exist locally (empty, untracked)
```
- Why it matters: empty dirs are not in git (harmless locally); two large root plan documents overlap `docs/audits/PROJECT_DEEP_ANALYSIS.md` and `FLAWS_AND_FIXES_TODO.md`, so there are several competing sources of truth for the same backlog.
- Fix: move the two root plans into `docs/audits/` (or mark superseded) and link them from the vault; delete the empty local dirs.
- Effort: S

## B. Monorepo structure

### ARCH-001 `rain_core` (storage) depends on `protocol_brain` (signaling) for two small types
- Severity: P2 | Confidence: High
- Location: `packages/rain_core/lib/src/drift_connection_memory_store.dart:4`, `packages/rain_core/lib/voice_call/voice_call_frame.dart:1`
- Evidence:
```
voice_call_frame.dart:1  export 'package:protocol_brain/protocol_brain.dart' show CallMediaMode, VoiceCallFrame, VoiceCallFrameType;
drift_connection_memory_store.dart:4  import 'package:protocol_brain/protocol_brain.dart';   // ConnectionMemoryStore, ConnectionMemory
```
- Why it matters: importing the whole `protocol_brain` barrel drags Firebase (auth, database, cloud_functions) into the storage package, so a pure-DB change recompiles and retests signaling and the graph `rain_core -> protocol_brain -> peer_core` cannot be reordered. rain_core only needs `ConnectionMemory`, `ConnectionMemoryStore`, `VoiceCallFrame`, `VoiceCallFrameType`, `CallMediaMode`.
- Fix: extract these value types into a dependency-free package (e.g. `rain_models`) or into `rain_core`, and have `protocol_brain` depend on it; at minimum import `package:protocol_brain/src/...` narrowed `show` instead of the barrel.
- Effort: M

### ARCH-002 `protocol_brain` public barrel exports concrete Firebase adapters and a test fake
- Severity: P2 | Confidence: High
- Location: `packages/protocol_brain/lib/protocol_brain.dart:44`, `:51`, `:57`
- Evidence:
```
44: export 'adapters/firebase_adapter.dart';
51: export 'src/connection_request_rtdb_adapter.dart';
57: export 'src/testing/fake_connection_request_adapter.dart';
```
- Why it matters: any importer of the barrel (including `rain_core`, see ARCH-001) gets production Firebase code and `FakeConnectionRequestAdapter` in its API; the fake can be instantiated in release code by mistake. `src/testing/` also holds `fake_voice_signaling_adapter.dart` and `live_smoke_peer_core.dart`, which are not exported, so the testing split is already inconsistent.
- Fix: move fakes to `package:protocol_brain/testing.dart` (separate entry point); split `protocol_brain.dart` into an interface barrel and `protocol_brain_firebase.dart` for adapters.
- Effort: M

### ARCH-003 App imports the Firebase SDK in four places beyond bootstrap
- Severity: P2 | Confidence: High
- Location: `apps/rain/lib/application/bootstrap/app_bootstrap.dart:1-3`, `apps/rain/lib/infrastructure/services/force_update_service.dart:3`, `apps/rain/lib/infrastructure/services/network_status_service.dart:4`, `apps/rain/lib/infrastructure/services/turn_credential_service.dart:5`, `:165`
- Evidence:
```
turn_credential_service.dart:165  final user = FirebaseAuth.instance.currentUser;
network_status_service.dart:101   final FirebaseDatabase _database;
```
- Why it matters: `app_bootstrap.dart` and `firebase_options.dart` are legitimate composition-root uses. `force_update_service.dart` (Remote Config) and `network_status_service.dart` (injects `FirebaseDatabase`) are infrastructure services and acceptable. `turn_credential_service.dart:165` reads the `FirebaseAuth.instance` singleton directly instead of an injected auth/identity provider, so it cannot be tested without Firebase and bypasses the app's identity layer.
- Fix: inject a `Future<String?> Function()` ID-token/uid getter into `TurnCredentialService` from `identity_providers.dart`.
- Effort: S

### ARCH-004 `cloud_functions` is a hard dependency of `protocol_brain` although Spark default is `rtdbOnly`
- Severity: P2 | Confidence: High
- Location: `packages/protocol_brain/pubspec.yaml:22`, `packages/protocol_brain/lib/adapters/firebase_adapter.dart:3`, `:27`, `:35`, `:44`, `:2284` (HEAD)
- Evidence:
```
firebase_adapter.dart:35  _functions = functions ?? FirebaseFunctions.instance,
firebase_adapter.dart:2284  } on FirebaseFunctionsException catch (error) {
```
- Why it matters: `FirebaseFunctions.instance` is eagerly created in the constructor even in `rtdbOnly` mode; the plugin adds binary size and a Blaze-only code path to a Spark app (constraint D4). It is not a runtime failure, but it blurs which features work on Spark.
- Fix: make `functions` a lazy getter and move the callable path behind `ConnectionRequestBackendMode.cloudFunctions`; longer term, move callable code to a separate adapter file/package.
- Effort: M

### ARCH-005 Melos scripts cover only pub get, analyze and test
- Severity: P3 | Confidence: High
- Location: `pubspec.yaml:15-19`
- Evidence:
```
scripts:
  pub:get: dart run melos exec -- flutter pub get
  analyze: dart run melos exec -- flutter analyze
  test: dart run melos exec --concurrency=1 -- flutter test
```
- Why it matters: format check, coverage, build_runner (needed for `rain_database.g.dart`), functions tests and rules tests are run by hand or only in CI, so local and CI behavior drift.
- Fix: add `format`, `format:check`, `coverage`, `build_runner`, `functions:test`, `rules:test` scripts.
- Effort: S

### ARCH-006 Beta and end-of-life dependencies in production
- Severity: P2 | Confidence: High
- Location: `apps/rain/pubspec.yaml:17` (`file_picker: ^12.0.0-beta.3`), `pubspec.lock:1287-1302` (`sqlite3` 3.3.1, `sqlite3_flutter_libs` 0.6.0+eol), `packages/rain_core/pubspec.yaml:22`
- Evidence:
```
apps/rain/pubspec.yaml:17  file_picker: ^12.0.0-beta.3          (latest stable 13.1.0, audit/00-inventory.md §4.2)
pubspec.lock  sqlite3_flutter_libs  version: "0.6.0+eol"
```
- Why it matters: a pre-release plugin handles every incoming/outgoing file selection; an `+eol` package ships the native SQLite binaries and blocks the SQLCipher route (see SEC finding on DB encryption). One major behind: `go_router` 17 vs 18, `flutter_secure_storage` 10 vs 11 (holds the key store), `flutter_local_notifications` 21 vs 22.
- Fix: move `file_picker` to a stable 13.x after smoke-testing picking on Android and Windows; plan sqlite3 build-hooks migration with the DB encryption decision; defer other major bumps to the backlog.
- Effort: M

### ARCH-007 Lint set is only `flutter_lints`
- Severity: P3 | Confidence: High
- Location: `analysis_options.yaml:1-10`
- Evidence:
```
include: package:flutter_lints/flutter.yaml
errors: invalid_annotation_target: ignore
```
- Why it matters: 113 `catch (_)` and unawaited futures in call/transfer paths are not flagged; the codebase mixes swallowed errors with real handling.
- Fix: add under `linter: rules:` `unawaited_futures`, `avoid_catches_without_on_clauses`, `only_throw_errors`, `cancel_subscriptions`, `close_sinks`, `avoid_print`, `prefer_final_locals`; introduce them gradually (enable, then baseline ignores).
- Effort: M

## C. Signaling and session logic

Note: `firebase_adapter.dart` line numbers below are from `git show HEAD:...` (the working copy does not compile, GIT-001). The HEAD file is 3,046 lines.

FSM (`packages/protocol_brain/lib/src/voice_call_session.dart:1105-1150`, `_isAllowedTransition`; same-state is always allowed):

| From | Allowed next |
|---|---|
| idle | preflightingMic, incomingRinging, failed |
| preflightingMic | outgoingRinging, connectingMedia, failed, ending |
| outgoingRinging | creatingMedia, connectingMedia, failed, ending |
| incomingRinging | preflightingMic, failed, ending, idle |
| creatingMedia | connectingMedia, failed, ending |
| connectingMedia | creatingMedia, active, failed, ending |
| active | ending, failed |
| ending | idle, failed |
| failed | none (`_ => false`, strictly terminal, comment at :1148-1150) |

Timeout constants: ringing 45 s (`voice_call_session.dart:~38`, fires `_fail` without notifying the peer), answer 15 s (notifies peer), media/ICE 20 s (notifies peer), cleanup 5 s; call room `expiresAt` = 2 min (`voice_call_runtime.dart:71`, `_voiceCallExpiry`); legacy room TTL 15 min (`firebase_adapter.dart:241`); presence freshness 30 s (`firebase_adapter.dart:240`).

### SIG-001 Glare handled only by RTDB pair lock; local runtime has no tie-break and may answer "busy" to the winner
- Severity: P2 | Confidence: Low
- Location: `apps/rain/lib/application/runtime/voice_call/voice_call_preflight_coordinator.dart:185-188`, `apps/rain/lib/application/runtime/voice_call_runtime.dart:1098-1133`
- Evidence:
```
preflight_coordinator.dart:185  bool canReplaceVoiceCallWithRetry(VoiceCallState current) {
preflight_coordinator.dart:186    return !current.isOutgoing && current.phase == VoiceCallPhase.incomingRinging;
voice_call_runtime.dart:1128  if (!_canReplaceVoiceCallWithRetry(current)) { return _IncomingVoiceInviteDisposition.busy; }
```
- Why it matters: A and B call each other within the same second. Each runtime is in `outgoingRinging` with `peerId == other`, so the incoming invite is not replaceable and each side answers `busy` (`voice_call_runtime.dart:1128-1130`). If both invites cross before either lock write is rejected, both sides show "Peer is busy" and neither call connects. Mitigation observed: `activeVoicePairs/<pairId>` admits a single creator (rules write branch `!data.exists() && newData.exists()`, `backend/firebase/database.rules.json` near line 346; test `packages/protocol_brain/test/voice_signaling_contract_test.dart:107`), so normally the second `startOutgoing` fails and that side becomes `failed`, which `_prepareIncomingVoiceInvite` (`voice_call_runtime.dart:1117-1121`) replaces and accepts. The race window is the loser's phase before its failure arrives. The only deterministic ordering in the code is `isVoiceCallOfferOwner` (`voice_call_session.dart:1223`, lexicographic peer id), used only to choose who creates the SDP offer, not to resolve crossed invites. Grep for `glare|tieBreak|polite` over `lib/` finds nothing.
- Fix: in `_prepareIncomingVoiceInvite`, when `current.isOutgoing && current.peerId == normalizedPeerId` and the phase is `outgoingRinging` or `preflightingMic`, keep the call whose caller is the lower peer id (reuse `isVoiceCallOfferOwner`), hang up the other with a best-effort frame, and auto-accept the surviving invite. Add a runtime test with two crossed invites.
- Effort: M
- Confirm by: emulator test where both clients call `startCall` within 50 ms.

### SIG-002 ICE candidates received before negotiation phases are dropped at the session layer
- Severity: P2 | Confidence: Medium
- Location: `packages/protocol_brain/lib/src/voice_call_session.dart:602-625` (`_handleRemoteCandidate`)
- Evidence:
```
if (state.phase != creatingMedia && state.phase != connectingMedia && state.phase != active) {
  _logInvalidEvent('candidate frame in ${state.phase.name}');
  return;
}
```
- Why it matters: candidate frames are exempt from the ordered-seq check (`:820-840`), so a candidate can be processed while the session is still `outgoingRinging` or `preflightingMic` (for example while the `accept` frame is queued). Such candidates are discarded, not buffered. Media-level buffering exists (`call_media_connection.dart:88,416-417`, `voice_media_connection.dart:57,287-288`) but only covers candidates that reach `media.addRemoteCandidate`. Trickle ICE tolerates some loss; if the dropped candidates were the only srflx/relay ones the call hits the 20 s ICE timeout.
- Fix: keep a bounded session-level queue (for example 64) for candidates seen in `outgoingRinging`, `preflightingMic` or `incomingRinging`, flush it on entering `connectingMedia`, and drop it on `failed`/`idle`.
- Effort: S
- Confirm by: unit test feeding `candidate` before `accept` and asserting `media.addRemoteCandidate` runs after.

### SIG-003 In `rtdbOnly` mode connected or abandoned call rooms are never deleted
- Severity: P1 | Confidence: High
- Location: `firebase_adapter.dart:1120-1260` (HEAD, `cleanupStaleVoiceCallArtifacts`, esp. `:1213`), `backend/firebase/functions/index.js:11,55,93`, `apps/rain/lib/application/runtime/rain_runtime_controller.dart:806,2350`
- Evidence:
```
firebase_adapter.dart:1213  } else if (room.status != VoiceCallSignalingStatus.connected &&
firebase_adapter.dart:1214      room.expiresAt <= now) {
index.js:93  exports.cleanupVoiceCalls = onSchedule({ schedule: "every 5 minutes" ...   // needs Blaze
Grep onDisconnect: only presence (firebase_adapter.dart:2786); none for voiceCalls/*, activeVoiceUsers/*, activeVoicePairs/*
```
- Why it matters: client cleanup runs only at startup/resume (`rain_runtime_controller.dart:806`, `:2350`), only inspects the signed-in user's own `activeVoiceUsers/<name>` lock (so a callee's view after the caller's app was killed is not covered) and explicitly skips rooms in `connected` state. After an app kill or crash mid-call, the room, both locks and the inbox entry stay in RTDB until a Blaze function removes them. On Spark that is never: `voiceCalls/*`, `voiceCallInboxes/*`, `activeVoiceUsers/*` and `activeVoicePairs/*` accumulate against the 1 GB storage quota. Locks can be overwritten once `expiresAt <= now` (rules `activeVoiceUsers` write branch 2), so calls are not permanently blocked, but data is never reclaimed.
- Fix: (1) when a call starts, register `onDisconnect` handlers that mark the caller's `voiceCalls/<id>` as failed and remove the caller's locks, and cancel them on clean end; (2) in `cleanupStaleVoiceCallArtifacts` also treat `connected` rooms with `expiresAt <= now` as stale when the client is not in that call; (3) run the cleanup for the inbox when `watchIncomingVoiceCalls` starts.
- Effort: M

### SIG-004 On Blaze, `cleanupVoiceCalls` would delete live connected calls after the 2-minute room expiry
- Severity: P2 | Confidence: Low
- Location: `backend/firebase/functions/index.js:93-130`, `apps/rain/lib/application/runtime/voice_call_runtime.dart:71`
- Evidence:
```
index.js:100  root.child("voiceCalls").orderByChild("expiresAt").endAt(now).get()   // no status filter
voice_call_runtime.dart:71  static const Duration _voiceCallExpiry = Duration(minutes: 2);
```
- Why it matters: nothing found in `firebase_adapter.dart` extends `voiceCalls/<id>/expiresAt` after `markConnected` (`:1303-1326` updates only status, connectedAt, updatedAt). For a call longer than 2 minutes the room is expired; the scheduled function deletes it whatever its status, so hangup and mute frames sent afterwards fail and the peer only notices through media disconnect detection.
- Fix: refresh `expiresAt` in a periodic heartbeat while `connected`, or make the function skip `status == 'connected'` rooms with a recent `updatedAt`.
- Effort: S
- Confirm by: Blaze/emulator test with a 3-minute connected call, inspecting `voiceCalls/<id>` after the function run.

### SIG-005 Ringing timeout fails locally without notifying the peer
- Severity: P3 | Confidence: High
- Location: `packages/protocol_brain/lib/src/voice_call_session.dart:1155-1167`
- Evidence:
```
_ringingTimer = Timer(timeouts.ringing, () { unawaited(_enqueue(() => _fail('Call timed out while ringing.', reasonCode: ringingTimeout))) });
```
- Why it matters: `_fail` is called with default `notifyPeer: false`, unlike the answer and media timeouts. The callee relies on its own 45 s timer (armed in `_handleInvite`, `:422-434`), so a late-delivered invite keeps ringing after the caller gave up.
- Fix: pass `notifyPeer: true` (best-effort hangup) so the callee stops ringing immediately.
- Effort: S

### SIG-006 TASK-005 "watcher subscribed after startOutgoing" remains unverified
- Severity: P3 | Confidence: Low
- Location: `PROJECT_PROGRESS_TRACKER.md:65,84`
- Evidence:
```
BLOCKER-4 (TASK-005): "Watcher-before-startOutgoing" reorder REVERTED ... premise is UNVERIFIED
```
- Why it matters: if a callee answers within about 50 ms the `accept`/`answer` could land before the caller's watcher listens, leaving the caller in `outgoingRinging` until the 45 s timeout. No test proves it.
- Fix: none until reproduced; write the emulator test (see TEST findings) before changing order.
- Effort: M
- Confirm by: emulator test where the callee answers within 50 ms of room creation.

## D. WebRTC and transfer

Checked and found sound (no finding): `call_media_connection.dart` and `voice_media_connection.dart` close and dispose the peer connection, stop every local and remote track and dispose streams on every exit path, including a failed `getUserMedia` (`call_media_connection.dart:1010-1085`, `voice_media_connection.dart:163-200`, `:728-783`). File transfer streams from `File.openRead()` in 32 KiB chunks (`file_transfer_protocol.dart:8`, `file_transfer_runtime.dart:642-720`), never `readAsBytes`; max file is 100 MiB (`file_transfer_protocol.dart:7`, enforced by the receiver at `file_transfer_runtime.dart:208` and the sender at `rain_runtime_controller.dart:2125` and `chat_panel.dart:1178`); the receiver checks offsets, byte counts and size overflow (`:340-365`), verifies SHA-256 of the whole file (`:491-503`), and on mismatch or failure deletes the `.part` file (`markTransferFailed` -> `deleteTempFile`, `:1046-1160`). Platform branching is limited to `_windowsReleaseSafeIceServers` (`turn_credential_service.dart:276`).

### RTC-001 `DefaultPeerCore.destroy()` can skip closing the peer connection and never calls `dispose()`
- Severity: P2 | Confidence: Medium
- Location: `packages/peer_core/lib/src/default_peer_core.dart:164-193`
- Evidence:
```
try { await stopLocalAudio(); for (final channel in _channels.values.toList()) { await channel.close(); } } finally { _destroying = false; }
...
await _peerConnection?.close();      // reached only if the try block did not throw
_peerConnection = null;              // no _peerConnection.dispose()
```
- Why it matters: if `stopLocalAudio()` or one `channel.close()` throws, the exception leaves `destroy()` before `_peerConnection.close()` and the state reset, so the native peer connection stays alive and `init()` (which calls `destroy()` when `_peerConnection != null`, `:198-200`) throws again. Even on the happy path only `close()` is called; `flutter_webrtc` requires `dispose()` to release the native object, which the call/voice classes do (`call_media_connection.dart:1077-1083`) but this one does not.
- Fix: wrap each step in its own try/catch, always run `close()`, `dispose()` and the field resets in a `finally`, and rethrow the first error after cleanup.
- Effort: S

### RTC-002 Backpressure wait ignores channel close and polls
- Severity: P2 | Confidence: Medium
- Location: `packages/peer_core/lib/src/data_channel_backpressure.dart:28-40`
- Evidence:
```
while ((channel.bufferedAmount ?? 0) > lowWatermarkBytes) {
  if (stopwatch.elapsed > timeout) { throw TimeoutException(...); }
  await Future<void>.delayed(pollInterval);   // 20 ms poll, 10 s timeout, no channel.state check
```
- Why it matters: if the channel closes or the peer disappears while the buffer is above the high watermark (1 MiB), `bufferedAmount` stays flat and the sender spins every 20 ms for 10 s before failing with a generic `TimeoutException`, so a dropped transfer takes 10 s to be noticed and the error is not a "channel closed" error. `bufferedAmountLowThreshold`/`onBufferedAmountLow` is not used.
- Fix: break out with a `StateError('channel closed')` when `channel.state != RTCDataChannelOpen`, and prefer `channel.bufferedAmountLowThreshold = lowWatermarkBytes` with `onBufferedAmountLow` completing a `Completer`.
- Effort: S

### RTC-003 Default ICE configuration relays through a public shared TURN account
- Severity: P2 | Confidence: High
- Location: `apps/rain/lib/core/config/app_environment.dart:618-629`, `:127-134`
- Evidence:
```
'turn:openrelay.metered.ca:80?transport=udp', ... 'turns:openrelay.metered.ca:443?transport=tcp'
'username': 'openrelayproject', 'credential': 'openrelayproject'
RAIN_ICE_SERVERS read via String.fromEnvironment (compile-time)
```
- Why it matters: when `RAIN_ICE_SERVERS` is empty the app uses a free public TURN service with a published shared credential. It has no SLA or quota guarantees for Rain, so calls behind symmetric NAT can silently fail, and relayed traffic goes through a third party (media stays DTLS-SRTP encrypted, but metadata and IPs are visible to it). Any value that is supplied through `RAIN_ICE_SERVERS` is compiled into the binary, so a private TURN username and credential would be extractable from the APK or EXE; the safer path (`turn_credential_service.dart` broker with short-lived credentials, TTL default 1200 s at `:200`) exists but depends on a broker URL.
- Fix: make the broker the production source (fail visibly if absent in release), keep the public relay only for debug builds, and never place long-lived TURN credentials in `RAIN_ICE_SERVERS`.
- Effort: M

### RTC-004 No resume and no free-disk check for file transfers
- Severity: P3 | Confidence: High
- Location: `apps/rain/lib/application/runtime/file_transfer_runtime.dart:1046-1060`, `:1114-1119`
- Evidence:
```
await deleteTempFile(transfer);   // markTransferFailed: partial data is discarded
if (await tempFile.exists()) { await tempFile.delete(); }   // before each receive
```
- Why it matters: any disconnect on a 100 MiB file restarts the transfer from byte 0, and the receiver accepts an offer without checking available disk space, so a full disk shows up only as a write failure mid-transfer (`'Could not write received file chunk.'`).
- Fix: backlog; keep `.part` files with persisted offsets and add a `resume_from` field in the accept frame, check free space before accepting.
- Effort: L

## E. Security and crypto

Rules trace, no finding (read from `backend/firebase/database.rules.json`, evaluated with a Node script, not an emulator):
- Authenticity of rooms: `rooms/$roomId` create requires `root.child('users/' + newData.child('userA').val() + '/uid').val() === auth.uid` and `userA < userB` and `userA:userB === $roomId`; update and delete require `auth.uid` to equal `userA` or `userB`. Sub-nodes: `offer` writable only by `userA`'s uid, `answer` only by `userB`'s uid, `callerICE`/`calleeICE` likewise. A third user cannot write into the room of B and C. Same pattern for `voiceCalls/$callId` (`offer` requires the caller uid and status `accepted|negotiating`; `answer` requires the callee uid and status `negotiating`), `activeVoicePairs` and `activeVoiceUsers`.
- Identity binding: `users/$username` `.write` requires `auth.token.email === $username + '@rain.local'` and either a new row with `uid === auth.uid` or an existing row whose `uid` already equals `auth.uid` (and cannot change). `userSearch/$username` and `presence/$username` require `root.child('users/' + $username + '/uid').val() === auth.uid`. Overwriting another user's row is not possible.
- Validation: SDP and ICE fields have `v`, `alg === 'A256GCM-HKDF-SHA256'`, `from`/`to` bound to `userA`/`userB`, `nonce <= 96`, `ciphertext <= 262144` (SDP) and `mac <= 96`; 24 `length` checks in `rooms`, 28 in `voiceCalls`. `users/$username` has `$other: .validate false`.
- Sanitizer (`apps/rain/lib/infrastructure/services/diagnostics_sanitizer.dart:10-60`) redacts SDP markers, `candidate:` lines, `password|token|secret|credential|api_key|authorization` assignments, bearer tokens, file paths, Firebase paths and emails; no raw logging of SDP/candidate/password found by Grep.
- Remote Config (`backend/firebase/remoteconfig.template.json`) holds only `rain_release_manifest_v1`, `min_required_version`, `update_url`; no key can disable encryption.

### SEC-001 New registrations write `users/<name>/signingPublicKey`, which the rules reject
- Severity: P1 | Confidence: Medium
- Location: `apps/rain/lib/application/state/identity_providers.dart:136-146`, `packages/protocol_brain/lib/adapters/firebase_adapter.dart:265-277` (HEAD), `backend/firebase/database.rules.json` (`users/$username/$other`)
- Evidence:
```
identity_providers.dart:144  await adapter.publishIdentitySigningKey(username: username, signingPublicKey: ...)
firebase_adapter.dart:274    await _root.child('users/$normalized/signingPublicKey').set(signingPublicKey);
rules: users/$username children = username, uid, displayName, gender, registeredAt, accountState, deletedAt, $other{.validate:false}; "signingPublicKey" does not occur in the file; git log -S finds no commit that ever added it
```
- Why it matters: if the deployed rules equal the repo rules, every new sign-up creates the Firebase Auth account, then the key write is rejected with permission denied, the catch only calls `adapter.signOut()` (`identity_providers.dart:158-166`) and rethrows. The Auth user is never deleted (compare `_rollbackNewlyCreatedAuthUser` in the adapter's own `register`, which is not used here), so the username is permanently taken with no `users/` row. The adapter comment "RTDB rules enforce that only the matching auth uid may write this node" is not backed by any rule. There is no rules test (see BE-001) to catch this.
- Fix: add `signingPublicKey` to `users/$username` rules (`.validate`: string, base64, length 44, writable only when `root.child('users/'+$username+'/uid').val() === auth.uid`, immutable once set unless an explicit rotate flag), add a rules test, and in `identity_providers.dart` roll back the Auth user (delete) when `publishIdentitySigningKey` fails.
- Effort: M
- Confirm by: emulator rules test writing `users/alice/signingPublicKey` as alice's uid.

### SEC-002 Per-pair E2E signaling (v=2) is implemented but not wired; signaling uses one shared compile-time key
- Severity: P2 | Confidence: High
- Location: `apps/rain/lib/application/bootstrap/app_bootstrap.dart:78-86`, `apps/rain/lib/application/state/runtime_providers.dart:543-545`, `apps/rain/lib/core/config/app_environment.dart:137-146,241-246,615`, `packages/protocol_brain/lib/adapters/firebase_adapter.dart:29-38,130-150,153-170` (HEAD)
- Evidence:
```
app_bootstrap.dart:78  final signalingCipher = SignalingCipher.fromKeyMaterial(effectiveEnvironment.signalingEncryptionKey);
app_bootstrap.dart:83  FirebaseSignalingAdapter(database: firebaseDatabase!, signalingCipher: signalingCipher)   // no pairCipherResolver
Grep "pairCipherResolver|SignalingCipherResolver" in apps/rain/lib -> 0 matches
app_environment.dart:615  const demoSignalingEncryptionKey = 'rain-demo-signaling-encryption-key-v1-change-me';
```
- Why it matters: `FirebaseSignalingAdapter._resolvePairCipher` returns null without a resolver, so `_encryptSignalingPayload` always takes the v=1 path. v=1 derives keys from one root key supplied via `RAIN_SIGNALING_ENCRYPTION_KEY` (a `--dart-define`, compiled into every installed binary and identical for all users; `AppEnvironment.validateForRelease` only requires it to be non-demo, `:410-430`). Anyone with the app can decrypt any signaling envelope they can read, so v=1 gives no confidentiality against a database operator or backup reader and the "E2E" claim in the tracker is not true of the shipped path. Demo channel builds may ship the public demo key. Media itself is DTLS-SRTP and chat messages go over the P2P data channel, so exposure is limited to SDP/ICE (IP addresses, DTLS fingerprints) and their integrity; the rules in the trace above remain the real access control.
- Fix: after SEC-001 is fixed, pass a `SignalingCipherResolver` built from `IdentityKeyRepository.derivePairKeyMaterial` and a peer-key lookup (`users/<peer>/signingPublicKey`) in `app_bootstrap.dart`; keep v=1 decode support for one release (decode-only), then drop v=1 encrypt. Document that v=1 is obfuscation, not confidentiality.
- Effort: L

### SEC-003 Local database is stored in plaintext; the DB key is generated but never used
- Severity: P1 | Confidence: High
- Location: `packages/rain_core/lib/database/rain_database.dart:358-405` (`openEncryptedRainDatabase`), `packages/rain_core/lib/database/database_key_service.dart:18-45`, `apps/rain/lib/application/bootstrap/app_bootstrap.dart:49-56`, `pubspec.lock:1287-1302`
- Evidence:
```
rain_database.dart:394  db.execute("PRAGMA key = \"x'$hex'\";");   // unknown PRAGMA is ignored by stock SQLite; wrapped in try/catch
rain_database.dart:401  // Not a SQLCipher build - continue with plaintext. (inner probe catch at :397-399 is empty)
pubspec.lock  sqlite3 3.3.1 (default source), sqlite3_flutter_libs 0.6.0+eol
```
- Why it matters: message history, friends and file metadata sit unencrypted in the Drift file (Android app data dir, Windows user profile). A stock SQLite build silently ignores `PRAGMA key`, so nothing is encrypted yet the keystore holds a "DB key" that suggests otherwise. Latent data-loss: `DatabaseKeyService.ensureDatabaseKey` regenerates a new key when the keystore returns null (`:26-33`), and `openEncryptedRainDatabase` falls back to a fresh `RainDatabase()` on any error; once a real SQLCipher build is introduced, a keystore reset would orphan an encrypted file, and an existing plaintext file would fail to open with "file is not a database" because no migration exists.
- Decision options:
  - (a) `sqlite3` >= 3.x with the SQLCipher source selected through build hooks. Confirmed with Context7 (`/simolus3/sqlite3.dart`, `UPGRADING_TO_V3.md` and `sqlite3/doc/hook.md`): add `hooks: user_defines: sqlite3: source: sqlcipher` (or `sqlite3mc`) to the pubspec and drop `sqlite3_flutter_libs`/`sqlcipher_flutter_libs`. The lockfile already has sqlite3 3.3.1, so hooks are available. Cost: native build on Android/Windows must be verified (R7 forbids builds in this program), plus a one-time plaintext-to-cipher migration (`sqlcipher_export` or `ATTACH ... KEY`) and a version marker file.
  - (b) Application-level AES-GCM on message bodies (`cryptography`, already a dependency) with the existing DB key. No native change, works with the current build, but metadata (peers, timestamps, file names) and search remain plaintext.
  - (c) Keep plaintext and document it as an accepted risk, with OS disk encryption as the control.
  - Recommendation: (a) as the target, shipped behind a verified migration; do (b) only if (a) cannot be built on Windows. Until then record (c) in the risk register and remove the misleading "encrypted open" wording. Decision recorded as ADR-012 in Phase 2.
- Fix: implement the chosen option; in the interim make `openEncryptedRainDatabase` log an event `db_encryption_inactive` and never regenerate a key when a database file already exists.
- Effort: L

### SEC-004 Android auto-backup is not disabled
- Severity: P2 | Confidence: High
- Location: `apps/rain/android/app/src/main/AndroidManifest.xml:12-16`
- Evidence:
```
<application android:label="Rain" android:name="${applicationName}" android:icon="@mipmap/ic_launcher">   # no allowBackup, dataExtractionRules or fullBackupContent
```
- Why it matters: `android:allowBackup` defaults to true, so the plaintext Drift database (SEC-003) can be uploaded to Google Drive backups and restored on another device without the keystore, leaving a database whose key is gone. `usesCleartextTraffic` is not set (default false for targetSdk >= 28) and only `MainActivity` is exported, both fine. Permissions: INTERNET, ACCESS_NETWORK_STATE, CHANGE_NETWORK_STATE, MODIFY_AUDIO_SETTINGS, RECORD_AUDIO, CAMERA, POST_NOTIFICATIONS; no FOREGROUND_SERVICE (see APP findings).
- Fix: set `android:allowBackup="false"` and `android:dataExtractionRules` excluding the database and secure-storage files.
- Effort: S

### SEC-005 `ensureKeyPair` trusts the database public key without checking the private key
- Severity: P2 | Confidence: Medium
- Location: `packages/rain_core/lib/identity/identity_key_repository.dart:25-40`, `apps/rain/lib/infrastructure/security/flutter_secure_storage_key_store_service.dart:21-27`
- Evidence:
```
final existing = await _readPublicKey();
if (existing != null) { return existing; }       // private key in the keystore is never verified
```
- Why it matters: if the keystore entry is lost (Windows profile reset, Android backup restore, `flutter_secure_storage` major upgrade, or an uncaught non-`PlatformException`), `ensureKeyPair` still returns the old public key. The peer then derives ECDH with a key whose private half no longer exists, and `getPrivateKeyBytes` throws on every call, so per-pair encryption fails permanently with no regeneration path. The key store only maps `PlatformException` to `KeyStoreException` (`:21-27`), so other failures surface as raw exceptions. On Windows `flutter_secure_storage` uses a DPAPI-protected file (documented as non-TPM in the file header).
- Fix: in `ensureKeyPair`, if the DB public key exists but `_store.read(_storeId)` is null, regenerate the pair and republish; wrap all `catch` types in `KeyStoreException`.
- Effort: S

### SEC-006 `userSearch` can be listed by any signed-in account and sign-up is open, without App Check
- Severity: P2 | Confidence: Medium
- Location: `backend/firebase/database.rules.json` (`userSearch.".read": "auth != null"`), `apps/rain/pubspec.yaml`, `backend/firebase/firebase.json`
- Evidence:
```
userSearch: { ".read": "auth != null", "$username": { ".write": "... users/$username/uid === auth.uid ..." } }
Grep -i "app_check|appcheck" in pubspecs, lib/ and firebase.json -> 0 matches
```
- Why it matters: anyone can create a Firebase Auth account (`<name>@rain.local` e-mail/password, API key is public) and download the full list of usernames and display names, and `users/<name>` rows (uid, gender, registeredAt) and `presence/<name>` (platform, online state) for any known username. Without App Check, scripts rather than the app can also create accounts and consume Spark RTDB quota. Chat content is not in RTDB, so this is a privacy and abuse issue, not a content leak.
- Fix: restrict `userSearch` listing with `.indexOn` plus `orderByKey().startAt().limitToFirst(20)` constraints enforced by query-based rules (`query.limitToFirst <= 20`), add App Check (Play Integrity / debug provider; Windows has no provider, so enforce monitoring-only there), and treat per-IP sign-up throttling in the Auth console as an owner action.
- Effort: M
- Confirm by: emulator test reading `userSearch` as a fresh account.

### SEC-007 Update URL from Remote Config is opened without a scheme or host check
- Severity: P2 | Confidence: Medium
- Location: `apps/rain/lib/infrastructure/services/force_update_service.dart:84,293-295,323`, `apps/rain/lib/presentation/screens/root_screen.dart:61`, `apps/rain/lib/presentation/screens/settings_screen.dart:908,921`, `apps/rain/lib/presentation/screens/startup_surface.dart:117`
- Evidence:
```
force_update_service.dart:84  updateUrl: _optionalString(json['updateUrl']) ?? fallbackUpdateUrl,
root_screen.dart:61  onUpdate: () => unawaited(launchUrlString(updateResult.updateUrl)),
```
- Why it matters: whoever can publish the Remote Config template (or tamper with a cached copy) can send every client to an arbitrary `http(s)` or custom-scheme URL from a trusted "Update required" screen. The force-update gate also blocks use of the app, so it is a phishing vector.
- Fix: parse with `Uri.tryParse`, require `https` and an allow-listed host (`github.com`, `AbdogadXNabawy`/`EslamNabawy` release paths), else fall back to the compiled `RAIN_UPDATE_URL`.
- Effort: S

## F. App layer

Checked and found sound (no finding): router redirect sends any non-ready startup state to `/` for protected paths (`apps/rain/lib/presentation/navigation/app_routes.dart:~118-127`, `appStartupRedirectForPath`); no deep-link intent filters exist in `AndroidManifest.xml`, so deep-link handling is out of scope. Stream-subscribing notifiers cancel on dispose (`runtime_providers.dart:120,335,714,743,908,1038`, `messaging_providers.dart:74,239`).

### APP-001 Backgrounding marks the user offline mid-call and there is no Android foreground service
- Severity: P1 | Confidence: Medium
- Location: `apps/rain/lib/application/runtime/rain_runtime_controller.dart:2357-2366`, `apps/rain/lib/application/state/runtime_providers.dart:68-75`, `apps/rain/lib/infrastructure/services/app_settings_store.dart:163-169`, `apps/rain/android/app/src/main/AndroidManifest.xml:4-10`
- Evidence:
```
rain_runtime_controller.dart:2360  case AppLifecycleState.hidden: case AppLifecycleState.paused:
rain_runtime_controller.dart:2362    _presenceHeartbeatPaused = true;  ... _setPresenceOfflineSafely('app_${state.name}');   // no check for an active call or transfer
runtime_providers.dart:71  await BackgroundServices.instance.stop(); return false;      // background service is forced off
Grep "foregroundService|FOREGROUND_SERVICE" in android/ and lib/ -> 0 source matches
```
- Why it matters: when the Android app is backgrounded, or the Windows window is minimized (`hidden`), presence is set offline immediately even while a voice call or file transfer is active; the peer's UI then shows the user offline and presence-gated actions fail (call creation rules require `presence/<callee>/online === true`). On Android 11+ capturing the microphone in the background requires a foreground service of type `microphone`; none is declared, so an audio call is expected to lose mic input or be killed shortly after the user switches apps. Only video calls are explicitly ended on pause (`voice_call_media_coordinator.dart:297-335`).
- Fix: skip `_setPresenceOfflineSafely` while `voiceCallState.hasCall` or an active file transfer exists; add a call-scoped Android foreground service (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `foregroundServiceType="microphone"`) started in `startOutgoing`/`acceptIncoming` and stopped on end. Needs device verification (R7, owner action).
- Effort: L
- Confirm by: Android 13+ device, start an audio call, press Home for 60 s.

### APP-002 Call-expiry check treats a network error as "not expired"
- Severity: P2 | Confidence: Medium
- Location: `apps/rain/lib/application/runtime/voice_call_runtime.dart:316-340` (`_isExpiredVoiceCallStartBlock`)
- Evidence:
```
try { final room = await voiceAdapter.fetchCall(callId); ... return room.expiresAt <= now; } catch (_) { return false; }
```
- Why it matters: when `fetchCall` fails (offline, permission denied, timeout) the stale call state that blocks new calls is reported as still valid, so the user stays stuck in "busy" until the network recovers, with no log entry. The fallback branch right below uses the local epoch plus 2 minutes, which would have cleared it.
- Fix: on error, fall through to the local `sessionEpoch + _voiceCallExpiry` check and record a runtime event.
- Effort: S

### APP-003 `failActiveTransfersForPeer` swallows a store read error and leaves transfers active
- Severity: P2 | Confidence: Medium
- Location: `apps/rain/lib/application/runtime/file_transfer_runtime.dart:1073-1088`
- Evidence:
```
try { active = await fileTransferStore.loadActiveTransfers(peerId: peerId); } catch (_) { return; }
...
try { await markTransferFailed(transfer.id, reason); } catch (_) { /* best effort */ }
```
- Why it matters: this is the cleanup run on disconnect, friend removal and shutdown. If the DB read or a single `markTransferFailed` throws, the transfer rows stay in `receiving`/`offered`, and `hasActiveTransferForPeer` (`:200`, offer handler) then rejects every new file from that peer with "Finish the active file transfer first" until the app restarts or the rows are cleaned by hand. Nothing is recorded.
- Fix: log through `recordRuntimeEvent` with severity warning and `errorRecorder`; on shutdown path, schedule a retry on next start (`loadActiveTransfers` -> mark failed) as part of runtime start.
- Effort: S

### APP-004 `brain!` is dereferenced after long awaits in the transfer loop
- Severity: P3 | Confidence: Low
- Location: `apps/rain/lib/application/runtime/file_transfer_runtime.dart:715,762,793,838,1019,1026,1040`
- Evidence:
```
await for (final bytes in openRead()) { ... await _sendFileChunk(...) }   // seconds to minutes
brain!.send(peerId, SessionChannel.file, FileTransferFrame.complete(...)) // :715
```
- Why it matters: `brain` is a mutable field that is nulled during logout/shutdown; a transfer in flight then fails with `Null check operator used on a null value`, which surfaces as an unclassified error instead of "Transfer canceled". The outer `try` records a generic failure, so impact is a misleading message, not a crash. Counts of `!` in the two large files are 27 (`voice_call_runtime.dart`) and 19 (`rain_runtime_controller.dart`); the ones checked right after a null test (`current.callId!` after `current.callId == null` guards) are safe.
- Fix: read `final activeBrain = brain; if (activeBrain == null) throw StateError('Transfer canceled.')` once per chunk.
- Effort: S

### APP-005 `brainProvider` and `appRouterProvider` do not dispose what they create
- Severity: P3 | Confidence: Low
- Location: `apps/rain/lib/application/state/runtime_providers.dart:171-215`, `apps/rain/lib/presentation/navigation/app_routes.dart:39-43`
- Evidence:
```
final brain = createDefaultProtocolBrain(...); return brain;      // no ref.onDispose
return GoRouter(refreshListenable: refreshListenable, ...);       // router.dispose() never registered
```
- Why it matters: `SessionManager` has no `dispose` method (`session_manager.dart` has none; the runtime tears sessions down in `_shutdown`), so a session change relies entirely on the runtime shutdown path; `GoRouter` holds listeners until process exit. Low impact today because both providers live for the process, but a second account switch in one process would reuse stale state.
- Fix: add `SessionManager.dispose()` that closes all peers and register it with `ref.onDispose`; register `router.dispose`.
- Effort: S

## G. Storage

Checked and found sound (no finding): all single-store writes in `message_store.dart`, `friend_store.dart`, `file_transfer_store.dart`, `offline_queue.dart` and `identity.dart` run inside `serializedTransaction` (`rain_database.dart:293-302`, busy/locked retry with backoff, `:305-330`); schema v6 adds explicit indexes `messages(peer_id, sent_at, seq, id)`, `friends(display_name)`, `queued_messages("to", status, seq, sent_at)` and `(status, "to")`, `file_transfers(peer_id, created_at)`, `(message_id)`, `(state, peer_id)` (`rain_database.dart:204-240`).

### DB-001 Migration steps 3->4, 4->5 and 6->7 have no test; `from < 5` is unguarded
- Severity: P2 | Confidence: High
- Location: `packages/rain_core/lib/database/rain_database.dart:143,170-198`, `packages/rain_core/test/rain_database_test.dart:87,176`
- Evidence:
```
rain_database.dart:143  int get schemaVersion => 7;
rain_database.dart:180  if (from < 5) { await m.createTable(fileTransfers); }      // no _hasTable guard, unlike the other steps
rain_database_test.dart:111 PRAGMA user_version = 2;   :190 PRAGMA user_version = 5;   // only these two legacy fixtures
```
- Why it matters: only "v2 skips existing column" and "v5 creates indexes" are exercised. The `signingPublicKey` column (v7, `:190-192`) is added to every existing install on first run of the new build and has no upgrade test; `m.createTable(fileTransfers)` throws "table already exists" if a previous run died after creating the table but before bumping `user_version`. A failing `onUpgrade` blocks startup (see DB-003).
- Fix: add tests for upgrades 2->7, 4->5, 6->7 using `PRAGMA user_version` fixtures, and guard `createTable(fileTransfers)` with `!await _hasTable('file_transfers')`.
- Effort: S

### DB-002 Message, file-transfer and unread-counter writes are separate transactions
- Severity: P2 | Confidence: High
- Location: `apps/rain/lib/application/runtime/file_transfer_runtime.dart:262-288`, `:1058-1070`, `apps/rain/lib/application/runtime/serialized_runtime_mutations.dart:1-9`
- Evidence:
```
await localMutations.run(() async {
  if (!await messageStore.containsMessage(messageId)) {
    await messageStore.forceStoreIncomingEnvelope(...);  await friendStore.incrementUnread(peerId);
  }
  await fileTransferStore.upsert(FileTransferRecord(...));
});
serialized_runtime_mutations.dart:5  final next = _tail.catchError((_) {}).then((_) => action());   // a Future FIFO, not a DB transaction
```
- Why it matters: `localMutations.run` only orders callbacks; each store call opens its own SQLite transaction. If the app is killed or `upsert` throws between them, the chat shows a file message with no `file_transfers` row (the bubble cannot accept or fail) and the unread counter was already incremented; on retry `containsMessage` is true, so unread is not double counted but the transfer row is still created, so only the first crash leaves an inconsistent state. The same pattern appears in `markTransferFailed` (`:1058-1070`): `markState(failed)` then `markMessageStatus(failed)`.
- Fix: add `RainDatabase.serializedTransaction` wrappers in a single `FileTransferStore.recordIncomingOffer(...)` / `failTransfer(...)` method that touches all three tables in one transaction.
- Effort: M

### DB-003 A foreign-key check failure or failed upgrade blocks startup with no recovery
- Severity: P2 | Confidence: Medium
- Location: `packages/rain_core/lib/database/rain_database.dart:156-168`, `apps/rain/lib/application/bootstrap/app_bootstrap.dart:49-56`
- Evidence:
```
beforeOpen: ... if (fkViolations.isNotEmpty) { throw StateError('Rain database has N foreign-key violation(s). ... clear app data to rebuild it.'); }
app_bootstrap.dart:54  } catch (_) { database = RainDatabase(); }      // fallback hits the same beforeOpen and throws again
```
- Why it matters: any FK violation (for example a deleted message with a leftover transfer row after DB-002) throws on every launch; the only remedy shown is for the user to clear app data, which also loses the identity and chat history. The bootstrap fallback retries the same file, so it cannot recover.
- Fix: on `StateError` from `beforeOpen`, quarantine the file (rename to `rain.corrupt-<ts>.sqlite`), create a fresh database, and surface a "history could not be restored" notice; repair violating rows with `DELETE` of orphans before failing.
- Effort: M

### DB-004 No pruning of terminal transfer rows, failed queue entries or connection memory
- Severity: P3 | Confidence: Medium
- Location: `packages/rain_core/lib/database/rain_database.dart` (tables), Grep `prune|retention|deleteOlder` in `packages/rain_core/lib` -> 0 matches
- Evidence:
```
Only deletes: clearSessionData (:253-259), per-peer friend removal (friend_store.dart:122,163), offline_queue.dart:147, connection memory delete(peerId)
```
- Why it matters: `file_transfers` terminal rows (completed/failed/canceled), `queued_messages` with failed status and `message_seq_tracker` grow for the life of the install. At chat scale this is small, but nothing bounds it and diagnostics tables (if any) share the same file.
- Fix: add `pruneTerminalTransfers(olderThan: 90 days)` and cap failed queue rows at start-up.
- Effort: S
