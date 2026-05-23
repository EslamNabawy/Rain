# Voice Call Architecture Lock

Status: locked for implementation

Date: 2026-05-23

Implementation spec: `docs/superpowers/specs/2026-05-23-webrtc-voice-call-rebuild-spec.md`

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

Locked namespace:

```text
activeVoicePairs/{pairId}
  callId
  caller
  callee
  createdAt
  updatedAt
  expiresAt

voiceCallInboxes/{username}/{callId}
  from
  to
  pairId
  status
  createdAt
  updatedAt
  expiresAt

voiceCalls/{callId}
  v
  pairId
  caller
  callee
  status
  createdAt
  updatedAt
  expiresAt
  acceptedAt?
  connectedAt?
  endedAt?
  endedBy?
  reasonCode?
  reason?
  muted/{username}
  offer
  answer
  ice/caller/{candidateId}
  ice/callee/{candidateId}
```

Security rules must enforce:

- only caller and callee can read/write call data
- caller and callee must be accepted friends
- frame payloads have bounded size
- SDP and ICE payloads are encrypted before storage
- role-specific writes for offer, answer, and ICE
- active pair lock prevents simultaneous-call glare
- calls expire through TTL cleanup
- no call history is persisted

Explicitly rejected path:

```text
existing encrypted SessionChannel.control
```

Reason rejected:

- call setup requires a connected chat peer before ringing
- less reliable startup path
- tighter coupling to chat reconnect behavior
- already produced stale SDP/candidate and disposed transceiver failure modes

## Offer Ownership And ICE

The caller owns the first media offer.

ICE candidates are accepted by call id, participant role, and terminal-state checks. They are not rejected by one global monotonic frame sequence because candidate delivery can race with SDP delivery.

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
