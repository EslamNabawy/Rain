# Voice Calls

## Purpose

Provide one-to-one audio calls between accepted friends.

## Business Value

Real-time private communication.

## Technical Flow

- Call requires accepted friend, fresh presence, no active call, no active file transfer.
- Firebase creates call room, inbox entry, pair lock, and user locks.
- SDP and ICE are encrypted before storage.
- WebRTC media connection carries microphone audio.
- Terminal Firebase room state should end both peers.
- Failed setup diagnostics include Firebase room status transitions so reports can distinguish ringing, accepted, connected, failed, and ended phases.
- Late terminal-sensitive media signaling sends (`accept`, `offer`, `answer`, `mute`) preflight the Firebase call room before writing. If the room is missing or terminal, Rain records `voice_late_media_frame_ignored_after_terminal`, reconciles the active session, and does not let the debug signaling adapter record a crash-level write failure.

## Dependencies

- Firebase RTDB `voiceCalls`, `voiceCallInboxes`, `activeVoicePairs`, `activeVoiceUsers`
- `protocol_brain` voice session
- `peer_core` voice media connection
- Microphone permission and selected microphone settings

## Edge Cases

- Peer offline.
- Peer busy.
- Permission denied.
- ICE candidate write failure.
- Stale call lock.
- App closed mid-call.
- Network switch mid-call.

## Known Issues

- PC-to-mobile call reliability has been repeatedly reported broken.
- Call failures can be shown as media failures even when signaling failed.
- Voice hangup reliability has been reported weaker than video.
- Call setup diagnostics were strengthened on 2026-06-03, but full device-level reliability remains a launch blocker until smoke evidence proves both directions.
- 2026-06-04 mitigation: a PC-side crash after the remote peer ended the call was traced to `_createAndSendOffer` writing an offer after Firebase room status was already terminal. Runtime now skips late terminal-sensitive media signaling writes before they reach `writeVoiceOffer`/`writeVoiceAnswer`.

## Testing Requirements

- PC to Android voice call.
- Android to PC voice call.
- Hangup from either side.
- Stale lock cleanup.
- Permission denied.
- TURN relay path.

Related: [[Video Calls]], [[Backend Architecture]], [[Risk Register]].
