# Voice Call Architecture Lock

Status: locked for implementation

Date: 2026-05-23

## Decision

Rain voice calls use one fresh, short-lived audio-only `RTCPeerConnection` per call.

The existing chat/data `RTCPeerConnection` remains data-only:

```text
chat/data peer connection: chat, control, file data channels only
voice media peer connection: microphone audio only, created per call, disposed after call
```

## Media Transport

Rain does not send microphone audio over data channels.

Microphone audio must stay on WebRTC media tracks:

```text
microphone -> MediaStreamTrack -> RTCPeerConnection
  -> Opus/RTP/RTCP -> DTLS-SRTP -> ICE transport
  -> remote jitter buffer -> speaker
```

Rain application code handles only:

```text
mic permission
audio session setup/cleanup
SDP offer/answer signaling
ICE candidate signaling
call state
diagnostics
UI
cleanup
```

## Signaling Path

Selected path: Firebase ephemeral voice call signaling.

Reason:

- Outgoing ringing must not depend on an already-open chat data channel.
- Voice setup needs independent offer, answer, ICE candidate, timeout, and hangup state.
- Dedicated call signaling keeps media setup separate from chat reconnect/file-transfer behavior.
- Call state is ephemeral control data, not chat history.

Minimum namespace:

```text
voiceCalls/{callId}
  caller
  callee
  status
  createdAt
  expiresAt
  seqByPeer/{username}
  frames/{frameId}
```

Security rules must enforce:

- only caller and callee can read/write call data
- caller and callee must be accepted friends
- frame payloads have bounded size
- calls expire through TTL cleanup
- no call history is persisted

Fallback only if Firebase schema change is explicitly rejected:

```text
existing encrypted SessionChannel.control
```

Fallback cost:

- call setup requires a connected chat peer before ringing
- less reliable startup path
- tighter coupling to chat reconnect behavior

## Release Proof

Voice call is not considered fixed until the same commit passes live device tests:

```text
Windows -> Android live call
Android -> Windows live call
repeat calls without app restart
caller hangup
callee hangup
microphone denial
chat usable during active call
file transfer blocked during active call
```

Automated tests and CI are required but not sufficient for release proof.
