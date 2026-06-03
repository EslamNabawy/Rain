# Signaling Architecture

Firebase signaling coordinates connection setup. It does not carry media packets.

## Data-Peer Signaling

- Uses Firebase rooms for WebRTC data peer negotiation.
- WebRTC data channels carry chat, control, and file transfer traffic.

## Call Signaling

- Uses `voiceCalls`, `voiceCallInboxes`, `activeVoicePairs`, and `activeVoiceUsers`.
- Encrypted SDP and ICE envelopes are stored in RTDB.
- Media flows over WebRTC.

## Required Improvements

- Separate signaling failure from media failure.
- Track candidate write/read health.
- Add watcher error handling.

Related: [[Lease Management]], [[Call State Machine]], [[Firebase Architecture]].
