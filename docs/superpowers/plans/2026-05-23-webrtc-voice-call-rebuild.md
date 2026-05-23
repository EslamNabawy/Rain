# WebRTC Voice Call Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build reliable 1:1 audio-only calls for accepted Rain friends on Android and Windows.

**Architecture:** Keep the existing chat/data `RTCPeerConnection` data-only. Create one dedicated, short-lived audio-only `RTCPeerConnection` per call, then dispose it fully on hangup/failure. WebRTC carries real-time microphone packets as RTP/RTCP over DTLS-SRTP; Rain only signals SDP/ICE/control frames and manages mic, state, UI, and cleanup.

**Tech Stack:** Flutter, Riverpod, `flutter_webrtc`, Firebase signaling, existing Rain monorepo packages (`peer_core`, `protocol_brain`, `rain_core`, `apps/rain`), Melos CI.

---

## Hard Decision

Use a dedicated call media peer connection.

Do not attach microphone tracks to `DefaultPeerCore`'s long-lived chat peer connection. That old design couples two lifetimes:

- chat/data: long-lived, reconnectable, data channels, file chunks
- call/media: short-lived, permission-driven, track lifecycle, ICE/media readiness

Mixing them caused native transceiver lifecycle failures. Rebuilding voice on a fresh per-call media PC removes renegotiation races and gives every call clean setup/teardown.

## Audio Model

Rain does not send raw microphone packets through data channels.

Correct flow:

```text
Microphone -> MediaStreamTrack -> RTCPeerConnection sender
  -> Opus encode -> RTP packets -> DTLS-SRTP encryption
  -> ICE selected candidate pair -> remote jitter buffer
  -> Opus decode -> speaker/audio device
```

Rain controls only:

```text
permission -> audio session -> getUserMedia -> addTrack/addTransceiver
offer/answer SDP -> ICE candidates -> state changes -> cleanup
```

## File Map

### New Files

- `packages/peer_core/lib/src/voice/voice_media_connection.dart`
  - Owns one audio-only `RTCPeerConnection`.
  - Captures local microphone.
  - Creates/applies SDP.
  - Emits local ICE candidates.
  - Buffers remote ICE until remote description is set.
  - Emits remote audio track events.
  - Closes and disposes all media resources.

- `packages/peer_core/lib/src/voice/voice_media_models.dart`
  - Typed state and diagnostics for media connection.
  - No app policy, no Rain friend logic.

- `packages/peer_core/test/voice_media_connection_test.dart`
  - Fake platform tests for mic, SDP, ICE buffering, readiness, mute, cleanup, repeated calls.

- `packages/protocol_brain/lib/src/voice/voice_call_signaling.dart`
  - Call signaling coordinator.
  - Sends/receives typed call frames.
  - Owns call IDs, sequence rejection, stale frame handling.

- `packages/protocol_brain/lib/src/voice/voice_call_session.dart`
  - Protocol-level call state machine.
  - Does not import Flutter UI.

- `packages/protocol_brain/test/voice_call_session_test.dart`
  - Tests invite/accept/reject/busy/offer/answer/candidate/hangup state flow.

- `apps/rain/lib/application/runtime/voice_call_diagnostics.dart`
  - Redacted call diagnostics for support/debug UI and logs.

- `apps/rain/test/voice_call_runtime_dedicated_media_test.dart`
  - App runtime tests for one-call-global, file-transfer blocking, mic failure, timeout, logout cleanup.

### Modified Files

- `packages/peer_core/lib/peer_core.dart`
  - Export new voice media types.

- `packages/peer_core/lib/src/platform_bridge.dart`
  - Keep `getUserMedia`, `prepareVoiceAudio`, `clearVoiceAudio`, `setMicrophoneMuted`.
  - Add optional media PC factory if needed for tests.

- `packages/peer_core/lib/src/default_peer_core.dart`
  - Remove voice-call media APIs from chat peer core after replacement path exists.
  - Keep chat/control/file data channels unchanged.

- `packages/rain_core/lib/voice_call/voice_call_frame.dart`
  - Add `candidate`.
  - Add `seq`.
  - Add `sessionEpoch`.
  - Keep size limits and strict parsing.

- `apps/rain/lib/application/runtime/voice_call_state.dart`
  - Add `preflightingMic`, `creatingMedia`, typed failure reasons, diagnostics ID.

- `apps/rain/lib/application/runtime/voice_call_runtime.dart`
  - Replace current media renegotiation path with dedicated media session orchestration.

- `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
  - Own global call lock and lifecycle disposal.

- `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
  - Keep call UI, update error and disabled states.

- `apps/rain/android/app/src/main/AndroidManifest.xml`
  - Verify `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `CHANGE_NETWORK_STATE`, `ACCESS_NETWORK_STATE`.

- `.github/workflows/ci.yml`
  - Keep Android/Windows artifact checks.
  - Add artifact smoke verification if new ABI/artifact names change.

## Protocol Frame Shape

Use strict JSON frames. These are control frames, not audio packets.

```dart
enum VoiceCallFrameType {
  invite,
  accept,
  reject,
  busy,
  offer,
  answer,
  candidate,
  hangup,
  mute,
}
```

Required fields:

```json
{
  "type": "voice_call",
  "action": "offer",
  "callId": "alice-bob-1700000000000",
  "from": "alice",
  "to": "bob",
  "sentAt": 1700000000000,
  "seq": 3,
  "sessionEpoch": 1
}
```

Offer/answer payload:

```json
{
  "sdpType": "offer",
  "sdp": "v=0..."
}
```

Candidate payload:

```json
{
  "candidate": "candidate:...",
  "sdpMid": "0",
  "sdpMLineIndex": 0
}
```

Rules:

- Reject wrong `to`.
- Reject wrong `from`.
- Ignore stale `callId`.
- Ignore lower/equal `seq` for same `callId`.
- Ignore stale `sessionEpoch`.
- Buffer candidates until remote SDP is set.
- Drop frames after hangup/failure.
- Never persist as chat messages.

## Signaling Choice

Preferred robust path: Firebase ephemeral call signaling.

Reason: outgoing call should not depend on an already-open chat data channel. Existing Firebase signaling already solves peer discovery and offline-ish coordination while app is open.

Minimal schema:

```text
voiceCalls/{callId}
  caller
  callee
  status
  createdAt
  expiresAt
  seqByPeer/{username}
  frames/{frameId}
```

Security rules must enforce:

- caller/callee only
- accepted friends only
- bounded frame size
- bounded TTL

If Firebase schema change is still forbidden, fallback path is existing encrypted `SessionChannel.control`; then calls require a connected chat peer before ringing. That is simpler but less reliable for call setup.

## Phase 00: Architecture Lock

**Purpose:** Lock the architecture before code changes start.

- [ ] Confirm voice media will use one fresh, short-lived audio-only `RTCPeerConnection` per call.

Architecture rule:

```text
chat/data peer connection: chat, control, file data channels only
voice media peer connection: microphone audio only, created per call, disposed after call
```

- [ ] Confirm Rain will not send microphone audio over data channels.

Reason:

```text
WebRTC media stack already handles Opus, RTP, RTCP, DTLS-SRTP, jitter buffer, packet loss, and timing.
Data channels are only for call control/signaling, not realtime mic packets.
```

- [ ] Confirm signaling path before implementation.

Preferred:

```text
Firebase ephemeral voice call signaling
```

Fallback:

```text
Existing encrypted SessionChannel.control, requiring connected peer before ringing
```

- [ ] Confirm release proof required.

Do not mark voice call fixed until:

```text
same commit installed on Windows and Android
Windows -> Android live call passes
Android -> Windows live call passes
repeat calls pass without app restart
mic denial and hangup paths pass
```

- [ ] Commit.

```powershell
git add docs/superpowers/plans/2026-05-23-webrtc-voice-call-rebuild.md
git commit -m "docs: add voice call architecture lock phase"
```

## Phase 01: Freeze Old Media Path

**Purpose:** Stop adding more logic to the chat peer connection.

- [ ] Write failing tests proving `DefaultPeerCore` is not used for new call media.

Run:

```powershell
cd packages/peer_core
flutter test test/peer_core_test.dart --plain-name "default peer core does not own dedicated voice media calls"
```

Expected before change: fail because current call code still exposes media APIs through chat peer core.

- [ ] Add `VoiceMediaConnection` interface skeleton.

```dart
abstract class VoiceMediaConnection {
  Stream<VoiceIceCandidate> get onIceCandidate;
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack;
  Stream<VoiceMediaState> get onStateChanged;

  Future<void> startLocalAudio();
  Future<VoiceSessionDescription> createOffer();
  Future<VoiceSessionDescription> acceptOffer(VoiceSessionDescription offer);
  Future<void> applyAnswer(VoiceSessionDescription answer);
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate);
  Future<void> setMuted({required bool muted});
  Future<void> dispose();
}
```

- [ ] Export skeleton from `packages/peer_core/lib/peer_core.dart`.

- [ ] Commit.

```powershell
git add packages/peer_core/lib packages/peer_core/test
git commit -m "feat: add dedicated voice media interface"
```

## Phase 02: Dedicated Media Core

**Purpose:** Create real audio-only WebRTC connection per call.

- [ ] Implement `DefaultVoiceMediaConnection`.

Core lifecycle:

```dart
await platform.prepareVoiceAudio();
localStream = await platform.getUserMedia({
  'audio': {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
  },
  'video': false,
});
for (final track in localStream.getAudioTracks()) {
  await peerConnection.addTrack(track, localStream);
}
```

- [ ] Wire `RTCPeerConnection` events.

Required event handling:

```dart
pc.onIceCandidate = (candidate) => iceController.add(candidate);
pc.onTrack = (event) {
  if (event.track.kind == 'audio') {
    remoteTrackController.add(event);
  }
};
pc.onIceConnectionState = (state) => diagnostics.recordIceState(state);
pc.onConnectionState = (state) => diagnostics.recordConnectionState(state);
```

- [ ] Implement candidate buffering.

Rule:

```text
if remoteDescriptionSet == false:
  queue candidate
else:
  pc.addCandidate(candidate)
```

After `setRemoteDescription`, flush queue in order.

- [ ] Implement idempotent dispose.

Order:

```text
cancel timers/subscriptions
stop local tracks
dispose local stream
close RTCPeerConnection
clear Android audio
close stream controllers
```

- [ ] Tests:

```powershell
cd packages/peer_core
flutter test test/voice_media_connection_test.dart
```

Must cover:

- mic success
- mic denied
- create offer after local track
- accept offer creates answer
- candidate buffered before remote SDP
- mute does not stop track
- dispose twice is safe
- repeated call creates new PC

- [ ] Commit.

```powershell
git add packages/peer_core/lib packages/peer_core/test
git commit -m "feat: add dedicated webrtc voice media connection"
```

## Phase 03: Signaling Protocol

**Purpose:** Make call control deterministic before UI.

- [ ] Extend `VoiceCallFrame`.

Add fields:

```dart
final int seq;
final int sessionEpoch;
final String? candidate;
final String? sdpMid;
final int? sdpMLineIndex;
```

Add validation:

```text
candidate frames require candidate + sdpMid/sdpMLineIndex
offer frames require sdpType=offer + sdp
answer frames require sdpType=answer + sdp
seq > 0
sessionEpoch > 0
```

- [ ] Add tests in `packages/rain_core/test/voice_call_frame_test.dart`.

Cases:

- invalid candidate missing `sdpMid`
- stale sequence ignored by caller code
- wrong peer ignored
- unknown frame ignored by demux

- [ ] Implement `VoiceCallSession`.

State machine:

```text
idle
preflightingMic
outgoingRinging
incomingRinging
creatingMedia
connectingMedia
active
ending
failed
```

Allowed transitions only. Invalid events ignored and logged.

- [ ] Implement timeouts.

```text
ringing timeout: 45s
answer timeout: 15s
ICE/media timeout: 20s
cleanup watchdog: 5s
```

- [ ] Tests:

```powershell
cd packages/protocol_brain
flutter test test/voice_call_session_test.dart
```

Must cover:

- outgoing invite flow
- incoming accept flow
- reject
- busy
- timeout
- stale frame ignored
- wrong peer ignored
- hangup clears only voice session

- [ ] Commit.

```powershell
git add packages/rain_core packages/protocol_brain
git commit -m "feat: add deterministic voice call signaling"
```

## Phase 04: Runtime Integration

**Purpose:** Wire app runtime without UI churn.

- [ ] Replace current `brain.startLocalAudio/createMediaOffer/applyMediaOffer` usage in `apps/rain/lib/application/runtime/voice_call_runtime.dart`.

New outgoing flow:

```text
validate friend/network/global-call-lock/file-transfer-lock
set phase preflightingMic
create VoiceMediaConnection
startLocalAudio
send invite
wait accept
create offer
send offer
send candidates as they appear
wait answer
apply answer
wait media readiness
set active
```

New incoming flow:

```text
receive invite
validate friend/global-call-lock/file-transfer-lock
show incomingRinging
on accept: startLocalAudio
send accept
wait offer
acceptOffer -> answer
send answer
send candidates as they appear
wait media readiness
set active
```

- [ ] Add global call lock in runtime.

Rule:

```text
phase != idle && phase != failed => blocks new calls and file transfers
```

- [ ] Add cleanup on:

```text
hangup
remote hangup
timeout
peer disconnect
network loss
logout
app dispose
mic failure
SDP failure
ICE failure
```

- [ ] Tests:

```powershell
cd apps/rain
flutter test test/voice_call_runtime_dedicated_media_test.dart
```

Must cover:

- outgoing mic denied sends no invite
- incoming mic denied sends reject
- active file transfer blocks call
- active call blocks new file transfer
- call failure keeps chat session alive
- logout disposes media connection
- remote hangup clears busy state

- [ ] Commit.

```powershell
git add apps/rain/lib/application/runtime apps/rain/test
git commit -m "feat: wire voice calls to dedicated media runtime"
```

## Phase 05: UI/Error Handling

**Purpose:** Make state understandable and stop hiding root causes.

- [ ] Update call panel copy in `apps/rain/lib/presentation/widgets/home/chat_panel.dart`.

Display typed messages:

```text
Microphone permission required.
Peer microphone permission required.
Call timed out while ringing.
Call media could not connect: ICE timeout.
Call media connected but no remote audio arrived.
Peer is busy.
Finish the active file transfer first.
```

- [ ] Keep raw native error out of normal UI.

Store raw error in diagnostics:

```dart
VoiceCallDiagnostics(
  callId: callId,
  role: role,
  failureCode: failureCode,
  nativeError: error.toString(),
  iceStates: iceStates,
  connectionStates: connectionStates,
)
```

- [ ] Widget tests:

```powershell
cd apps/rain
flutter test test/rain_chat_widgets_test.dart --plain-name "voice call"
```

Must cover:

- call button disabled during transfer
- call button disabled during another call
- incoming ring actions
- active mute/hangup actions
- mic permission retry message
- failed call dismiss

- [ ] Commit.

```powershell
git add apps/rain/lib/presentation apps/rain/test
git commit -m "feat: update voice call ui states"
```

## Phase 06: Platform/Build Gates

**Purpose:** Prevent wrong APK/EXE and platform regressions.

- [ ] Verify Android permissions are present.

Expected manifest entries:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
```

- [ ] Verify release artifacts still build.

Commands:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

- [ ] Verify generated files do not drift.

Expected generated artifacts remain committed:

```text
apps/rain/lib/application/state/app_state.freezed.dart
packages/rain_core/lib/database/rain_database.g.dart
```

If Drift or Freezed inputs change, regenerate and commit outputs before CI.

- [ ] Verify Android release path, not only debug.

Reason: debug APK can pass while R8/release packaging fails.

Required checks:

```text
release build uses Kotlin DSL correctly
permissions are outside <application>
no camera feature required for audio-only installs
no Bluetooth permission added unless headset routing is explicitly supported
WebRTC native libs exist in produced APK
```

- [ ] Verify Android debug APK ABI.

Expected for current CI:

```text
debug APK: app-arm64-v8a-debug.apk
release artifact: Rain-Demo-Android-ARM-v8-v9-Build.apk
```

If `armeabi-v7a` is required again, explicitly add a separate v7 artifact and update CI checks. Do not silently ship universal APKs.

- [ ] Verify Windows package shape.

Artifact must include the full Flutter release directory, not only `rain.exe`:

```text
rain.exe
flutter_windows.dll
flutter_webrtc_plugin.dll
libwebrtc.dll
sqlite3.dll
data/
plugin DLLs
assets
```

Do not hand-edit:

```text
apps/rain/windows/flutter/generated_plugins.cmake
apps/rain/windows/flutter/generated_plugin_registrant.cc
```

- [ ] Commit.

```powershell
git add apps/rain/android .github/workflows scripts
git commit -m "ci: verify voice call platform artifacts"
```

## Phase 07: Manual Device Gate

**Purpose:** Do not call it fixed until real devices prove it.

Install same commit on both devices.

Required matrix:

```text
Windows -> Android direct route
Android -> Windows direct route
Windows -> Android TURN relay
Android -> Windows TURN relay
Android mic permission denied
Windows mic unavailable/blocked
caller hangup
callee hangup
network loss during ringing
network loss during active call
5 repeated calls without restarting either app
chat send during active call
file send blocked during active call
```

Pass criteria:

```text
remote voice audible both directions
call reaches active only after media readiness
hangup releases mic indicator
next call works without app restart
chat remains connected
no stale Peer is busy state
no RTCRtpTransceiver disposed errors
diagnostics identify failure reason when failure is forced
```

## Phase 8: PR Gate

Before PR:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
git diff --check
```

CI must pass:

```text
Workflow Lint
Quality Gate
Analyze all packages
Test all packages
Firebase Backend
Firebase Emulator Integration
Android Build
Build EXE and APK Artifacts
Required Checks
```

PR description must include:

```text
Architecture: dedicated per-call media RTCPeerConnection
Manual matrix result: pass/fail per row
Known limits: app-open only, no background ringing, no call history
Artifacts tested: exact APK and EXE names
```

## Grill-Me Risks

- If Firebase call schema is rejected, calls must require a connected chat control channel before ringing.
- If TURN config is weak, direct calls may work while relay routes fail.
- If Android OEM audio routing blocks communication mode, mic capture may succeed but speaker output may route wrong.
- If Windows microphone privacy blocks capture, manifest-style Android fixes do nothing; runtime error must be typed.
- If UI marks active before ICE/media readiness, users see fake connected calls.
- If diagnostics log SDP/candidates raw, privacy/security risk.
- If old media APIs remain callable, future patches can regress back to shared-PC voice.
- If release/R8 path is not tested, debug APK can look good while shipped APK fails.

## Caveman Summary

Old way bad: one peer connection do chat forever, then voice later. Native WebRTC state rot.

New way good: one fresh media connection per call. Mic in, WebRTC sends RTP, call ends, connection dies. Chat stays alive.

## Sources Checked

- `flutter_webrtc` docs via Context7: `getUserMedia`, `createPeerConnection`, offer/answer, ICE candidates, `addTrack`, `replaceTrack`, Android audio configuration.
- WebRTC project docs via Context7: signaling exchanges SDP/ICE; peer connection transports audio/video/data.
- Local Rain files listed in File Map.
