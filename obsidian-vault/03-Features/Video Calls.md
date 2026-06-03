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

## Known Issues

- PC-to-mobile call setup has been reported failing.
- UI surface has required repeated redesign.
- 2026-06-03 call setup diagnostics now preserve room timelines for failed setup, but actual cross-device reliability still requires smoke validation.

## Testing Requirements

- PC to Android video.
- Android to PC video.
- Camera mute.
- Preview swap.
- Fullscreen and minimized modes.

Related: [[Voice Calls]], [[Branding And UI]].
