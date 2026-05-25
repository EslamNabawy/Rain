# Rain Call Runtime Stability Audit

Date: 2026-05-24

Branch: `codex/rain-rebrand-implementation`

Plan: `docs/superpowers/plans/2026-05-24-rain-call-runtime-stability-and-device-capability.md`

## Purpose

This audit locks the reported failures before implementation starts. The goal is to keep the fixes focused on the owning runtime layer instead of hiding stale call state with UI-only changes.

## Failure Taxonomy

| ID | Reported symptom | Primary owner layer | Suspected source area | Expected terminal state | Later test target |
| --- | --- | --- | --- | --- | --- |
| F00 | Startup loading screen appears while the bottom navigation bar is visible. | App shell/navigation | `apps/rain/lib/presentation/navigation/app_routes.dart`, `apps/rain/lib/presentation/screens/root_screen.dart`, `apps/rain/lib/main.dart` | Startup remains in splash until shell is ready. | Navigation shell test plus `root_screen_test.dart`. |
| F01 | PC to phone voice call says `peer busy` on first attempt, then retry causes a request to return to the PC before connecting. | Firebase call lease/signaling | `packages/protocol_brain/lib/adapters/firebase_adapter.dart`, `apps/rain/lib/application/runtime/voice_call_runtime.dart` | Failed or stale call becomes terminal and pair lock is released. | Firebase adapter contract test and runtime fake signaling test. |
| F02 | Voice call duration stays at `0`. | Local call runtime state | `apps/rain/lib/application/runtime/voice_call_state.dart`, `_applyVoiceSessionState`, call overlay/manager timer widgets | Active call has stable `startedAt`; ended call stops ticking. | Widget tests with fake clock. |
| F03 | Muting mic shows `Peer muted`, and the label appears and disappears. | Local call runtime state | `VoiceCallState.isMuted`, `VoiceCallState.isRemoteMuted`, Firebase room mute updates, session state mapping | Local mute changes only local mute; remote mute changes only from remote peer signal. | Runtime state test plus call controls widget test. |
| F04 | PC to phone video request fails, then the Windows app crashes/closes. | Renderer/video resources | `voice_call_runtime.dart` video setup, `peer_core` media connection, Flutter WebRTC renderers | Call fails with a typed media error; app process stays alive; chat remains usable. | Fake renderer/media failure tests. |
| F05 | When the other peer closes the app, the connection does not dispose cleanly. | Local call runtime state | `rain_runtime_controller.dart` shutdown, presence/offline handling, `_disposeCurrentVoiceCallSession`, peer disconnect listeners | Remaining peer converges to `ended`, `failed`, or `disconnected`; media and data listeners are disposed. | Runtime close/dispose test with fake peer. |
| F06 | Phone starts video to computer and thinks the call is established, but video button reports another running video call. | Local call runtime state | `VoiceCallState.hasCall`, `_assertVoiceCallCanStart`, terminal room watcher, media setup failure handling | Failed setup clears active video state and returns to `idle` or `failed`. | Runtime test for remote video setup failure and stale active call cleanup. |
| F07 | On phone, after disconnecting, Connect cannot be pressed again. | Peer connection state | `apps/rain/lib/application/state/runtime_providers.dart`, `RainRuntimeController.disconnectPeer`, manual disconnect intent | Peer is `disconnected`; explicit Connect is enabled and clears manual disconnect intent. | Connection controller state test. |
| F08 | Top call manager and expanded popup duplicate controls and use inconsistent icons. | Call surface UI | `apps/rain/lib/application/state/call_surface_providers.dart`, `apps/rain/lib/presentation/screens/home_screen.dart`, call widgets | Expanded/fullscreen hides top manager; minimized/PiP shows top manager; one shared icon contract. | Call surface provider and home screen/widget tests. |
| F09 | Laptop shows flip-camera control even when there is no rear camera. | Media device capability inventory | `apps/rain/lib/application/runtime/media_device_settings.dart`, `packages/peer_core/lib/src/call/call_media_connection.dart`, call control capability mapping | Single-camera laptop hides or disables switch camera; multi-camera Android can show it. | Media device inventory tests and call control capability tests. |

## Owner Layers

### App shell/navigation

Owns whether the user sees a real app route or a loading surface. This layer should not depend only on identity existence; it must know whether startup/runtime readiness is complete enough to show the navigation shell.

### Firebase call lease/signaling

Owns pair-level call locks, call room status, retry direction, stale invite cleanup, and terminal room writes. False `peer busy` belongs here unless a test proves the peer truly has a non-terminal active call.

### Local call runtime state

Owns call phase, active call id, started timestamp, local and remote mute fields, terminal reconciliation, and the invariant that one active call exists globally.

### Peer session/media setup

Owns microphone/camera acquisition, WebRTC media setup, and local media cleanup on failure. It must not leave tracks or transceivers alive after a failed setup attempt.

### Renderer/video resources

Owns local and remote video renderer lifecycle. Renderer creation, attachment, first-frame timeout, and disposal failures must become typed call failures instead of process crashes.

### Peer connection state

Owns manual disconnect/reconnect state for chat/data peer sessions. Manual disconnect may stop automatic reconnection, but it must not block the user from explicitly pressing Connect.

### Call surface UI

Owns visual placement of the call manager, popup, fullscreen video, and PiP states. It should display runtime truth; it should not hide stale runtime bugs.

### Media device capability inventory

Owns microphone/camera lists and platform capability decisions. It should expose whether camera switching is available instead of letting UI assume every device has a rear camera.

## Terminal State Expectations

| Scenario | Expected local state | Expected remote state | Required cleanup |
| --- | --- | --- | --- |
| User hangs up | `ended` then `idle` | `ended` then `idle` | Stop media tracks, dispose renderers, release active pair lock. |
| Local media setup fails before ringing | `failed` | No incoming ring, or terminal failed room if already created | Stop opened tracks, release active pair lock. |
| Local media setup fails after invite | `failed` | `failed` | Stop opened tracks, send terminal status, release active pair lock. |
| Remote rejects | `failed` or `idle` with rejected reason | `idle` | Dispose local call session and keep chat peer alive. |
| Remote app closes | `ended`, `failed`, or `disconnected` depending on signal availability | App offline | Dispose media and reclaim stale lock by terminal room or lease timeout. |
| Firebase stale lock exists | New call may reclaim if stale or terminal | No active call | Delete or overwrite stale `activeVoicePairs` entry safely. |
| Manual peer disconnect | Peer `disconnected` | Peer observes disconnect/offline as appropriate | Stop active transfers and calls; explicit Connect remains enabled. |
| Video renderer fails | `failed` with video/media reason | `failed` if room exists | Dispose renderer references, stop tracks, keep app process alive. |

## Do Not Fix By UI Masking

- Do not hide `peer busy` in the UI unless Firebase call locks and room terminal states are proven correct.
- Do not hide the video button to work around stale `VoiceCallState.hasCall`; clear stale runtime state instead.
- Do not suppress crash text while renderer/media exceptions still escape the runtime boundary.
- Do not keep the top manager visible over an expanded popup to compensate for missing popup controls; define one surface owner per mode.
- Do not infer laptop camera switching from platform alone; use actual device inventory and labels when available.

## Acceptance Lock

The later phases are complete only when these statements are true:

- Cold startup shows one splash/loading experience and no bottom navigation until the app shell is ready.
- A stale previous failed call cannot make the next first attempt falsely busy.
- Retry preserves caller and callee direction.
- Both peers leave active call state after hangup, app close, media failure, or renderer failure.
- Video setup failures do not close the Windows app.
- Call duration increments from the moment the call becomes active.
- Local mute and remote mute have separate, stable labels.
- Manual disconnect can be followed by explicit reconnect.
- Expanded call UI and minimized call manager never duplicate controls.
- Camera switching appears only when device inventory supports it.

