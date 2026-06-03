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

## Tests

- Mic denied.
- Camera denied.
- PC no camera.
- ICE failure.
- TURN unavailable.
- Remote first frame timeout.

Related: [[Voice Calls]], [[Video Calls]], [[CallStartCoordinator]].
