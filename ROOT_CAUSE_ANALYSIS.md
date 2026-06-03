# Rain Root Cause Analysis

Date: 2026-06-03

## Scope

This RCA is based only on the evidence supplied with the request and the directly referenced code paths. It does not claim a fix has been made.

Authoritative evidence reviewed:

- `C:\Users\eslam\OneDrive\Desktop\rain-diagnostics-2026-06-03T052607-406986Z.json`
- `C:\Users\eslam\.codex\attachments\ab414e03-67bc-4056-b94e-6e9b0cb40f14\pasted-text.txt`
- `C:\Users\eslam\OneDrive\Desktop\unnamed.jpg`
- Source paths named by stack traces and diagnostics:
  - `apps/rain/lib/application/runtime/voice_call_runtime.dart`
  - `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
  - `backend/firebase/database.rules.json`
  - `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart`
  - `backend/firebase/remoteconfig.template.json`

No remediation was proposed before reviewing these artifacts.

## Implementation Status

Completed mitigations from this RCA:

- 2026-06-03: Late voice signaling frames after terminal Firebase rooms are now recorded as structured `late_frame_ignored` runtime events only, not as crash/error records.
- 2026-06-03: Firebase `endCall` terminal room writes are independent from callee inbox mirror rows. A new emulator regression proves an already-cleaned `voiceCallInboxes/{callee}/{callId}` row no longer causes permission denied or prevents lock release.
- 2026-06-03: Android diagnostics export no longer treats SAF `/document/...` or `/tree/...` handles as raw filesystem paths. A regression proves `/document/1282` can be returned by the picker without causing `PathNotFoundException`.

Remaining evidence-backed repairs:

- Complete terminal-state reconciliation coverage for all voice/video runtime paths.
- Unify presence availability decisions.
- Fix update metadata/build-number validation.

## Evidence Summary

### Diagnostic JSON

Export:

- Export time: `2026-06-03T05:26:07.406986Z`
- Platform: Windows
- App version: `1.0.6`
- Build: `7`
- Update status: `current`
- Channel: `demo`
- Peer under investigation: `khara1`
- Local user: `khara2`

Important diagnostic facts:

- `lastCrash.source`: `voice-call-signaling`
- `lastCrash.fatal`: `false`
- `lastCrash.error`: `Bad state: Ignored late voice signaling for khara1:khara2:hj4dy036vl/1780464162430: ignored failed state after terminal room`
- Stack trace enters:
  - `VoiceCallRuntime._recordLateVoiceFrame`
  - `VoiceCallRuntime._applyVoiceSessionState`
  - `VoiceCallSession._fail`
  - `VoiceCallSession.acceptIncoming`
  - `VoiceCallRuntime.acceptVoiceCall`
- Four call summaries exist:
  - `khara1:khara2:hj4dy036vl`
  - `khara1:khara2:hj4dyg6s6q`
  - `khara1:khara2:hj4dynm7v8`
  - `khara1:khara2:hj4dz5u2r1`
- Every call summary has:
  - `roomStatusTimeline: []`
  - `iceCandidateWriteCount: 0`
  - `iceCandidateReadCount: 0`
  - `relayFallbackAttempted: false`

Interpretation:

- These captured failures did not reach a healthy ICE exchange.
- The primary captured failure is before successful WebRTC media negotiation.
- NAT/TURN may still be a future risk, but this evidence points first to signaling, presence, terminal cleanup, and lifecycle races.

Diagnostics quality gaps:

- `failureTaxonomy` is empty.
- `firebaseCostCounters` are zero even though network operations were recorded.
- There is only one WebRTC event in the export, and it is a disposed media-state event.
- There is no room-status timeline even though terminal inbox entries were observed.

### Screenshot

Screenshot path:

- `C:\Users\eslam\OneDrive\Desktop\unnamed.jpg`

Visible state:

- Screen: Android Settings.
- Device time: 8:26.
- App: `Rain 1.0.6`
- Build: `1007`
- Platform/channel: `android | demo`
- Update UI says: `Rain is up to date`
- Last Flutter error:
  - Time: `2026-06-03 08:24`
  - Source: `signaling.endCall`
  - Error: `[firebase_database/unknown] Firebase Database error: Permission denied`
- Diagnostics export failure snackbar:
  - `Could not export diagnostics: PathNotFoundException: Cannot open file, path = '/document/1282' (OS Error: No such file or directory, errno = 2)`

Interpretation:

- Android failed to write the end-call terminal state or associated cleanup path.
- The diagnostics export path handling is broken for Android picker output returning `/document/1282`.
- Android reports build `1007`, while Windows JSON reports build `7`, and the checked-in Remote Config template declares Android demo `latestBuild: 7`.

### Pasted Manual Failure Report

The pasted report states repeated manual failures:

- Presence stale until restart.
- One device shows connected while the other shows connecting.
- Peer appears online but direct connect does not start or notification request becomes required.
- Voice calls fail, stick, or clean up incompletely.
- Video calls fail or hang.
- Camera remains active after ending video.
- Outdated clients are not notified.

Interpretation:

- These are real observed symptoms, but not all are directly proven by the single JSON export.
- The JSON and screenshot prove root causes for presence oscillation, call terminal signaling races, Firebase end-call permission denial, stale terminal inbox cleanup, diagnostics export failure, and update/build metadata inconsistency.
- Camera resource leakage is reported and serious, but this diagnostic export does not contain enough media-track lifecycle data to prove the exact leak path.

## Failure Timeline

### Timeline A: Windows voice signaling terminal race

1. Initial state
   - Local user `khara2` is running Rain on Windows.
   - Peer `khara1` has prior call artifacts.

2. Trigger
   - Incoming call flow reaches `VoiceCallRuntime.acceptVoiceCall`.
   - The session later emits a failed state.

3. State transitions
   - Call id: `khara1:khara2:hj4dy036vl`.
   - Created at: `2026-06-03T05:22:42.430Z`.
   - Runtime receives or has already latched a terminal room state.
   - `VoiceCallSession._fail` emits a non-idle state after the room is terminal.

4. Error
   - At `2026-06-03T05:23:15.367991Z`, diagnostics record:
     - `Bad state: Ignored late voice signaling... ignored failed state after terminal room`
   - Code path:
     - `voice_call_runtime.dart:2188-2194` detects terminal-latched session state.
     - `voice_call_runtime.dart:4130-4151` records a late frame and sends it to `errorRecorder`.

5. Recovery attempt
   - Runtime logs the late frame as ignored.
   - However, because it is also sent to `errorRecorder`, it becomes the visible last crash/error.

6. Final state
   - The UI can be idle while diagnostics show a call-signaling error.
   - This proves active runtime state and diagnostic severity/state are not aligned.

Divergence from expected behavior:

- A late frame after terminal cleanup should be diagnostic-only call noise.
- It should not become the primary "last crash" shown to the user.

### Timeline B: Failed video/call UI cleared before session evidence is complete

1. Initial state
   - Call state is failed for `khara2:khara1:hj4dzua3cv`.

2. Trigger
   - At `2026-06-03T05:24:40.787467Z`, provider state changes.

3. State transitions
   - `VoiceCallController` changes from:
     - peer `khara1`
     - call `khara2:khara1:hj4dzua3cv`
     - phase `failed`
   - to:
     - phase `idle`
   - `VideoCallRenderers` had a previous renderer state.
   - `CallSurfaceState` clears.

4. Final state
   - UI state is cleared.

Divergence from expected behavior:

- There is no matching call setup timeline, no room status timeline, and no ICE timeline.
- The UI cleared the failure without enough retained evidence to classify whether the cause was permission, Firebase, SDP, ICE, media capture, renderer, or terminal cleanup.

### Timeline C: Presence oscillation and connection teardown

1. Initial state
   - Local user `khara2` is running.
   - Peer `khara1` is watched through Firebase presence.

2. Trigger and transitions
   - `2026-06-03T05:24:43.418Z`: `watchPresence(khara1)` emits `online: true`.
   - `2026-06-03T05:24:49.127Z`: `presence_session_expired` fires for `khara1`.
   - Runtime logs:
     - `end_for_peer_requested`
     - message `Peer closed Rain. Connection ended.`
     - phase `idle`
     - failure reason `networkLost`
   - Connection logs:
     - `brain_disconnect_requested`
     - intent `presenceExpired`
     - `peer_disconnected`

3. Repetition
   - Similar online/expired cycles repeat around:
     - `05:24:53` -> `05:24:59`
     - `05:25:50` -> `05:25:58`
     - `05:26:02` -> `05:26:03`

4. Critical contradiction
   - `2026-06-03T05:26:03.505Z`: `fetchIdentity(khara1)` returns:
     - `online: true`
     - `lastHeartbeat: 1780464338501`
   - `2026-06-03T05:26:03.724Z`: `watchPresence(khara1)` emits:
     - `online: false`
   - `2026-06-03T05:26:03.725Z`: `presence_session_expired` fires.

5. Final state
   - UI/action code can see the peer as online from `fetchIdentity` while the presence watcher expires the same peer almost immediately.

Divergence from expected behavior:

- Presence has multiple competing truth sources.
- A peer near the freshness boundary can be treated as online for an action and offline for session teardown in the same second.
- This directly explains contradictory UI states such as online-but-cannot-connect or connected-vs-connecting.

### Timeline D: Stale terminal call inbox cleanup

1. Initial state
   - `watchIncomingCalls(khara2)` subscribes at `2026-06-03T05:25:50.793Z`.

2. Trigger
   - At `2026-06-03T05:25:50.981Z`, the incoming call watcher receives four inbox entries.

3. Observed entries
   - `khara1:khara2:hj4dy036vl`, status `failed`
   - `khara1:khara2:hj4dyg6s6q`, status `ended`
   - `khara1:khara2:hj4dynm7v8`, status `ended`
   - `khara1:khara2:hj4dz5u2r1`, status `failed`

4. Cleanup
   - `voice_call_cleanup_janitor_completed`
   - `cleanedAny: true`
   - `decisionCount: 4`
   - all four decisions delete terminal inbox entries.

5. Final state
   - Cleanup eventually removes the terminal inboxes, but they were still visible to the incoming watcher first.

Divergence from expected behavior:

- Terminal inbox entries should not be able to affect incoming-ring or busy decisions during startup.
- Cleanup is reactive and late relative to watch subscription.

### Timeline E: Android end-call permission denied

1. Initial state
   - Android app is open in Settings.
   - Local Android build: `1.0.6`, build `1007`, demo.

2. Trigger
   - A call end path invokes `signaling.endCall`.

3. Error
   - Screenshot shows:
     - `2026-06-03 08:24 | signaling.endCall | [firebase_database/unknown] Firebase Database error: Permission denied`

4. Code path
   - `FirebaseAdapter.endCall` reads the room, validates participant, writes terminal fields, updates callee inbox status, then removes active locks.
   - `database.rules.json` has separate write rules for:
     - `voiceCalls/$callId/status`
     - `voiceCalls/$callId/endedAt`
     - `voiceCalls/$callId/endedBy`
     - `voiceCalls/$callId/reasonCode`
     - `voiceCalls/$callId/reason`
     - `voiceCallInboxes/$username/$callId/status`
     - active lock deletion paths

5. Final state
   - The terminal write can fail before durable cleanup.
   - If end-call terminal state is denied, the remote peer can remain in a call or a stale lock can survive.

Divergence from expected behavior:

- End-call terminal writes must be allowed for both participants in all valid non-terminal call states.
- Cleanup of terminal states must be idempotent and rules-compatible.

### Timeline F: Android diagnostics export failure

1. Initial state
   - User taps Export diagnostics on Android Settings.

2. Trigger
   - App receives a save destination path that appears as `/document/1282`.

3. Error
   - Snackbar:
     - `PathNotFoundException: Cannot open file, path = '/document/1282'`

4. Code path
   - `CrashDiagnosticsService.exportDiagnostics` calls `_saveFile`.
   - `_fileFromPickerPath` returns `File(path)` for any path without a URI scheme.
   - `/document/1282` has no URI scheme, so it is treated as a normal filesystem path.

5. Final state
   - Export fails.
   - User cannot provide the clean diagnostic report from the affected Android device.

Divergence from expected behavior:

- Android picker/document destinations must be handled as platform-managed document targets or copied through the native save channel.
- A SAF/document path must not be treated as a normal app-writable file.

### Timeline G: Update status inconsistency

1. Windows JSON evidence
   - Version `1.0.6`
   - Build `7`
   - Channel `demo`
   - Platform `windows`
   - Remote policy in export:
     - latest version `1.0.6`
     - latest build `7`
     - minimum version `1.0.6`
     - minimum build `7`
   - Result: `current`

2. Android screenshot evidence
   - Version `1.0.6`
   - Build `1007`
   - Channel `demo`
   - Platform `android`
   - UI says: `Rain is up to date`

3. Repository Remote Config template
   - Demo Android latest build is `7`, not `1007`.

4. Interpretation
   - This evidence does not prove the exact old-client failure.
   - It does prove cross-platform build metadata is inconsistent.
   - With same semantic version, update logic compares integer build numbers. Android build `1007` will never be considered older than remote build `7`.

Divergence from expected behavior:

- Release policy must use platform-correct build numbers.
- The app must show enough policy detail to prove which manifest was loaded and why it decided `current`.

## Correlated Failures

### Cluster 1: Presence, connect disagreement, and request eligibility

Symptoms:

- Peer appears online but cannot connect.
- Peer appears offline until restart.
- One side shows connected while the other shows connecting.
- Offline request eligibility conflicts with direct connect.

Shared root:

- Presence freshness is evaluated by multiple consumers at slightly different times:
  - `watchPresence` emits live online/offline events and schedules a local expiry timer.
  - `fetchIdentity` returns a snapshot with `online` and `lastHeartbeat`.
  - UI, connection recovery, call start, and request notification eligibility consume those states separately.

Evidence:

- `fetchIdentity(khara1)` says online at `05:26:03.505Z`.
- `watchPresence(khara1)` says offline at `05:26:03.724Z`.
- `presence_session_expired` immediately disconnects the peer.
- This happened repeatedly.

Secondary symptoms:

- Recovering/connected UI disagreement.
- Direct connect allowed momentarily, then teardown.
- Offline request notification blocked or allowed inconsistently.

### Cluster 2: Failed calls, false busy, stuck setup, and terminal cleanup

Symptoms:

- Voice/video call fails.
- Calls get stuck.
- Peer may remain in call state.
- Busy appears after failed attempts.
- Incoming requests show terminal records.

Shared root:

- Call terminal truth is split across:
  - Firebase room status.
  - Firebase inbox records.
  - active pair/user locks.
  - local `VoiceCallState`.
  - protocol `VoiceCallSession`.
  - late data/session frames.

Evidence:

- Last crash is a late failed session state after terminal room.
- Four terminal inbox entries were still visible to the incoming watcher.
- Cleanup deleted terminal inboxes only after watcher subscription.
- Every call summary has no ICE candidates and no room status timeline.
- Android `signaling.endCall` is denied by Firebase rules.

Secondary symptoms:

- Stuck connecting.
- False busy.
- Remote side not ending.
- Failed call UI staying around or clearing without proof.

### Cluster 3: Media failure reports and missing setup observability

Symptoms:

- Voice/video cannot establish.
- Camera remains active after ending video.
- Video call hangs.

Shared root supported by evidence:

- The captured failures do not prove a TURN/NAT/media-track root cause because ICE candidate counts are zero.
- Diagnostics do not include enough media lifecycle data to prove track/renderer disposal on every path.

Evidence:

- `iceCandidateWriteCount: 0`
- `iceCandidateReadCount: 0`
- only one WebRTC event: `media_state_changed` to `disposed`
- `VideoCallRenderers` provider changed from an instance to cleared, but no track/stream stop events are present.

Secondary symptoms:

- User-facing "could not connect" can be caused by upstream signaling failure but presented as media failure.
- Camera leak cannot be proven from this export, which is itself a diagnostics defect.

### Cluster 4: Update check confusion and backend compatibility risk

Symptoms:

- Old builds do not prompt for update.
- Settings says up to date when user expects update.

Shared root supported by evidence:

- Version/build policy is inconsistent across platforms and artifacts.

Evidence:

- Windows build: `7`.
- Android screenshot build: `1007`.
- Checked-in Remote Config Android latest build: `7`.
- Equal semantic versions fall back to numeric build comparison.

Secondary symptoms:

- Old Android builds can appear current if remote policy uses the wrong Android build number.
- Backend rules can be deployed while clients believe they are compatible.

### Cluster 5: Diagnostics are not reliable enough for production support

Symptoms:

- Export diagnostics failed on Android.
- Failure taxonomy empty.
- Firebase counters zero.
- Last non-fatal late-frame warning appears as Last Flutter error.

Shared root:

- Diagnostics currently capture some raw events but do not consistently classify, correlate, or export them across platforms.

Evidence:

- Android export fails with `/document/1282`.
- `failureTaxonomy: {}`
- `firebaseCostCounters` all zero despite 31 network operations.
- `lastCrash` contains a non-fatal late-frame warning.

## Root Cause Tree

### RC-001: Call terminal state has multiple competing authorities

Status: Confirmed

Confidence: 9/10

Supporting evidence:

- Last crash: late failed session after terminal room.
- `voice_call_runtime.dart:2188-2194` ignores non-idle session state after terminal latch.
- `voice_call_runtime.dart:4130-4151` still records ignored late state through errorRecorder.
- Four terminal inbox records were visible to incoming watcher.
- Android end-call terminal write denied.

Impact:

- Voice/video call state can disagree across peers.
- Remote peer may not hang up.
- Failed or ended records can produce false busy or stale incoming state.
- User-facing failures appear random because terminal cleanup depends on several async paths.

Fix direction:

- Make Firebase terminal room state the single authoritative terminal event.
- Session/data-channel hangup frames become best-effort only after terminal write.
- Incoming watchers must filter terminal inbox entries before UI/ring/busy logic.
- Late session frames after terminal state must be diagnostic events, not crash records.
- Rules must allow valid terminal writes and matching lock cleanup for both participants.

Validation:

- Runtime tests for local hangup ending remote voice call.
- Runtime tests for remote terminal room ending local call without a hangup frame.
- Emulator rules tests for participant end-call writes from caller and callee.
- Fake adapter tests for terminal inbox filtering before ring/busy.

### RC-002: Firebase rules deny valid end-call cleanup

Status: Confirmed for Android endCall failure; exact denied child path not identified in screenshot

Confidence: 8/10

Supporting evidence:

- Screenshot: `signaling.endCall | [firebase_database/unknown] Firebase Database error: Permission denied`.
- `FirebaseAdapter.endCall` performs a multi-path update to room and inbox, then lock cleanup.
- `database.rules.json` has narrow write predicates for terminal room fields, inbox fields, and lock deletion.

Impact:

- A valid participant can fail to write terminal state.
- Remote peer can remain active or stuck.
- Locks/inboxes can remain stale and cause future false busy.

Fix direction:

- Reproduce with Firebase emulator using the exact end-call multi-path update for:
  - caller ends ringing call
  - callee ends ringing call
  - caller ends accepted/negotiating/connected call
  - callee ends accepted/negotiating/connected call
  - failed/expired timeout cleanup
  - terminal cleanup retry after room already terminal
- Adjust rules to allow only valid terminal transitions while preserving ownership/security.
- Add diagnostics that include denied logical path category without exposing raw payload.

Validation:

- Emulator allow/deny matrix must pass before release.
- App-level integration test must assert `signaling_end_call_completed` for both caller and callee paths.

### RC-003: Presence freshness race between snapshot reads and watch expiry

Status: Confirmed

Confidence: 9/10

Supporting evidence:

- `watchPresence` emits online then offline repeatedly.
- `fetchIdentity(khara1)` returns `online: true` at `05:26:03.505Z`.
- `watchPresence(khara1)` emits `online: false` at `05:26:03.724Z`.
- `presence_session_expired` disconnects peer at `05:26:03.725Z`.
- `FirebaseAdapter.watchPresence` uses a local timer based on `_presenceTimeoutMs = 30000`.

Impact:

- UI and runtime action guards can make contradictory decisions.
- Direct connect/call/request eligibility can change while an action is in progress.
- Session teardown can happen while another subsystem thinks the peer is online.

Fix direction:

- Introduce one app-level `PeerAvailabilitySnapshot` with freshness age, source, and monotonic update time.
- Gate connect/call/request from the same snapshot contract.
- Treat near-expiry presence as `stale` instead of online for user actions.
- Debounce watcher expiry against in-flight fresh identity checks.
- Record heartbeat age and source in every connect/call/request decision.

Validation:

- Unit tests for heartbeat ages around 0-30s, 30-45s, and older.
- Runtime tests where `fetchIdentity` returns online and watcher expires within the same second.
- Tests for restart-free convergence after network resume.

### RC-004: Terminal inbox cleanup happens after incoming watcher exposure

Status: Confirmed

Confidence: 8/10

Supporting evidence:

- `watchIncomingCalls` subscribed at `05:25:50.793Z`.
- It emitted four terminal entries at `05:25:50.981Z`.
- Cleanup janitor then deleted four terminal inboxes.

Impact:

- Startup/resume can briefly expose old terminal calls to runtime.
- Incoming call logic can see stale failed/ended records.
- Busy/ring/failed surfaces can be contaminated by old state.

Fix direction:

- Run cleanup before subscribing, or filter terminal inbox entries inside the watcher before emitting app-level events.
- Terminal entries should be deleted opportunistically but never surfaced to UI/ring/busy.

Validation:

- Fake adapter test with terminal inbox entries present at startup.
- Watcher must emit no incoming call and cleanup must remove entries.

### RC-005: Diagnostics export path handling is broken on Android document paths

Status: Confirmed

Confidence: 10/10

Supporting evidence:

- Screenshot: `/document/1282` PathNotFoundException.
- `CrashDiagnosticsService._fileFromPickerPath` treats scheme-less strings as filesystem paths.
- Existing test covers `content://...`, not `/document/...`.

Impact:

- The affected Android side cannot export diagnostics.
- Support/debugging loses the most important evidence.

Fix direction:

- Do not treat Android `/document/...` style picker values as writable filesystem paths.
- Route Android diagnostic export through a native save channel or require a proper content URI from the picker.
- Add regression test for `/document/1282`.

Validation:

- Unit test: `/document/1282` must not be opened as `File`.
- Android smoke test: export diagnostics saves a JSON file without PathNotFoundException.

### RC-006: Version/update policy has platform build-number inconsistency

Status: Probable

Confidence: 6/10

Supporting evidence:

- Windows diagnostic: version `1.0.6`, build `7`, current.
- Android screenshot: version `1.0.6`, build `1007`, current.
- Checked-in Remote Config template: demo Android latest build `7`.
- Update comparison uses semantic version first, then integer build only when semantic versions are equal.

Impact:

- Android update prompts can fail when remote policy uses Windows-style build numbers.
- Old builds can keep running against newer Firebase rules/protocol.

Fix direction:

- Normalize release build numbering per platform or publish platform-specific correct build numbers.
- Add diagnostics showing selected manifest path and comparison reason.
- Add tests using actual artifact metadata: Android `1007` style, Windows `7` style, and older Android builds.

Validation:

- Unit tests for Android old build vs Android latest build.
- Widget tests for required and optional update prompts.
- Release workflow must fail if manifest Android build is lower than Android artifact build for the same version/channel.

### RC-007: Media lifecycle leak is reported but not provable from current diagnostics

Status: Reported and possible; exact leak path unproven by supplied JSON

Confidence: 4/10 for exact root cause, 9/10 that observability is missing

Supporting evidence:

- Pasted report states camera remains active after ending video.
- JSON shows `VideoCallRenderers` existed and was cleared.
- JSON does not show local track stop, stream dispose, renderer dispose, camera release, or peer connection close events for every path.

Impact:

- Camera/microphone resources can remain active.
- User privacy and battery are affected.
- Repeated calls can fail because devices remain allocated.

Fix direction:

- Add media resource lifecycle instrumentation first.
- Then prove every terminal path stops tracks, disposes streams, disposes renderers, and closes peer connections.

Validation:

- Unit/fake media tests for every terminal path.
- Windows and Android smoke tests checking renderer/track disposal events.
- Diagnostics export must include media cleanup summary.

## Impact Assessment

Severity: Critical

Affected product areas:

- Voice calls
- Video calls
- Presence
- Direct connect
- Offline request eligibility
- Firebase call signaling
- Update prompts
- Diagnostics export

Production impact:

- Calls are not production reliable.
- Old/stale Firebase state can block new calls.
- Users can see contradictory online/connected states.
- End-call cleanup can fail due to permissions.
- Android users may be unable to export the logs needed to debug failures.
- Backend rule changes can break older clients if update enforcement is unreliable.

Security/privacy impact:

- Permission-denied rules are safer than over-permissive rules, but they are currently denying expected participant cleanup.
- Reported camera resource leakage is a privacy blocker until proven fixed.
- Diagnostics must not over-correct by logging raw SDP, ICE candidates, tokens, credentials, or message content.

## Fix Roadmap

Every fix below is tied to evidence above. This is a roadmap, not an implementation claim.

### Phase 0: Evidence and test harness lock

Addresses:

- Empty failure taxonomy.
- Missing room/media timeline.
- Incomplete proof for camera cleanup.

Tasks:

- Add deterministic call timeline capture:
  - presence decision
  - room/lock decision
  - room status transitions
  - inbox transitions
  - offer/answer created/applied
  - local/remote ICE candidate counts
  - media capture start/stop
  - renderer create/dispose
  - terminal cleanup result
- Add emulator tests for the exact end-call update path.
- Add tests for Android diagnostics export path values.

Exit criteria:

- A failed call export identifies whether failure was presence, Firebase rules, stale lock, SDP, ICE, media capture, renderer, or UI state.

### Phase 1: Firebase end-call rules and terminal cleanup

Addresses:

- RC-001.
- RC-002.
- RC-004.

Tasks:

- Reproduce Android `signaling.endCall` denial in emulator.
- Fix the minimal denied rule path.
- Keep security strict:
  - only caller/callee can end.
  - only valid terminal transitions allowed.
  - only matching call locks can be removed.
- Filter terminal inbox entries before incoming call UI/ring/busy.
- Make terminal cleanup idempotent for already terminal/missing rooms.

Exit criteria:

- Caller and callee can end voice/video calls in every non-terminal state.
- Terminal inbox records never reach incoming UI.
- Stale terminal locks are cleaned only when `callId` matches.

### Phase 2: Call terminal state single source of truth

Addresses:

- RC-001.
- Voice call remote side not closing.
- Late session-frame crash records.

Tasks:

- Firebase room terminal state wins over session frames.
- Session/data hangup frame becomes best-effort after durable terminal write.
- Late session states after terminal become non-crash diagnostics.
- Runtime returns to idle after terminal reconciliation.
- Ended/failed presentation is separate from active runtime state.

Exit criteria:

- Local hangup ends remote voice call even if hangup frame is lost.
- Remote terminal room ends local voice call.
- Late `failed`, `markConnected`, `hangup`, or media frames cannot revive or poison a terminal call.

### Phase 3: Presence single availability model

Addresses:

- RC-003.
- Online/offline contradictions.
- Direct connect/request eligibility conflicts.

Tasks:

- Replace scattered online checks with one `PeerAvailabilitySnapshot`.
- Include:
  - online/stale/offline/unknown
  - heartbeat age
  - source
  - session id
  - last evaluated time
- Near-expiry presence should not be treated as solid online for user actions.
- Connect/call/request guards must consume the same snapshot.
- Presence expiration should reconcile connection state once, not repeatedly.

Exit criteria:

- No action can start from an online snapshot that expires in the same decision window.
- Peer state converges without app restart.
- Request notification eligibility and direct connect never contradict each other.

### Phase 4: Call start pipeline hardening

Addresses:

- Zero ICE candidate call failures.
- Stuck connecting.
- False busy after failed attempts.

Tasks:

- Enforce one shared voice/video start pipeline:
  - stable presence snapshot
  - stale lock repair
  - permission/media preflight
  - Firebase room/lock/inbox creation
  - accept/reject/busy
  - SDP offer/answer
  - ICE candidates
  - active/terminal
- Add hard timeout-to-terminal cleanup for each phase.
- Classify failures by phase.

Exit criteria:

- No call remains connecting forever.
- A failed call creates a terminal room state or no room at all.
- A retry starts from a clean state.

### Phase 5: Media lifecycle proof and cleanup

Addresses:

- RC-007.
- Camera active after video end report.

Tasks:

- Instrument media acquisition and disposal.
- Ensure every terminal path stops:
  - audio tracks
  - video tracks
  - local media stream
  - remote media stream references
  - renderers
  - peer connection
- Add fake media tests and platform smoke tests.

Exit criteria:

- Diagnostics show every acquired media resource has a matching release event.
- Camera cannot remain active after terminal call cleanup.

### Phase 6: Update policy repair

Addresses:

- RC-006.

Tasks:

- Align artifact build numbers and Remote Config build numbers per platform.
- Add release workflow checks comparing:
  - Android artifact build
  - Windows artifact build
  - Remote Config template
  - docs manifest example
- Add Settings diagnostics showing selected channel/platform/policy and comparison reason.

Exit criteria:

- Old Android and Windows builds show required/optional update correctly.
- Current builds show current for the correct reason.

### Phase 7: Diagnostics export repair

Addresses:

- RC-005.

Tasks:

- Fix Android document path export.
- Add regression test for `/document/1282`.
- Keep `content://` behavior safe.
- Add export smoke test on Android emulator.

Exit criteria:

- Android diagnostics export never fails because a picker document path is treated as a normal filesystem path.

## Validation Strategy

### Required automated tests

Firebase emulator:

- Caller can end ringing/accepted/negotiating/connected calls.
- Callee can end ringing/accepted/negotiating/connected calls.
- Terminal room cleanup removes matching locks.
- Stale/terminal inbox records are ignored before incoming UI.
- Live newer locks cannot be deleted by stale cleanup.

Runtime/fake adapter:

- Late failed session after terminal room is ignored without becoming a last-crash record.
- Remote terminal room ends local voice call.
- Local voice hangup writes terminal room before best-effort session hangup.
- Call start with stale locks repairs once.
- Failed media setup returns to idle and cleans locks.

Presence:

- `fetchIdentity` online and watcher expiry in same second converges to stale/offline without contradictory actions.
- Presence recovers without restart after network resume.
- Manual disconnect is not confused with presence expiry.

Media:

- Every acquired track has a stop event.
- Every renderer has a dispose event.
- Failed call setup releases camera/mic.
- Video call terminal cleanup releases camera/mic.

Update:

- Android `1.0.6+1006` vs policy `1.0.6+1007` prompts update.
- Windows `1.0.6+6` vs policy `1.0.6+7` prompts update.
- Same semantic version but wrong platform build policy fails release metadata validation.

Diagnostics:

- Android `/document/1282` export path does not throw `PathNotFoundException`.
- Export includes call failure taxonomy.
- Export includes non-zero Firebase operation counters when network events exist.

### Required manual smoke checks

- PC-to-mobile voice call starts, connects, ends from PC, and ends on mobile.
- Mobile-to-PC voice call starts, connects, ends from mobile, and ends on PC.
- PC-to-mobile video call starts, connects, ends, and releases camera on both sides.
- Mobile-to-PC video call starts, connects, ends, and releases camera on both sides.
- Restart-free presence convergence after closing one app.
- Android diagnostics export succeeds after a failed call.

## Confidence Table

| Root cause | Status | Confidence | Why |
| --- | --- | ---: | --- |
| Call terminal state has multiple competing authorities | Confirmed | 9 | Late session failure after terminal room, terminal inbox cleanup, empty call timelines, and runtime/code evidence all align. |
| Firebase rules deny valid end-call cleanup | Confirmed for Android error | 8 | Screenshot shows `signaling.endCall` permission denied; exact denied child path needs emulator reproduction. |
| Presence freshness race | Confirmed | 9 | JSON shows online identity read followed by offline watch expiry within 219 ms. |
| Terminal inbox cleanup after watcher exposure | Confirmed | 8 | Watcher emitted four terminal entries before cleanup deleted them. |
| Android diagnostics export path bug | Confirmed | 10 | Screenshot and `_fileFromPickerPath` behavior directly match. |
| Update/build policy mismatch | Probable | 6 | Evidence proves build-number inconsistency, but supplied artifacts do not include an old-client failed prompt trace. |
| Camera/media resource leak exact path | Possible | 4 | Manual report says camera stays active, but JSON lacks enough media lifecycle events to identify exact path. Missing observability is confirmed. |

## Final Conclusion

The primary evidence-supported failure is not "WebRTC is broken" by itself.

The captured failures show Rain is failing before reliable media negotiation:

1. Presence flips between online and expired near the freshness boundary.
2. Failed/ended call artifacts remain visible to incoming watchers.
3. Late session states fire after Firebase terminal state.
4. Android cannot always write end-call terminal state because Firebase rules deny `signaling.endCall`.
5. Diagnostics export fails on Android, hiding the best evidence.

The next implementation must start with Firebase end-call rule reproduction, terminal-state ownership, presence availability unification, and diagnostics export repair. Media cleanup must be proven after instrumentation, not guessed.
