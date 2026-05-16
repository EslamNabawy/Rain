# Rain P2P Files and Calls Plan

## Status
Deferred. Do not implement file transfer, voice calls, or video calls until the current app hardening pass is green.

## Summary
Rain can add file transfer plus voice/video calls on top of the existing WebRTC direction, but this must be treated as a real transport/product layer, not a quick UI bolt-on. The current app must first be hardened for connection reliability, chat flow, auth keyboard behavior, Find/home regressions, release packaging, and security-sensitive runtime config.

## Core Direction
- Use WebRTC data channels for chat-adjacent file transfer metadata and file chunks.
- Use WebRTC media tracks for voice/video calls.
- Keep the signaling backend responsible only for identity, friendship, presence, offers/answers, ICE, and small call/file setup messages.
- Keep large file bytes off Firebase/Supabase by default; send them peer-to-peer over RTCDataChannel.
- Keep all new file/call work behind explicit feature gates until the current app is stable.

## File Transfer Plan
- Add a typed transfer protocol: offer, accept, reject, chunk, progress, complete, cancel, fail.
- Chunk files with bounded memory use; never read a full large file into memory.
- Use RTCDataChannel buffering controls and pause/resume writes when buffered bytes exceed a threshold.
- Store transfer records locally so interrupted transfers can be explained cleanly to the user.
- Add limits for file size, extension/type display, retry count, and simultaneous transfers.
- Verify sender/receiver are friends before accepting any transfer setup message.

## Voice and Video Call Plan
- Add a call state machine: idle, ringing, connecting, active, reconnecting, ended, failed.
- Use RTCPeerConnection media tracks for microphone/camera.
- Start with one-to-one calls only.
- Keep permissions explicit and recoverable: microphone denied, camera denied, device unavailable, route failed.
- Add call controls: mute, camera on/off, speaker/device route where platform support exists, hang up.
- Keep media UI simple: full-screen active call, compact incoming call sheet, clear failed/retry state.

## Connection Requirements
- OpenRelay is demo-only. Production builds need project-owned TURN servers for reliable relay behavior.
- Release builds must not crash when TURN is absent; they must show clear direct/relay/demo language and run with direct routes only if that is the selected policy.
- Reconnect must be bounded, visible, and cancellable.
- Disconnect, unfriend, block, logout, and app close must clean up sessions and local state safely.

## Security and Abuse Controls
- File transfers must require friendship and explicit receiver acceptance.
- Never auto-open downloaded files.
- Show file name, size, and sender before acceptance.
- Sanitize file names before saving.
- Add per-peer transfer throttles and max active transfer count.
- Keep signaling messages schema-validated and reject unknown transfer/call message types.

## Test Plan
- Unit-test transfer protocol parsing, validation, chunk ordering, retry/cancel/fail states.
- Unit-test call state transitions and cleanup paths.
- Integration-test two-device file transfer over data channels with small and medium files.
- Integration-test voice-call signaling and teardown without requiring real backend production credentials.
- Stress-test disconnect/reconnect during transfer and during active call.
- Manual-test Android and Windows permissions, background/foreground transitions, and release startup.

## Current Hardening Gate
Before this plan starts, finish the current app hardening pass:
- Offline friend selection cannot create confusing failed interactive connects.
- Find results cannot show stale data after query changes.
- Mobile Find/home/chat rows cannot overflow.
- Auth/login/signup keyboard cannot hide active inputs.
- Chat composer must remain visible and fast.
- Release scripts must build Android APKs and Windows EXE without the old TURN crash.
- Push/background behavior must be direct in-app only unless a production push/background design is reintroduced deliberately.

## Sources
- [WebRTC peer connections](https://webrtc.org/getting-started/peer-connections?hl=en)
- [MDN: Using WebRTC data channels](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Using_data_channels)
- [MDN: RTCDataChannel bufferedAmountLowThreshold](https://developer.mozilla.org/en-US/docs/Web/API/RTCDataChannel/bufferedAmountLowThreshold)
- [MDN: RTCPeerConnection addTrack](https://developer.mozilla.org/en-US/docs/Web/API/RTCPeerConnection/addTrack)
- [Android foreground service types required](https://developer.android.com/about/versions/14/changes/fgs-types-required?hl=en)
