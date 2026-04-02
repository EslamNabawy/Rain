# Two-Device Handshake End-to-End Test & Firebase Emulator CI Pipeline

## Summary

Implemented a dedicated two-device handshake end-to-end test with Firebase emulator support for CI/local testing. This validates the complete friend request → acceptance → WebRTC handshake flow using two emulator-backed user identities.

## Changes

### Tests
- **`apps/rain/test/integration_two_users_end2end_test.dart`** — Simulates two emulator-backed users (Alice and Bob) using Firebase emulator paths. Alice sends a friend request to Bob; Bob accepts; both sides end up with `FRIEND` state.
- **`apps/rain/test/friend_flow_test.dart`** — Extended with inbound/outbound scenarios and self-request edge-case coverage.

### Emulator Harness (CI/Local)
- **`scripts/ci_run_firebase_emulators.sh`** — Starts Firebase Auth and RTDB emulators, exports emulator host variables, runs tests (melos bootstrap; melos test).
- Firebase adapter updated to support emulator-based registration and login using deterministic emails (`username@rain.local`).

### CI Wiring
- **`.github/workflows/ci.yml`** — Now invokes the emulator harness to run emulator-based tests. Boots Melos dependencies, starts Firebase emulators, runs tests.

### Security
- **`backend/firebase/database.rules.json`** — Tightened with owner-based access enforcement for user data.

## How to Run Locally

```bash
# 1. Start Firebase emulators
firebase emulators:start --project RainMVP --only auth,database

# 2. Point app to emulators
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000

# 3. Run tests
melos bootstrap
melos test

# Or run the two-device test directly:
cd apps/rain
flutter test test/integration_two_users_end2end_test.dart
```

## Notes

- **Emulator reliability**: CI handles readiness with retry loop. Adjust backoff if flakiness occurs.
- **Production parity**: Emulator path uses email/password sign-in to mirror realistic flow. Anonymous sign-in remains available for MVP if needed.
- **Future extension**: Can add live message exchange test to validate WebRTC data channel carries messages end-to-end.

## Files Touched

- `apps/rain/test/integration_two_users_end2end_test.dart`
- `apps/rain/test/friend_flow_test.dart`
- `scripts/ci_run_firebase_emulators.sh`
- `.github/workflows/ci.yml`
- `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- `backend/firebase/database.rules.json`
- `apps/rain/pubspec.yaml`
- `packages/protocol_brain/pubspec.yaml`
