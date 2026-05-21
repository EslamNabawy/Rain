# peer_core

WebRTC transport primitives for Rain.

## Scope

- Owns peer connection lifecycle.
- Owns data-channel framing and chunk handling.
- Does not know about Rain UI, Drift storage, or Firebase user records.

## Validation

```powershell
cd packages/peer_core
flutter test
```
