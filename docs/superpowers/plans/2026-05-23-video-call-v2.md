# WebRTC Video Call V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add reliable 1:1 camera video calls for accepted Rain friends on Android and Windows without breaking the working voice-call path.

**Architecture:** Reuse the proven dedicated per-call media `RTCPeerConnection`, but evolve it from audio-only to audio/video-capable. Firebase continues to signal SDP, ICE, room status, and call controls; WebRTC carries microphone and camera packets as RTP/RTCP over DTLS-SRTP. UI renders local/remote video with `RTCVideoRenderer` and keeps chat usable behind the call surface.

**Tech Stack:** Flutter, Riverpod, `flutter_webrtc` 1.4.1, Firebase Realtime Database signaling, existing Rain packages (`peer_core`, `protocol_brain`, `rain_core`, `apps/rain`), Melos CI, Android + Windows release builds.

---

## Hard Decisions

- Keep one active call globally.
- Keep file transfer blocked during any active audio/video call.
- Keep call media on a dedicated short-lived `RTCPeerConnection`; never put camera tracks on the chat/data peer connection.
- Keep audio-only calls working as first-class calls.
- Add direct video call first; audio-to-video upgrade can be a later feature after direct video is stable.
- Do not send raw camera frames through Firebase, Drift, chat data channels, or file channels.
- Do not add call recording, group calls, screen share, background ringing, or call history in this feature.
- Build only at final release gate.
- Commit every completed task.

## Packet Model

Correct video flow:

```text
Camera -> MediaStreamTrack(video) -> RTCPeerConnection sender
  -> VP8/H264 encode by native WebRTC
  -> RTP packets -> DTLS-SRTP encryption
  -> ICE selected candidate pair
  -> remote jitter buffer/decode
  -> MediaStreamTrack(video) -> RTCVideoRenderer -> RTCVideoView
```

Rain controls only:

```text
permission -> capture constraints -> addTrack -> SDP/ICE signaling
  -> renderer binding -> mute/camera controls -> diagnostics -> cleanup
```

## Verified API Basis

Checked against installed `flutter_webrtc` 1.4.1 and Context7 docs for `/flutter-webrtc/flutter-webrtc`:

- `navigator.mediaDevices.getUserMedia(...)` captures audio/video.
- `RTCPeerConnection.addTrack(...)` attaches tracks.
- `RTCPeerConnection.onTrack` emits remote tracks.
- `RTCVideoRenderer.initialize()`, `srcObject`, `onFirstFrameRendered`, `onResize`, and `dispose()` handle rendering.
- `RTCVideoView` renders a renderer.
- `Helper.switchCamera(videoTrack)` supports native camera switching.
- `RTCRtpSender.replaceTrack(...)` exists for later camera device replacement.
- Android needs `CAMERA` permission plus existing audio/network permissions.

## Success Criteria

- Android-to-Android video call connects with audio and remote video.
- Android-to-Windows video call connects with audio and remote video.
- Windows-to-Android video call connects with audio and remote video.
- Audio-only calls still pass exactly as before.
- Remote first video frame appears or a typed timeout error is shown.
- Camera off does not hang up call.
- Mic mute and camera mute are independent.
- Hangup always releases camera, microphone, renderer textures, and Firebase active call lock.
- APK still contains only requested ABI when built as v7a.
- Windows release starts without demo-key failure when built with shared release defines.

## File Map

### New Files

- `packages/peer_core/lib/src/call/call_media_models.dart`
  - Shared media models for audio/video calls: media mode, local/remote tracks, diagnostics, first-frame events.

- `packages/peer_core/lib/src/call/call_media_connection.dart`
  - Audio/video capable dedicated media connection.
  - Owns capture, SDP, ICE, track events, camera toggles, camera switching, and cleanup.

- `packages/peer_core/test/call_media_connection_test.dart`
  - Fake media tests for audio-only and video calls.

- `apps/rain/lib/application/runtime/video_call_renderers.dart`
  - Owns `RTCVideoRenderer` lifecycle outside protocol code.
  - Provides local/remote renderer handles to UI.

- `apps/rain/test/video_call_renderers_test.dart`
  - Renderer lifecycle tests with fake renderer factory.

### Modified Files

- `packages/peer_core/lib/peer_core.dart`
  - Export new call media models/connection.

- `packages/peer_core/lib/src/platform_bridge.dart`
  - Add camera capture helpers and renderer factory hooks for tests.

- `packages/peer_core/lib/src/voice/voice_media_connection.dart`
  - Keep as compatibility wrapper or migrate callers to `CallMediaConnection`.

- `packages/peer_core/lib/src/voice/voice_media_models.dart`
  - Keep compatibility exports until app/runtime migration is complete.

- `packages/protocol_brain/lib/src/voice_call_frame.dart`
  - Add optional `mediaMode: audio|video`.
  - Add optional `cameraMuted`.
  - Preserve SDP/candidate text exactly.

- `packages/protocol_brain/lib/src/voice_call_session.dart`
  - Add video-aware session behavior while preserving audio-only behavior.

- `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
  - Add room-level media mode and camera state fields.

- `packages/protocol_brain/lib/adapters/signaling_adapter.dart`
  - Extend typed interfaces only where room metadata needs media mode.

- `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
  - Read/write media mode and camera state in Firebase call rooms.

- `packages/protocol_brain/lib/src/testing/fake_voice_signaling_adapter.dart`
  - Add fake room fields for tests.

- `apps/rain/lib/application/runtime/voice_call_state.dart`
  - Evolve state into audio/video call state without breaking provider names.
  - Add `mediaMode`, `isCameraMuted`, `isRemoteCameraMuted`, `hasRemoteVideo`, video failure reasons.
  - Reuse the Phase 10 compatibility layer (`CallMediaMode`, camera mute flags, and control capabilities) instead of creating a parallel video state model.

- `apps/rain/lib/application/runtime/voice_call_runtime.dart`
  - Add `startVideoCall`, video accept path, camera controls, renderer wiring, diagnostics.

- `apps/rain/lib/application/runtime/voice_call_diagnostics.dart`
  - Add camera/video diagnostics.

- `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
  - Add video call button and render video call panel/surface.

- `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
  - Add video call controls, local preview, remote video surface, camera buttons.
  - Extend the generic `RainCallPanel`/`RainCallControls` surfaces; keep `RainVoiceCallPanel` only as a compatibility alias while older call sites are migrated.

- `apps/rain/android/app/src/main/AndroidManifest.xml`
  - Add camera permission/features.

- `apps/rain/test/friend_flow_test.dart`
  - Add runtime video call flows.

- `apps/rain/test/rain_chat_widgets_test.dart`
  - Add video button, video panel, mute/camera/hangup tests.

- `packages/protocol_brain/test/voice_call_session_test.dart`
  - Add media-mode and camera-state protocol tests.

- `packages/protocol_brain/test/voice_signaling_contract_test.dart`
  - Add Firebase contract tests for media mode.

- `backend/firebase/database.rules.json`
  - Allow bounded new video metadata fields in voice call rooms.

- `packages/protocol_brain/test/firebase_contract_test.dart`
  - Assert Firebase rules accept only valid video call metadata.

---

## Phase 00: Architecture Lock

**Purpose:** Stop design drift before code starts.

- [x] Confirm feature scope in `docs/superpowers/plans/2026-05-23-video-call-v2.md`.
- [x] Lock non-goals: no group calls, screen share, recording, background service, call history, audio-to-video upgrade.
- [x] Lock architecture: dedicated media PC per call, Firebase signaling, WebRTC RTP media.
- [x] Commit:

```powershell
git add docs/superpowers/plans/2026-05-23-video-call-v2.md
git commit -m "docs: plan video call v2"
```

## Phase 01: Contract And Compatibility Tests

**Purpose:** Make protocol understand audio vs video before touching capture.

- [x] Add failing tests in `packages/rain_core/test/voice_call_frame_test.dart`:
  - video invite round-trips `mediaMode: video`
  - audio invite defaults to `mediaMode: audio`
  - `cameraMuted` only allowed on mute/control frames
  - SDP still preserved byte-for-byte
  - invalid `mediaMode` rejected

- [x] Add failing tests in `packages/protocol_brain/test/voice_call_session_test.dart`:
  - video call sends invite with `mediaMode: video`
  - audio call behavior unchanged
  - stale video offer ignored by `callId`, `sessionEpoch`, and `seq`
  - camera mute frame changes remote camera state only

- [x] Implement minimal fields:
  - `VoiceCallFrame.mediaMode`
  - `VoiceCallFrame.cameraMuted`
  - `CallMediaMode.audio`
  - `CallMediaMode.video`

- [x] Run:

```powershell
flutter test packages\rain_core\test\voice_call_frame_test.dart
flutter test packages\protocol_brain\test\voice_call_session_test.dart
```

- [x] Commit:

```powershell
git add packages\rain_core\test\voice_call_frame_test.dart packages\protocol_brain\test\voice_call_session_test.dart packages\protocol_brain\lib\src\voice_call_frame.dart packages\rain_core\lib\voice_call\voice_call_frame.dart
git commit -m "feat: add video call signaling contract"
```

## Phase 02: Firebase Signaling Metadata

**Purpose:** Store call media mode and camera state safely.

- [x] Add failing tests in `packages/protocol_brain/test/voice_signaling_contract_test.dart`:
  - create video call room stores `mediaMode: video`
  - old room with missing `mediaMode` reads as audio
  - invalid `mediaMode` rejected
  - terminal cleanup still releases active pair lock

- [x] Add failing tests in `packages/protocol_brain/test/firebase_contract_test.dart`:
  - rules allow `mediaMode: audio|video`
  - rules reject unknown mode
  - rules allow bounded `cameraMuted` boolean
  - rules reject oversized/new unsafe fields

- [x] Modify:
  - `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
  - `packages/protocol_brain/lib/adapters/signaling_adapter.dart`
  - `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
  - `packages/protocol_brain/lib/src/testing/fake_voice_signaling_adapter.dart`
  - `backend/firebase/database.rules.json`

- [x] Run:

```powershell
flutter test packages\protocol_brain\test\voice_signaling_contract_test.dart
flutter test packages\protocol_brain\test\firebase_contract_test.dart
```

- [x] Commit:

```powershell
git add packages\protocol_brain backend\firebase
git commit -m "feat: add video call firebase signaling metadata"
```

## Phase 03: Dedicated Audio/Video Media Core

**Purpose:** Capture camera/mic and negotiate audio/video on the dedicated media peer.

- [x] Create `packages/peer_core/lib/src/call/call_media_models.dart`.
- [x] Create `packages/peer_core/lib/src/call/call_media_connection.dart`.
- [x] Add tests in `packages/peer_core/test/call_media_connection_test.dart`:
  - audio mode requests audio only and `OfferToReceiveVideo: false`
  - video mode requests audio + video and `OfferToReceiveVideo: true`
  - camera denied fails before invite
  - no camera track gives typed camera failure
  - local video track is added before offer
  - remote video track emits event
  - local/remote candidates still buffer before remote SDP
  - camera mute disables video track without renegotiation
  - mic mute still uses platform mute helper
  - switch camera calls `Helper.switchCamera`
  - dispose stops audio/video tracks and closes PC
  - repeated calls create fresh peer connections

- [x] Use native-shaped SDP constraints:

```dart
{
  'mandatory': {
    'OfferToReceiveAudio': true,
    'OfferToReceiveVideo': true,
  },
  'optional': [],
}
```

- [x] Use video capture constraints:

```dart
{
  'audio': {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
  },
  'video': {
    'facingMode': 'user',
    'mandatory': {
      'minWidth': '320',
      'minHeight': '240',
      'maxWidth': '640',
      'maxHeight': '480',
      'minFrameRate': '15',
      'maxFrameRate': '30',
    },
    'optional': [],
  },
}
```

- [x] Keep voice compatibility wrapper until runtime migration is complete.
- [x] Run:

```powershell
flutter test packages\peer_core\test\call_media_connection_test.dart
flutter test packages\peer_core\test\voice_media_connection_test.dart
```

- [x] Commit:

```powershell
git add packages\peer_core
git commit -m "feat: add audio video call media core"
```

## Phase 04: Renderer Lifecycle

**Purpose:** Keep UI renderer textures out of protocol/media logic.

- [x] Create `apps/rain/lib/application/runtime/video_call_renderers.dart`.
- [x] Add renderer factory abstraction so tests do not need native textures.
- [x] Add tests in `apps/rain/test/video_call_renderers_test.dart`:
  - initializes local and remote renderers once
  - assigns local stream to local renderer
  - assigns remote stream when remote video arrives
  - clears renderer `srcObject` on hangup
  - disposes renderers idempotently
  - first-frame event updates state

- [x] Wire first-frame diagnostics:
  - local preview first frame
  - remote first frame
  - remote video timeout

- [x] Run:

```powershell
flutter test apps\rain\test\video_call_renderers_test.dart
```

- [x] Commit:

```powershell
git add apps\rain\lib\application\runtime\video_call_renderers.dart apps\rain\test\video_call_renderers_test.dart
git commit -m "feat: manage video call renderers"
```

## Phase 05: Runtime Integration

**Purpose:** Add video call behavior without breaking voice calls.

- [x] Extend `apps/rain/lib/application/runtime/voice_call_state.dart`:
  - `mediaMode`
  - `isCameraMuted`
  - `isRemoteCameraMuted`
  - `hasLocalVideo`
  - `hasRemoteVideo`
  - `cameraDenied`
  - `remoteCameraDenied`
  - `videoFirstFrameTimeout`

- [x] Add runtime methods in `apps/rain/lib/application/runtime/voice_call_runtime.dart`:
  - `startVideoCall(String username)`
  - `setVideoCallCameraMuted(bool muted)`
  - `switchVideoCallCamera()`

- [x] Add tests in `apps/rain/test/friend_flow_test.dart`:
  - video call preflights mic + camera before Firebase invite
  - camera denied never sends invite
  - incoming video accept preflights camera before accept
  - remote camera denied maps to typed UI failure
  - video call blocks file transfer
  - active file transfer blocks video call
  - hangup releases Firebase room and media
  - logout/dispose releases camera/mic/renderers
  - voice call still works after video call hangup
  - video call still works after failed voice call

- [x] Keep current voice provider names unless rename is required by compiler.
- [x] Run:

```powershell
flutter test apps\rain\test\friend_flow_test.dart
```

- [x] Commit:

```powershell
git add apps\rain\lib\application\runtime apps\rain\test\friend_flow_test.dart
git commit -m "feat: add video call runtime"
```

## Phase 06: UI And Error Handling

**Purpose:** Give user real video controls and safe failures.

- [x] Add video call button beside voice button in `apps/rain/lib/presentation/widgets/home/chat_panel.dart`.
- [x] Add/extend widgets in `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`:
  - remote video surface
  - local preview
  - mic toggle
  - camera toggle
  - switch camera
  - hangup
  - retry after permission failure
  - typed failure banner

- [x] Mobile layout:
  - remote video fills call area
  - local preview fixed aspect ratio
  - controls do not overlap bottom nav
  - chat remains reachable

- [x] Desktop layout:
  - remote video uses available panel width
  - local preview anchored top/right
  - controls remain visible on narrow window

- [x] Add widget tests in `apps/rain/test/rain_chat_widgets_test.dart`:
  - video call button disabled during active transfer
  - video call button disabled during another call
  - incoming video ring actions wired
  - active video controls wired
  - camera muted state visible
  - remote camera muted state visible
  - camera permission failure offers retry
  - native camera/WebRTC errors are sanitized

- [x] Run:

```powershell
flutter test apps\rain\test\rain_chat_widgets_test.dart
```

- [x] Commit:

```powershell
git add apps\rain\lib\presentation apps\rain\test\rain_chat_widgets_test.dart
git commit -m "feat: add video call ui"
```

## Phase 07: Platform Gates

**Purpose:** Add required platform permissions and release checks.

- [x] Update `apps/rain/android/app/src/main/AndroidManifest.xml`:

```xml
<uses-feature android:name="android.hardware.camera" android:required="false" />
<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
<uses-permission android:name="android.permission.CAMERA" />
```

- [x] Keep existing:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

- [x] Windows:
  - no manifest change expected for camera
  - document that Windows privacy settings must allow camera and microphone

- [x] Add tests in `packages/protocol_brain/test/release_contract_test.dart`:
  - Android manifest contains `CAMERA`
  - Android manifest keeps audio/network permissions
  - release docs mention same non-demo signaling key for Windows/APK pair
  - release docs mention camera/mic OS permission checks

- [x] Run:

```powershell
flutter test packages\protocol_brain\test\release_contract_test.dart
```

- [x] Commit:

```powershell
git add apps\rain\android packages\protocol_brain\test\release_contract_test.dart docs
git commit -m "chore: add video call platform gates"
```

## Phase 08: Diagnostics And Quality Gates

**Purpose:** Make failures debuggable without exposing raw native spam to normal UI.

- [ ] Extend `apps/rain/lib/application/runtime/voice_call_diagnostics.dart`:
  - `mediaMode`
  - local/remote audio track counts
  - local/remote video track counts
  - first local video frame timestamp
  - first remote video frame timestamp
  - selected candidate route
  - ICE state history
  - camera permission failure detail
  - sanitized UI error detail

- [ ] Add tests:
  - diagnostics include video counters
  - UI hides raw `RTCRtpTransceiver`/native errors
  - export contains full native error for developer diagnosis

- [ ] Add runtime failure rules:
  - no remote video first frame within timeout -> show `Video could not connect. Try again.`
  - audio connected but remote camera off -> stay active, show peer camera off
  - ICE failed -> hangup with typed media failure
  - app pause/background -> keep call if OS allows, otherwise fail cleanly and release camera

- [ ] Run:

```powershell
flutter test apps\rain\test\crash_diagnostics_service_test.dart
flutter test apps\rain\test\rain_chat_widgets_test.dart
```

- [ ] Commit:

```powershell
git add apps\rain\lib\application\runtime apps\rain\test
git commit -m "feat: add video call diagnostics"
```

## Phase 09: Full Validation

**Purpose:** Prove codebase health before any installable artifact.

- [ ] Run:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

- [ ] Fix failures with focused commits.
- [ ] Do not build yet.
- [ ] Commit final test fixes:

```powershell
git status --short
git add <changed-files>
git commit -m "test: stabilize video call coverage"
```

## Phase 10: Manual Device Gate

**Purpose:** Prove real camera/media behavior before release claim.

- [ ] Build only now, after all tests pass.
- [ ] Build Windows and Android with the same release defines file.
- [ ] Build v7a APK only when testing old Android phone.
- [ ] Test matrix:
  - Android v7a -> Android v7a video call
  - Android v7a -> Windows video call
  - Windows -> Android v7a video call
  - Android camera denied
  - Windows camera denied/privacy blocked
  - camera mute/unmute
  - mic mute/unmute
  - switch camera on Android
  - hangup from caller
  - hangup from callee
  - failed call followed by successful retry
  - voice call after video call
  - video call after voice call

- [ ] Capture diagnostics for every failed run.
- [ ] Do not mark complete until at least:
  - 3 successful Android-to-Android calls
  - 3 successful Android-to-Windows calls
  - 3 successful Windows-to-Android calls

## Phase 11: Final Build And Release Gate

**Purpose:** Produce usable artifacts without repeating the demo-key mistake.

- [ ] Generate one shared non-demo `RAIN_SIGNALING_ENCRYPTION_KEY`.
- [ ] Use same `--dart-define-from-file` for Windows and APK.
- [ ] Build Windows release.
- [ ] Build Android v7a release APK.
- [ ] Verify APK contains only `armeabi-v7a`.
- [ ] Smoke launch Windows release.
- [ ] Install APK on target Android device.
- [ ] Confirm both artifacts talk to each other.
- [ ] Commit release doc updates only if docs changed.

Commands:

```powershell
cd "D:\old project\Rain"
dart pub get
dart run melos run analyze
dart run melos run test

cd "D:\old project\Rain\apps\rain"
flutter build windows --release --dart-define-from-file="$env:TEMP\rain-release-defines.json"

$env:RAIN_RELEASE_STORE_FILE = "$env:USERPROFILE\.android\debug.keystore"
$env:RAIN_RELEASE_STORE_PASSWORD = "android"
$env:RAIN_RELEASE_KEY_ALIAS = "androiddebugkey"
$env:RAIN_RELEASE_KEY_PASSWORD = "android"
flutter build apk --release --split-per-abi --target-platform android-arm --dart-define-from-file="$env:TEMP\rain-release-defines.json"
```

## Risk Register

- Camera permission varies by Android OEM and Windows privacy settings.
- Some Android v7a devices may have weak CPU/GPU; use conservative 640x480/30fps max.
- Public TURN/OpenRelay can still be flaky; production needs owned TURN or broker.
- Remote video first frame may fail while audio works; handle as typed video failure, not generic call failure.
- `RTCVideoRenderer` texture leaks can break later calls; renderer lifecycle must be tested.
- Switching camera can fail on some devices; failure must keep call alive.
- Camera mute by disabling track should not force renegotiation.
- Audio-only path must not regress.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-23-video-call-v2.md`.

Two execution options:

1. **Subagent-Driven (recommended)** - dispatch fresh subagent per phase, review between phases, commit after each phase.
2. **Inline Execution** - execute phases in this session with checkpoints and commits.
