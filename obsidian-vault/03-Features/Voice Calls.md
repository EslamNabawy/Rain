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

## Testing Requirements

- PC to Android voice call.
- Android to PC voice call.
- Hangup from either side.
- Stale lock cleanup.
- Permission denied.
- TURN relay path.

Related: [[Video Calls]], [[Backend Architecture]], [[Risk Register]].
