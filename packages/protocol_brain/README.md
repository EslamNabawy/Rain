# protocol_brain

Signaling, session, retry, and connection-memory logic for Rain.

## Scope

- Owns signaling adapter contracts.
- Owns session establishment and retry policy.
- Uses `peer_core` for raw peer transport.
- Does not own UI or local message persistence.

## Validation

```powershell
cd packages/protocol_brain
flutter test
```
