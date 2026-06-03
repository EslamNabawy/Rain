# System Architecture

Rain is a Flutter workspace split across app shell, local core, signaling/session policy, WebRTC primitives, and Firebase backend.

## Layers

```text
presentation widgets
  -> Riverpod providers
  -> runtime controllers
  -> rain_core / protocol_brain / peer_core
  -> Drift / Firebase / Flutter WebRTC / platform APIs
```

## Workspace Map

- `apps/rain` - Flutter Android/Windows app, UI, runtime orchestration, infrastructure services.
- `packages/rain_core` - local data, identity, friends, messages, file metadata, frame models.
- `packages/protocol_brain` - signaling adapters, session state, retry/reconnect policy, Firebase contracts.
- `packages/peer_core` - WebRTC data/media primitives and platform bridge.
- `backend/firebase` - Realtime Database rules, Remote Config template, optional functions.

## High-Risk Architectural Facts

- `VoiceCallRuntime` is too large and owns too many responsibilities.
- Firebase call locks are client-coordinated and sequential.
- Local database is missing important secondary indexes.
- CI workflows duplicate release/test logic.

Related: [[Frontend Architecture]], [[Backend Architecture]], [[Database Architecture]], [[Infrastructure Architecture]], [[Technical Debt]].
