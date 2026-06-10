# Signaling Architecture

Firebase signaling coordinates connection setup. It does not carry media packets.

## Data-Peer Signaling

- Uses Firebase rooms for WebRTC data peer negotiation.
- Room id is canonical by sorted peer usernames and RTDB role ownership remains canonical: `callerICE` is written only by `userA`, and `calleeICE` is written only by `userB`.
- Candidate paths are leaf writes: `rooms/{roomId}/callerICE/{candidateId}` and `rooms/{roomId}/calleeICE/{candidateId}`.
- Broadening ICE writes so either participant can write either bucket is a security regression unless the role model changes everywhere. The current fix for `signaling.writeICE` permission-denied diagnostics is lifecycle hardening: dispose peer bindings before room deletion and ignore queued local ICE callbacks when session, peer generation, room id, or binding state no longer match.
- Data-peer room cleanup is a session cleanup action, not a connected-state action. The active room stays alive while the data session is connected because valid local trickle ICE can arrive after the data channel opens; deleting the room at `connected` can make current-room ICE fail the RTDB room-existence rule.
- WebRTC data channels carry chat, control, and file transfer traffic.

## Call Signaling

- Uses `voiceCalls`, `voiceCallInboxes`, `activeVoicePairs`, and `activeVoiceUsers`.
- Encrypted SDP and ICE envelopes are stored in RTDB.
- Media flows over WebRTC.

## Required Improvements

- Separate signaling failure from media failure.
- Track candidate write/read health.
- Keep sanitized path templates in write-failure diagnostics so rule failures identify the template without exposing room ids or raw ICE.
- Add watcher error handling.

Related: [[Lease Management]], [[Call State Machine]], [[Firebase Architecture]].
