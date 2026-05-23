# Voice Call Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish Rain voice calls with an in-call overlay, minimizable call controls, real audio activity visualization, mic/device settings, local deafen, non-interrupting sound effects, and stronger call hardening without breaking the working dedicated WebRTC voice path.

**Architecture:** Keep the locked voice architecture: one fresh dedicated audio-only `RTCPeerConnection` per call, Firebase ephemeral signaling, and WebRTC media tracks for microphone audio. Add UI/runtime polish around that path instead of replacing it; shared call-surface and media-device abstractions must be compatible with future video calls.

**Tech Stack:** Flutter, Riverpod, `flutter_webrtc` 1.4.1, `audioplayers` 6.6.0, Firebase Realtime Database signaling, existing Rain packages (`peer_core`, `protocol_brain`, `rain_core`, `apps/rain`), Melos validation.

---

## Hard Rules

- Do not move voice packets through Dart, Firebase, Drift, chat data channels, or file channels.
- Do not change the chat/data `RTCPeerConnection`; it remains data-only.
- Do not let chat-panel ownership hide or destroy call controls; the call surface must be app-scoped.
- Do not fake the sound-wave meter as "real" audio. Use WebRTC stats/track activity; if unavailable, show a clear inactive/unsupported state.
- Do not request Android/iOS audio focus for short UI sound effects; SFX must mix with other phone audio when possible.
- Do not add call history.
- Do not persist private device names to Firebase.
- Do not break current audio-only calls, file-transfer blocking during calls, chat usability during calls, or release key/build gates.
- Commit after every completed phase.

## Existing Facts

- Current voice media core lives in `packages/peer_core/lib/src/voice/voice_media_connection.dart`.
- Current call state lives in `apps/rain/lib/application/runtime/voice_call_state.dart`.
- Current call runtime lives in `apps/rain/lib/application/runtime/voice_call_runtime.dart` as part of `RainRuntimeController`.
- Current UI call panel is `RainVoiceCallPanel` in `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`, placed from `apps/rain/lib/presentation/widgets/home/chat_panel.dart`; this is conversation-scoped and must be moved to an app-scoped surface.
- Current settings are minimal and stored through `apps/rain/lib/infrastructure/services/app_settings_store.dart`.
- Current SFX service is `apps/rain/lib/infrastructure/services/sound_effects_service.dart` using `audioplayers`.
- `flutter_webrtc` exposes `navigator.mediaDevices.enumerateDevices()`, `Helper.selectAudioInput`, `Helper.selectAudioOutput`, speaker routing helpers, Android communication audio configuration, and `getStats()`.
- `audioplayers` supports `AudioContextConfigFocus.mixWithOthers`; on Android that maps to no audio focus, and on iOS it maps to `mixWithOthers`.
- Existing `VoiceCallSession` sequence handling must be checked for candidate/SDP races because ICE can arrive before SDP and must not make a later offer/answer look stale.

---

## Phase 00: Architecture Lock And Baseline

**Purpose:** Protect the finally-working call path before UI/device polish starts.

**Files:**
- Read: `docs/architecture/voice-call-architecture-lock.md`
- Read: `docs/superpowers/plans/2026-05-23-video-call-v2.md`
- Modify: `docs/superpowers/plans/2026-05-23-voice-call-polish.md`

- [x] Confirm this plan keeps dedicated voice media peer connections.
- [x] Confirm no DB migration is needed for overlay state, selected mic, deafen, or sound settings; these are local app preferences.
- [x] Confirm Firebase changes are postponed unless a phase proves a signaling/capability field is required.
- [x] Run focused baseline tests before touching code:

```powershell
flutter test packages\peer_core\test\voice_media_connection_test.dart
Push-Location apps\rain
flutter test test\friend_flow_test.dart
flutter test test\rain_chat_widgets_test.dart
Pop-Location
```

- [x] Commit only the plan if this phase changes docs:

```powershell
git add docs\superpowers\plans\2026-05-23-voice-call-polish.md
git commit -m "docs: record voice call polish baseline"
```

## Phase 01: Baseline Freeze And Signaling Race Hardening

**Purpose:** Fix the riskiest correctness issue before adding new polish.

**Files:**
- Modify: `packages/protocol_brain/lib/src/voice_call_session.dart`
- Modify: `packages/protocol_brain/test/voice_call_session_test.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/test/friend_flow_test.dart`

**Design:**
- Keep SDP sequencing separate from ICE candidate sequencing.
- Reject stale offers/answers by `callId`, `sessionEpoch`, and media SDP sequence.
- Do not let a later ICE candidate sequence make a valid offer/answer look stale.
- Ignore late candidate/answer/offer frames after local hangup or dispose.
- Preserve current Firebase dedicated signaling path.
- Preserve current legacy control-channel voice ignore behavior.
- Ensure active pair lock releases on hangup, failure, timeout, logout, and dispose.

**Tests:**
- Candidate before answer does not stale-drop the answer.
- Candidate before offer does not stale-drop the offer.
- Late answer after hangup is ignored.
- Late candidate after dispose is ignored.
- Busy lock releases on every terminal path.
- Repeat call after failure creates a fresh call id and session.

**Validation:**

```powershell
flutter test packages\protocol_brain\test\voice_call_session_test.dart
flutter test apps\rain\test\friend_flow_test.dart
```

**Commit:**

```powershell
git add packages\protocol_brain\lib\src\voice_call_session.dart packages\protocol_brain\test\voice_call_session_test.dart apps\rain\lib\application\runtime\voice_call_runtime.dart apps\rain\test\friend_flow_test.dart
git commit -m "fix: harden voice call signaling races"
```

## Phase 02: App-Scoped Call UI State Model

**Purpose:** Add a safe UI-only call surface state before drawing the popup.

**Files:**
- Create: `apps/rain/lib/application/state/call_surface_providers.dart`
- Create: `apps/rain/test/call_surface_providers_test.dart`
- Modify: `apps/rain/lib/application/state/runtime_providers.dart` only if provider exports need wiring.
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart` for app-level listener placement.

**Design:**
- Add `CallSurfaceMode.expanded`, `CallSurfaceMode.minimized`.
- Add `CallSurfaceDock.chatCenter`, `CallSurfaceDock.chatTop`, `CallSurfaceDock.bottomSafe`.
- Store only UI preference in Riverpod state first; persist later only if useful.
- Reset to expanded for incoming ringing and new outgoing call.
- Keep minimized state when call becomes active.
- Force hidden when `VoiceCallPhase.idle`.
- Keep state app-scoped so switching chats/back navigation cannot hide active call controls.

**Tests:**
- New incoming call expands.
- Outgoing call expands.
- Active call can minimize.
- Failed/ended call clears surface state.
- Surface state never changes `VoiceCallState`.
- Switching selected chat does not hide active call surface.

**Validation:**

```powershell
flutter test apps\rain\test\call_surface_providers_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\application\state\call_surface_providers.dart apps\rain\test\call_surface_providers_test.dart apps\rain\lib\application\state\runtime_providers.dart apps\rain\lib\presentation\screens\home_screen.dart
git commit -m "feat: add voice call surface state"
```

## Phase 03: In-Call Overlay And Minimized Chip

**Purpose:** Replace the embedded card feeling with a proper call popup that can minimize while chat remains usable.

**Files:**
- Create: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Create: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/chat_panel.dart` only to remove embedded ownership or keep a contextual entry point.
- Modify: `apps/rain/test/rain_chat_widgets_test.dart`

**UI behavior:**
- Expanded call surface is a square-ish floating panel centered inside the chat area.
- Mobile: width `min(360, availableWidth - 32)`, aspect ratio near `1:1`, safe from bottom nav and keyboard.
- Desktop: width `360-420`, centered in current chat panel.
- Minimized chip docks above composer or near top of chat, never blocking message input.
- Incoming ringing: accept/reject primary controls.
- Outgoing/connecting: peer info, spinner/waves idle, cancel/hangup.
- Active: peer, elapsed time, route summary, local mute, deafen, mic menu entry, hangup, minimize.
- Failed: sanitized reason, retry, dismiss.
- Chat messages remain scrollable behind overlay; minimized mode must not intercept the whole chat.
- Call controls remain reachable after switching conversations.

**Tests:**
- Expanded panel appears only for current peer call.
- Minimize hides large panel and shows chip.
- Restore from chip returns expanded panel.
- Controls still call `accept`, `reject`, `hangUp`, `setMuted`.
- Composer stays reachable while minimized.
- Narrow mobile layout has no overflow.
- Switching chats keeps active call overlay visible.
- Back navigation does not orphan call controls.

**Validation:**

```powershell
flutter test apps\rain\test\rain_chat_widgets_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\presentation\widgets apps\rain\lib\presentation\screens\home_screen.dart apps\rain\test\rain_chat_widgets_test.dart
git commit -m "feat: add minimizable voice call overlay"
```

## Phase 04: Real Audio Activity Meter

**Purpose:** Drive the middle sound-wave icon from real call audio activity.

**Files:**
- Modify: `packages/peer_core/lib/src/voice/voice_media_models.dart`
- Modify: `packages/peer_core/lib/src/voice/voice_media_connection.dart`
- Modify: `packages/peer_core/test/voice_media_connection_test.dart`
- Create: `apps/rain/lib/application/runtime/voice_audio_level.dart`
- Create: `apps/rain/test/voice_audio_level_test.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_state.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`

**Design:**
- Sample WebRTC stats from the active dedicated media peer at a low rate, for example every 250 ms while active.
- Prefer inbound remote audio stats keys such as `audioLevel`, `totalAudioEnergy`, and `totalSamplesDuration`.
- Use local microphone track stats only for local mic activity indicators.
- Never inspect or copy raw RTP/audio packets in Dart.
- Subscribe to remote track events in the session/runtime path; do not rely only on ICE connected to infer audible media.
- Add `VoiceAudioLevel.remoteLevel`, `localLevel`, `updatedAt`, and `source`.
- If stats are absent on a platform, emit `VoiceAudioLevel.unavailable` and show a calm idle icon, not fake waves.
- Stop sampler immediately on hangup/dispose.

**Tests:**
- Parses stats with `audioLevel`.
- Derives level delta from `totalAudioEnergy` and `totalSamplesDuration`.
- Clamps invalid values to `0..1`.
- Stops sampling after call ends.
- Late stats after dispose are ignored.
- UI wave amplitude changes from provided level.
- UI shows inactive/unsupported state when unavailable.

**Validation:**

```powershell
flutter test apps\rain\test\voice_audio_level_test.dart
flutter test packages\peer_core\test\voice_media_connection_test.dart
flutter test apps\rain\test\rain_chat_widgets_test.dart
```

**Commit:**

```powershell
git add packages\peer_core apps\rain\lib\application\runtime apps\rain\lib\presentation\widgets\rain_chat_widgets.dart apps\rain\test packages\peer_core\test
git commit -m "feat: add voice call audio activity meter"
```

## Phase 05: Media Device Inventory And Mic Selection

**Purpose:** Let users choose the microphone without destabilizing calls.

**Files:**
- Modify: `packages/peer_core/lib/src/platform_bridge.dart`
- Modify: `packages/peer_core/lib/src/voice/voice_media_connection.dart`
- Modify: `packages/peer_core/test/voice_media_connection_test.dart`
- Create: `apps/rain/lib/application/runtime/media_device_settings.dart`
- Create: `apps/rain/test/media_device_settings_test.dart`
- Modify: `apps/rain/lib/infrastructure/services/app_settings_store.dart`
- Modify: `apps/rain/test/app_settings_store_test.dart`
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Modify: `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`

**Design:**
- Add platform bridge methods:
  - `enumerateMediaDevices()`
  - `selectAudioInput(String deviceId)`
  - `selectAudioOutput(String deviceId)`
  - `setSpeakerphoneOn(bool enabled)`
  - `setSpeakerphoneOnButPreferBluetooth()`
- Persist selected microphone `deviceId` locally in SharedPreferences, not Firebase.
- Use selected mic when creating local audio:

```dart
{
  'audio': {
    'deviceId': selectedDeviceId,
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
  },
  'video': false,
}
```

- If selected mic is missing, fall back to default and show one non-blocking warning.
- Active-call mic switching is phase-gated:
  - first implementation may apply to next call only;
  - active-call switching needs separate tests using `selectAudioInput` or safe track replacement before enabling.

**Tests:**
- Device list filters `audioinput`.
- Selected mic persists locally.
- Missing selected mic falls back to default.
- `getUserMedia` receives selected `deviceId`.
- Permission denied remains typed as microphone denied.
- Settings UI handles empty device list.

**Validation:**

```powershell
flutter test apps\rain\test\media_device_settings_test.dart
flutter test apps\rain\test\app_settings_store_test.dart
flutter test packages\peer_core\test\voice_media_connection_test.dart
```

**Commit:**

```powershell
git add packages\peer_core apps\rain\lib\application\runtime\media_device_settings.dart apps\rain\lib\infrastructure\services\app_settings_store.dart apps\rain\lib\presentation apps\rain\test packages\peer_core\test
git commit -m "feat: add voice microphone selection"
```

## Phase 06: Deafen And Output Routing

**Purpose:** Add local-only deafen and route controls without signaling false mute state to the peer.

**Files:**
- Modify: `apps/rain/lib/application/runtime/voice_call_state.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `packages/peer_core/lib/src/voice/voice_media_connection.dart`
- Modify: `packages/peer_core/lib/src/voice/voice_media_models.dart`
- Modify: `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
- Modify: `apps/rain/test/friend_flow_test.dart`
- Modify: `apps/rain/test/rain_chat_widgets_test.dart`
- Modify: `packages/peer_core/test/voice_media_connection_test.dart`

**Design:**
- `deafen` is local only: user does not hear remote audio.
- Do not send `mute` frame for deafen.
- Add `isDeafened` to `VoiceCallState`.
- Disable/enable retained remote audio tracks through media core.
- Decide explicitly in code/tests that deafen does not imply microphone mute for V1.
- Keep mic mute independent.
- Add speaker/Bluetooth output actions where supported by `flutter_webrtc` helpers.
- If output route selection fails, keep call alive and show a small warning.

**Tests:**
- Deafen disables remote audio locally.
- Undeafen restores remote audio.
- Deafen does not send a mute frame.
- Peer mute state remains separate from deafen state.
- Hangup clears deafen state.
- Unsupported route selection does not fail call.

**Validation:**

```powershell
flutter test packages\peer_core\test\voice_media_connection_test.dart
flutter test apps\rain\test\friend_flow_test.dart
flutter test apps\rain\test\rain_chat_widgets_test.dart
```

**Commit:**

```powershell
git add packages\peer_core apps\rain\lib\application\runtime apps\rain\lib\presentation\widgets\rain_chat_widgets.dart apps\rain\test packages\peer_core\test
git commit -m "feat: add voice call deafen"
```

## Phase 07: Non-Interrupting Sound Effects

**Purpose:** Expand call/action sounds while preventing short Rain sounds from pausing music on the phone.

**Files:**
- Modify: `apps/rain/lib/infrastructure/services/sound_effects_service.dart`
- Modify: `apps/rain/lib/application/state/core_providers.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- Modify: `apps/rain/lib/presentation/screens/onboarding_screen.dart`
- Modify: `apps/rain/test/sound_effects_assets_test.dart`
- Create or modify: `apps/rain/test/sound_effects_service_test.dart`
- Add assets under: `apps/rain/assets/sounds/`

**Design:**
- Expand enum:
  - `send`
  - `receive`
  - `action`
  - `error`
  - `callIncoming`
  - `callOutgoing`
  - `callConnected`
  - `callEnded`
  - `callFailed`
  - `mute`
  - `unmute`
  - `deafen`
  - `undeafen`
- Configure SFX players with low latency and mix-with-others context:

```dart
AudioContextConfig(
  route: AudioContextConfigRoute.system,
  focus: AudioContextConfigFocus.mixWithOthers,
  respectSilence: false,
  stayAwake: false,
).build()
```

- Never use `AudioContextConfigFocus.gain` for short SFX.
- Use very short WAV assets, normalized volume, no clipping.
- Throttle repeated effects so message bursts do not spam audio.
- Add settings later only if user wants full sound customization; keep this phase focused.
- During active voice call, play only critical call sounds at lower volume or skip non-critical message SFX to avoid echo/annoyance.

**Tests:**
- Service sets mix-with-others context.
- No SFX path requests audio focus gain.
- Missing plugin disables SFX without crashing.
- New sound assets are present and short.
- Burst throttle suppresses repeated receive sounds.
- Call actions trigger the right effect.

**Manual gate:**
- Start Spotify/YouTube/music on Android.
- Trigger send/receive/call action sounds.
- Music must keep playing; brief volume ducking is acceptable only if OS forces it, but pausing is a fail.

**Validation:**

```powershell
flutter test apps\rain\test\sound_effects_assets_test.dart
flutter test apps\rain\test\sound_effects_service_test.dart
flutter test apps\rain\test\rain_chat_widgets_test.dart
```

**Commit:**

```powershell
git add apps\rain\assets\sounds apps\rain\lib\infrastructure\services\sound_effects_service.dart apps\rain\lib\application\state\core_providers.dart apps\rain\lib\presentation apps\rain\test
git commit -m "feat: polish rain sound effects"
```

## Phase 08: Voice Runtime Hardening

**Purpose:** Reduce weird stuck/busy/late-callback failures without changing the successful call architecture.

**Files:**
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_state.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_diagnostics.dart`
- Modify: `packages/protocol_brain/lib/src/voice_call_session.dart`
- Modify: `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
- Modify: `packages/protocol_brain/test/voice_call_session_test.dart`
- Modify: `apps/rain/test/friend_flow_test.dart`
- Modify: `apps/rain/test/runtime_network_loss_test.dart`

**Hardening rules:**
- Every async media callback checks `callId`, `sessionEpoch`, and disposed state.
- Late ICE/SDP for ended call is ignored and logged.
- Busy locks are released on local hangup, remote hangup, failure, timeout, logout, app dispose, and network-loss cleanup.
- Firebase room terminal status wins over local stale state.
- Retry after failure creates a new call id and fresh media connection.
- Call cannot transition from `failed` back to `active`.
- App lifecycle detach/dispose always releases media and signaling locks.
- Diagnostics keep full native error; UI keeps sanitized user text.
- Verify no new code routes voice/video through legacy `DefaultPeerCore` media APIs.

**Tests:**
- Late remote answer after hangup ignored.
- Late candidate after dispose ignored.
- Retry after failed media creates fresh call id.
- Busy lock cleared on every terminal path.
- Network loss ends active call cleanly.
- Logout clears call state and media session.
- Voice call still blocks file transfer only while non-terminal.

**Validation:**

```powershell
flutter test packages\protocol_brain\test\voice_call_session_test.dart
flutter test apps\rain\test\friend_flow_test.dart
flutter test apps\rain\test\runtime_network_loss_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\application\runtime packages\protocol_brain apps\rain\test packages\protocol_brain\test
git commit -m "fix: harden voice call runtime"
```

## Phase 09: Settings Screen Polish

**Purpose:** Give users obvious control over call audio without hiding it inside chat.

**Files:**
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Modify: `apps/rain/lib/application/state/settings_providers.dart`
- Modify: `apps/rain/lib/infrastructure/services/app_settings_store.dart`
- Modify: `apps/rain/test/app_settings_store_test.dart`
- Add or modify: `apps/rain/test/settings_screen_test.dart`

**Settings:**
- Microphone selector.
- Refresh devices.
- Test selected microphone availability.
- Default speaker/Bluetooth preference if platform supports it.
- Sound effects on/off.
- Sound effects volume.
- Call sounds on/off.
- Optional: "reduce sounds during call".

**Tests:**
- Settings load defaults.
- Mic selection persists.
- SFX toggle persists.
- Call sounds toggle persists.
- Device refresh handles permission denied.
- UI does not overflow on narrow mobile.

**Validation:**

```powershell
flutter test apps\rain\test\app_settings_store_test.dart
flutter test apps\rain\test\settings_screen_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib\presentation\screens\settings_screen.dart apps\rain\lib\application\state\settings_providers.dart apps\rain\lib\infrastructure\services\app_settings_store.dart apps\rain\test
git commit -m "feat: add voice call audio settings"
```

## Phase 10: Future Video Compatibility Layer

**Purpose:** Make this polish reusable for video calls later, without implementing video now.

**Files:**
- Modify: `apps/rain/lib/presentation/widgets/rain_chat_widgets.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_state.dart`
- Modify: `docs/superpowers/plans/2026-05-23-video-call-v2.md` if needed.

**Design:**
- Name new UI surface generically where practical: `RainCallOverlay`, `RainCallControls`, `CallSurfaceMode`.
- Keep current provider name if renaming would create churn.
- Reserve layout slot for future `RTCVideoView`, but do not render video in this phase.
- Do not bolt future video onto audio-only `VoiceMediaConnection`; introduce generic call media files when the video phase starts.
- Keep call surface controls data-driven:
  - audio-only: mic, deafen, device, hangup
  - future video: mic, camera, switch camera, deafen, device, hangup
- Keep media-device model able to represent `audioinput`, `audiooutput`, and later `videoinput`.

**Tests:**
- Audio-only overlay renders without video dependencies.
- Adding a future video mode enum does not change current voice UI.
- No `RTCVideoRenderer` is initialized during audio-only calls.

**Validation:**

```powershell
flutter test apps\rain\test\rain_chat_widgets_test.dart
flutter test apps\rain\test\voice_audio_level_test.dart
```

**Commit:**

```powershell
git add apps\rain\lib docs\superpowers\plans\2026-05-23-video-call-v2.md apps\rain\test
git commit -m "refactor: prepare call surface for video"
```

## Phase 11: Full Automated Gate

**Purpose:** Prove the repo is still healthy before any installable build.

- [ ] Run:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

- [ ] Fix failures with focused commits.
- [ ] Do not build until automated gates pass.

**Commit if fixes were needed:**

```powershell
git status --short
git add <changed-files>
git commit -m "test: stabilize voice call polish"
```

## Phase 12: Manual Device Gate

**Purpose:** Catch the failures automated tests cannot catch: OEM audio focus, routing, real mic devices, and call lifecycle.

**Android manual matrix:**
- Music playing in another app, then Rain send/receive/call sounds: music must not pause.
- Incoming call sound while music plays.
- Outgoing call sound while music plays.
- Android to Android voice call.
- Android to Windows voice call.
- Windows to Android voice call.
- Minimize overlay, send chat, restore overlay.
- Mute/unmute mic.
- Deafen/undeafen remote audio.
- Real sound-wave: quiet room is flat, speech moves, muted mic changes local activity, deafen does not fake remote speech.
- Select default mic, restart app, confirm selection persists.
- Missing/disconnected selected mic falls back to default.
- Switch conversation during active call; overlay remains available.
- Hangup from caller.
- Hangup from callee.
- Failed call followed by successful retry.

**Windows manual matrix:**
- Default mic call.
- External mic if available.
- Deafen/undeafen.
- Overlay minimize/restore.
- Repeat calls without app restart.

**Acceptance:**
- At least 3 successful Android-to-Android calls.
- At least 3 successful Android-to-Windows calls.
- At least 3 successful Windows-to-Android calls.
- No stuck "peer busy" after hangup/failure.
- No lost chat/file-transfer behavior outside active call blocking.
- External music keeps playing while Rain SFX plays.

## Phase 13: Final Build And PR Gate

**Purpose:** Ship only after tests and real-device checks.

- [ ] Build only after Phase 10 and Phase 11 pass.
- [ ] Use one shared non-demo `RAIN_SIGNALING_ENCRYPTION_KEY`.
- [ ] Build Windows and Android from the same commit and same defines file.
- [ ] For old Android testing, build only `armeabi-v7a`.
- [ ] Verify APK ABI contents.
- [ ] Update PR body with:
  - automated validation results
  - manual device matrix
  - any unsupported audio-level/device-selection behavior
  - known OEM limitations

**Build helper:**

```powershell
pwsh -NoProfile -File scripts\build_stable_test_pair.ps1 -SmokeWindows
```

**Final validation:**

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

---

## Critical Risks

- Candidate/SDP sequence races can break otherwise valid Firebase signaling; hardening must happen before polish.
- Conversation-scoped call controls can make an active call feel stuck when users switch chats; the overlay must be app-scoped.
- Real remote audio level may not be exposed consistently by WebRTC stats on every platform. The UI must degrade honestly, not fake "real" waves.
- Android OEM audio focus behavior can still pause music despite correct `mixWithOthers` intent; this needs real-phone verification.
- Active-call mic switching can destabilize WebRTC on some platforms. Prefer "applies next call" first unless active replacement is proven.
- Deafen may not mute remote playback if Flutter WebRTC ignores remote track `enabled`; test before claiming support.
- Overlay can accidentally block chat input on mobile. Widget tests must include narrow widths and keyboard-safe layouts.
- Adding sound effects during calls can create echo or annoyance. Default to low volume and suppress non-critical SFX during active call.
- Future video compatibility must not introduce video renderer initialization during audio-only calls.
- Legacy media APIs still exist on `DefaultPeerCore`; future call work must not accidentally use the chat/data peer for media.

## Non-Goals For This Plan

- No video call implementation.
- No group calls.
- No screen sharing.
- No call recording.
- No push/background ringing.
- No call history.
- No server-side media relay.
