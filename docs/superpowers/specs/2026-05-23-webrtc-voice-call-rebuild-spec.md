# WebRTC Voice Call Rebuild Spec

Status: approved for implementation planning

Date: 2026-05-23

Branch policy: commit every change before moving to the next phase. Do not merge from this workstream. Do not run Android or Windows platform builds until the final release gate.

## Summary

Rain voice calls will be rebuilt around the same working shape used by `flutter-webrtc-demo`: independent signaling plus one dedicated media `RTCPeerConnection` per call.

The current voice path is not acceptable because ringing and media signaling still depend on an already-connected chat/control data channel. That couples calls to chat peer-session health and creates fragile failure modes such as stale SDP, disposed transceivers, false busy states, and media setup timeouts.

The new design uses Firebase Realtime Database as a demo-style signaling relay for ephemeral voice calls. Firebase carries call control, SDP, and ICE candidates. WebRTC carries microphone audio as RTP/SRTP media. Chat and file-transfer data channels remain separate.

## Reference Material

- `flutter-webrtc-demo`: https://github.com/flutter-webrtc/flutter-webrtc-demo
- `flutter-webrtc`: https://github.com/flutter-webrtc/flutter-webrtc
- `flutter-webrtc-server`: https://github.com/cloudwebrtc/flutter-webrtc-server
- Existing Rain architecture lock: `docs/architecture/voice-call-architecture-lock.md`

Reference commits studied locally:

- `flutter-webrtc-demo`: `7f3b2e5`
- `flutter-webrtc`: `4aa845b`
- `flutter-webrtc-server`: `751b715`

## Goals

- Make 1:1 audio-only calls reliable on Android and Windows.
- Allow ringing without a preconnected chat peer session.
- Use a fresh, short-lived audio-only `RTCPeerConnection` for each call.
- Use Firebase RTDB only for ephemeral signaling: invite, accept, reject, busy, offer, answer, ICE candidates, mute, hangup, and terminal state.
- Keep microphone audio on WebRTC media tracks only.
- Prefer reliability over direct-only purity: voice must support TURN relay-first or relay fallback.
- Preserve chat usability during active calls.
- Block new file sends and accepts during active calls with clear UI text.
- Provide typed user-facing failures and full internal diagnostics.
- Prove behavior with unit tests, Firebase emulator tests, final platform builds, and physical Android/Windows manual gates.

## Non-Goals

- No group calls.
- No video calls.
- No call history persistence.
- No background ringing service.
- No push notifications.
- No macOS or Linux support in this voice-call release.
- No custom media E2EE beyond WebRTC DTLS-SRTP for V1 of the rebuild.
- No mid-call device switching in the first stable version.
- No renegotiation on the chat/data peer connection.

## Hard Decisions

1. Voice signaling must not use `SessionChannel.control`.
2. Voice ringing must not require `connectPeer()` or an active chat data channel.
3. Caller owns the initial media offer.
4. A pair lock prevents simultaneous-call glare.
5. ICE candidates are not rejected by one global monotonic sequence.
6. SDP and ICE payloads must be encrypted before being written to Firebase.
7. One active call globally is enough for this release.
8. Android/Windows platform builds happen only at the final gate.

## Target Architecture

```text
Rain UI / Riverpod providers
  -> RainRuntimeController voice facade
  -> VoiceCallCoordinator
      - state machine
      - call lock
      - timeouts
      - stale-frame rejection
      - Firebase voice signaling
      - media connection lifecycle
  -> VoiceSignalingAdapter
      - Firebase RTDB call rooms
      - encrypted SDP/ICE payloads
      - inbox and pair-lock streams
  -> VoiceMediaConnection
      - flutter_webrtc RTCPeerConnection
      - getUserMedia audio-only
      - addTrack
      - offer/answer
      - ICE candidate buffering
      - remote audio stream retention
      - diagnostics
```

Package boundaries:

- `packages/peer_core`: WebRTC/media only. No Firebase, Riverpod, Drift, friends, or UI.
- `packages/protocol_brain`: voice signaling contracts, voice coordinator, call state machine, fake signaling adapters, and protocol tests.
- `apps/rain`: Riverpod integration, runtime facade, user-facing state mapping, UI, sound effects, file-transfer blocking, and app lifecycle cleanup.
- `packages/rain_core`: no live signaling or WebRTC. Existing frame types become legacy unless reused as pure DTOs.
- `backend/firebase`: RTDB rules, indexes, cleanup functions, and emulator contract fixtures.

## Firebase Data Model

```text
activeVoicePairs/{pairId}
  callId: string
  caller: username
  callee: username
  createdAt: millis
  updatedAt: millis
  expiresAt: millis

voiceCallInboxes/{username}/{callId}
  from: username
  to: username
  pairId: "alice:bob"
  status: ringing|accepted|ended|failed|expired
  createdAt: millis
  updatedAt: millis
  expiresAt: millis

voiceCalls/{callId}
  v: 1
  pairId: "alice:bob"
  caller: username
  callee: username
  status: ringing|accepted|negotiating|connected|ended|failed|expired
  createdAt: millis
  acceptedAt?: millis
  connectedAt?: millis
  endedAt?: millis
  updatedAt: millis
  expiresAt: millis
  endedBy?: username
  reasonCode?: string
  reason?: string
  muted/{username}: boolean
  offer?: encryptedEnvelope
  answer?: encryptedEnvelope
  ice/caller/{candidateId}: encryptedEnvelope
  ice/callee/{candidateId}: encryptedEnvelope
```

`pairId` is canonical username order: `min(usernameA, usernameB):max(usernameA, usernameB)`.

Encrypted envelopes reuse the existing signaling cipher shape:

```text
v
alg
ts
nonce
ciphertext
mac
```

Payload sizes must be bounded:

- SDP envelope ciphertext: max 262144 bytes.
- ICE envelope ciphertext: max 32768 bytes.
- Reason text: short bounded string.
- IDs and usernames: normalized, non-empty, bounded strings.

## Firebase Rules Requirements

- Only authenticated caller/callee can read a `voiceCalls/{callId}` room.
- Caller/callee must be accepted friends.
- Blocked users cannot create or accept calls.
- Only caller can create `ringing`, write `offer`, and write `ice/caller`.
- Only callee can accept, reject, write `answer`, and write `ice/callee`.
- Either participant can hang up or mark terminal state.
- Third authenticated users must be denied.
- `caller`, `callee`, `pairId`, and `createdAt` are immutable after create.
- `expiresAt` is required and indexed.
- Cleanup removes expired calls, inbox pointers, and active pair locks.

## Signaling Flow

Outgoing call:

1. User taps call.
2. Runtime validates network, accepted friendship, block state, no active call, and no active transfer.
3. Runtime requests microphone before ringing.
4. Runtime obtains current ICE servers from the TURN credential service.
5. Runtime creates Firebase pair lock through `activeVoicePairs/{pairId}`.
6. Runtime creates `voiceCalls/{callId}` and callee inbox pointer.
7. Callee receives incoming ringing from `voiceCallInboxes/{callee}/{callId}`.
8. Caller waits for accept/reject/busy/timeout.

Accept call:

1. Callee requests microphone.
2. Callee marks call accepted.
3. Caller creates dedicated media connection, adds local audio, creates offer, writes encrypted offer.
4. Callee applies remote offer, adds local audio, creates answer, writes encrypted answer.
5. Both sides write and watch role-specific ICE candidates.
6. Candidate watchers buffer candidates until remote SDP is applied.
7. Call becomes active only after media connection reaches connected/completed and remote audio is observed or media state confirms connection.

Hangup/failure:

1. Terminal state is written once with `endedBy`, `reasonCode`, and timestamp.
2. Both clients stop local tracks, dispose media connection, clear Android communication audio, release pair lock, remove inbox pointer, and return to idle.
3. Chat session is not torn down just because voice ended.

## Media Lifecycle

Each call owns one fresh `RTCPeerConnection`.

Creation:

- Set `sdpSemantics` to `unified-plan`.
- Use current ICE servers.
- For voice reliability, production should prefer relay-first or have a relay fallback mode.
- Register `onIceCandidate`, `onTrack`, `onConnectionState`, and `onIceConnectionState` before negotiation.
- Start Android communication audio before `getUserMedia`.
- Request `getUserMedia` with audio only:

```text
audio:
  echoCancellation: true
  noiseSuppression: true
  autoGainControl: true
video: false
```

Track handling:

- Add local microphone track with `addTrack`.
- Keep local stream and remote stream references alive for the call lifetime.
- Remote audio events must be retained by runtime/media owner, not dropped after callback.
- Mute changes track state/helper mute only; they do not stop or replace the track.

Cleanup:

- Stop all local media tracks.
- Dispose local media stream.
- Close and dispose peer connection.
- Clear Android communication device/audio mode.
- Cancel all Firebase/media subscriptions.
- Make cleanup idempotent.

## Audio Routing

Android:

- Require `RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, `CHANGE_NETWORK_STATE`, and `ACCESS_NETWORK_STATE`.
- Call `Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.communication)` before WebRTC session setup.
- Clear Android communication device after call end.
- Speaker/Bluetooth selection is deferred unless required for a release blocker.

Windows:

- Use OS default microphone/output for V1.
- Surface microphone unavailable/blocked as typed failure.
- Preserve native error text in diagnostics, not UI.

## State Machine

Application phases:

```text
idle
preflighting
outgoingRinging
incomingRinging
accepted
negotiating
active
ending
failed
```

Terminal reasons:

```text
rejected
busy
microphoneDenied
ringingTimeout
answerTimeout
mediaIceTimeout
mediaNoRemoteAudio
mediaFailed
networkLost
remoteEnded
localEnded
expired
```

Rules:

- Only one active or ringing call globally.
- A failed call can be replaced by a new call after cleanup.
- A terminal call cannot return to active.
- Stale Firebase snapshots must be ignored after local call epoch changes.
- Candidate delivery is accepted by `callId`, role, and terminal-state checks, not by a single global sequence gate.

## Diagnostics

User UI shows short typed messages only:

- `Microphone permission required.`
- `Peer is busy.`
- `Call timed out.`
- `Call media could not connect. Try again.`
- `Finish the call first.`

Diagnostics keep:

- callId
- peer IDs
- platform
- ICE servers shape without credentials
- local/remote candidate counts
- selected route type when known
- ICE state history
- peer connection state history
- SDP operation being applied when failure occurred
- native WebRTC exception text

Diagnostics must not log raw SDP, raw ICE candidates, TURN credentials, passwords, or message content.

## Testing Requirements

Unit tests:

- Voice signaling DTO parsing and invalid payload rejection.
- Pair lock behavior and simultaneous-call glare.
- Candidate-before-SDP buffering.
- Repeated calls create fresh peer connections.
- Mic denied cleanup.
- Hangup cleanup.
- Active call blocks file transfer and allows chat.
- Stale call snapshots ignored after cleanup.

Firebase emulator tests:

- Friends can create/read/update call rooms.
- Non-friends are denied.
- Blocked users are denied.
- Third user is denied.
- Caller-only offer writes.
- Callee-only answer writes.
- Role-specific ICE writes.
- Payload size limits.
- Expired call cleanup.
- Ringing works without preconnected chat peer.

Widget/runtime tests:

- Call button enabled only for accepted friends.
- Incoming ringing UI.
- Accept/reject/hangup/mute.
- Failure messages.
- Logout/dispose cleanup.
- Network loss during ringing and active call.

Standard non-platform validation:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

## Manual Device Release Gate

Use same commit and same artifacts for every manual row.

Required devices:

- One physical Android arm64 device.
- One Windows 10/11 machine.

Required scenarios:

- Windows to Android, direct route.
- Android to Windows, direct route.
- Windows to Android, TURN-only route.
- Android to Windows, TURN-only route.
- Direct blocked then relay fallback.
- Android mic denied.
- Windows mic blocked/unavailable.
- Caller hangup.
- Callee hangup.
- Network loss during ringing.
- Network loss during active call.
- Five repeated calls without app restart.
- Chat during active call.
- File transfer blocked during active call.

Evidence:

- Git commit.
- Artifact SHA256s.
- Android model/version.
- Windows version.
- ICE/TURN config used.
- Screenshots of route/call state.
- Filtered `adb logcat`.
- Rain diagnostics export.
- Sanitized Firebase lifecycle export.
- Pass/fail notes.

## Phased Implementation Plan

### Phase 00: Architecture Lock

Create and commit this spec plus any ADR updates. No build.

### Phase 01: Freeze Old Media Path

Mark control-channel voice signaling as legacy and block new runtime use. Chat/control/file data channels remain unchanged. Commit.

### Phase 02: Firebase Voice Signaling Contract

Add `VoiceSignalingAdapter`, call room models, call status enums, role models, and fake adapter tests. Commit.

### Phase 03: Firebase Implementation

Implement RTDB voice call rooms, inboxes, active pair locks, rules, encrypted SDP/ICE writes, and cleanup function updates. Add emulator tests. Commit.

### Phase 04: Dedicated Media Core

Harden `VoiceMediaConnection` for fresh-PC-per-call behavior, audio lifecycle, remote audio retention, diagnostics, and idempotent cleanup. Commit.

### Phase 05: Runtime Integration

Rewrite app voice runtime to use Firebase signaling. Remove `connectPeer()` as call prerequisite. Keep chat usable and block file transfer during calls. Commit.

### Phase 06: UI/Error Handling

Update call button, incoming ring, active call controls, mute, hangup, typed errors, and diagnostics surfaces. Commit.

### Phase 07: Test/Harness Gate

Run non-platform validation and Firebase emulator tests. Fix failures in committed increments. No Android/Windows builds. Commit final test fixes.

### Phase 08: Final Build/Release Gate

Only after Phase 07 passes, build Android and Windows artifacts. Then run physical device manual gate. Create PR only after same-commit manual proof passes or document blockers explicitly.

## Acceptance Criteria

The voice-call rebuild is accepted only when:

- Voice ringing works without a preconnected chat peer.
- Android to Windows and Windows to Android calls reach active with audible two-way audio.
- TURN-only mode works.
- Repeated calls do not leave stale busy state or disposed transceiver failures.
- Mic denial is clean and typed on both sides.
- Chat remains usable during active call.
- File transfer is blocked during active call.
- Firebase rules prevent nonparticipant access.
- Final tests and final platform builds pass.
- Manual device gate evidence is recorded.

## Open Risks

- Real-world network variability cannot be fully proven in CI.
- TURN infrastructure must be production-owned; public demo TURN is not acceptable for production.
- Android vendor audio routing can still vary by device.
- Windows privacy settings can block mic capture outside app control.
- Firebase RTDB rules complexity can create false denies; emulator contract tests are mandatory.
