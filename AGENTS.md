# Rain Agent Instructions

Rain is a Flutter monorepo for a peer-to-peer chat app. Keep changes focused on the maintained app and packages:

- `apps/rain` - Flutter desktop and Android app.
- `packages/peer_core` - WebRTC transport and data-channel framing.
- `packages/protocol_brain` - signaling, sessions, retry, and connection memory.
- `packages/rain_core` - Drift storage, identity, friends, messages, and delivery rules.
- `backend/firebase` - Firebase Realtime Database rules and cleanup functions.

## Priorities

1. Correctness
2. Reliability
3. Security
4. Maintainability
5. Operational simplicity
6. Performance
7. Developer experience

## Defaults

- Be direct and technical.
- Verify with tools when practical.
- Do not hardcode secrets or local credentials.
- Keep runtime backends limited to Firebase and noop unless the app explicitly changes direction.
- Prefer the existing Flutter, Riverpod, Drift, Firebase, and Melos patterns.
- Do not reintroduce obsolete scaffolding such as old phase runners, external skill bundles, or unused sample apps.

## Validation

Use these checks for normal code changes:

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

Do not run platform builds unless the user asks for build verification.
