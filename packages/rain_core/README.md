# rain_core

Local persistence and domain services for Rain.

## Scope

- Owns Drift database schema and generated database code.
- Owns local identity, friends, messages, offline queue, and file-transfer records.
- Does not own Firebase signaling or Flutter UI.

## Validation

```powershell
cd packages/rain_core
flutter test
```
