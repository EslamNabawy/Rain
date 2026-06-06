# CallMediaCoordinator

## Purpose

Own microphone, camera, WebRTC media session lifecycle, ICE restart, and media failure classification.

## Responsibilities

- Preflight permissions.
- Capture microphone/camera.
- Start media connection.
- Apply offers/answers/candidates.
- Track ICE candidate write/read health.
- Classify permission, device, ICE, TURN, and renderer failures separately.
- Tag video renderer failures as local, remote, or unknown so runtime policy can distinguish start-time renderer failure from active remote-renderer failure and stale callbacks.

## Current Implementation

As of 2026-06-06, `call_media_session_coordinator.dart` wraps app-side audio/video media connections and owns renderer attach error conversion. Local video renderer attach errors are rethrown as `VideoCallRendererException(target: local)` so call start fails deterministically. Remote video renderer attach errors are captured through a `Future.sync` boundary and reported as `VideoCallRendererException(target: remote)` so `VoiceCallRuntime` can fail the active video call and write terminal failed room state.

## Tests

- Mic denied.
- Camera denied.
- PC no camera.
- ICE failure.
- TURN unavailable.
- Remote first frame timeout.
- Local video renderer creation/attach failure fails the current video call with `videoRendererFailed`.
- Remote video renderer attach failure fails the current video call, writes terminal failed Firebase room state, and records split-state diagnostics when data-session truth is still connected.

Related: [[Voice Calls]], [[Video Calls]], [[CallStartCoordinator]].
