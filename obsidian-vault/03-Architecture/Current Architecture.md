# Current Architecture

Rain currently uses a layered Flutter workspace:

- `apps/rain` for app/UI/runtime/infrastructure.
- `packages/rain_core` for local persistence and domain data.
- `packages/protocol_brain` for signaling/session policy.
- `packages/peer_core` for WebRTC primitives.
- `backend/firebase` for RTDB rules and optional functions.

## Current Failure-Prone Areas

- `VoiceCallRuntime` centralizes too many responsibilities.
- `RainRuntimeController` still owns broad connection, lifecycle, file, call, and presence coordination.
- Firebase call lease flow depends on sequential client writes.
- UI state can present signaling failures as media failures.

Related: [[Target Architecture]], [[Refactoring Strategy]], [[VoiceCallRuntime Refactor]].
