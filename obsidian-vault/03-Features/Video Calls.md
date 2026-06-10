# Video Calls

## Purpose

Provide one-to-one video calls with audio.

## Business Value

Higher-context real-time communication.

## Technical Flow

- Uses the call runtime with `mediaMode: video`.
- Captures microphone and camera.
- Remote video is primary; local preview is secondary.
- Camera controls must reflect actual device inventory.
- Failed video setup diagnostics include Firebase room status transitions and terminal-room failure context.
- Live video renderer failure is terminal for the active video call. Local renderer failure fails call start; remote renderer attach failure writes terminal failed Firebase room state with `videoRendererFailed`.
- Renderer callbacks after the current video call is no longer live are warning diagnostics only and must not revive connected, recovering, active, or failed UI state.

## Dependencies

- Same Firebase call paths as [[Voice Calls]]
- WebRTC video tracks
- Video renderer factory
- Camera permission and selected camera settings

## Edge Cases

- No camera.
- Single camera, no flip control.
- Camera permission denied.
- First remote frame timeout.
- PC camera access failure.
- Remote closes app.
- Local or remote renderer attach failure.
- Stale renderer callback after call end/failure.

## Known Issues

- PC-to-mobile call setup has been reported failing.
- UI surface has required repeated redesign.
- 2026-06-03 call setup diagnostics now preserve room timelines for failed setup, but actual cross-device reliability still requires smoke validation.
- 2026-06-06 renderer authority is locally covered for local renderer failure and remote renderer attach failure. Device/cross-peer media proof remains required.

## Testing Requirements

- PC to Android video.
- Android to PC video.
- Camera mute.
- Preview swap.
- Fullscreen and minimized modes.

Related: [[Voice Calls]], [[Branding And UI]].
