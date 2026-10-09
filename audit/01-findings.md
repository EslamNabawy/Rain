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
