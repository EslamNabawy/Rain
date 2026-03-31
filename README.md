# Rain

Rain is a Melos-based Flutter monorepo for a peer-to-peer chat MVP. The codebase is split into transport, protocol, domain, and app layers so desktop and Android clients can share the same core behavior.

## Workspace Layout

- `apps/rain`: Flutter app shell for desktop and Android.
- `packages/peer_core`: WebRTC wrapper, state machine, channel lifecycle, and message chunking.
- `packages/protocol_brain`: Signaling adapters, session manager, retry logic, and connection memory.
- `packages/rain_core`: Drift database, identity, friends, messages, offline queue, and delivery rules.
- `backend/firebase`: Firebase Realtime Database rules and scheduled cleanup functions.
- `backend/supabase`: Supabase schema, RLS policies, and Edge Function cleanup job.

## Prerequisites

- Flutter `3.38.5`
- Dart `3.10.4`
- Melos `7.x`
- Windows desktop toolchain for local desktop development
- Android SDK cmdline-tools and accepted licenses before Android validation
- Firebase CLI for Firebase deployment
- Supabase CLI for Supabase deployment

## Bootstrap

```powershell
dart pub global activate melos
melos bootstrap
melos run analyze
melos run test
```

## Run Locally

The app can run in a local demo mode with no backend:

```powershell
cd apps/rain
flutter run -d windows --dart-define=RAIN_BACKEND=noop
```

For Firebase or Supabase, copy the example defines file and fill in real values:

```powershell
Copy-Item tool/dart_defines.example.json tool/dart_defines.local.json
flutter run -d windows --dart-define-from-file=tool/dart_defines.local.json
```

Do not commit `tool/dart_defines.local.json`; it is gitignored because it holds secrets.

## Dart Defines

The app reads compile-time configuration from `apps/rain/tool/dart_defines.local.json`. The supported keys are:

- `RAIN_BACKEND`: `noop`, `firebase`, or `supabase`
- `RAIN_ICE_SERVERS`: JSON array of WebRTC ICE server objects
- `RAIN_UPDATE_URL`: fallback update page used by the force-update gate
- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`
- `FIREBASE_DATABASE_URL`
- `FIREBASE_STORAGE_BUCKET`
- `FIREBASE_AUTH_DOMAIN`
- `FIREBASE_MEASUREMENT_ID`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

## Backend Setup

### Firebase

1. Create a Firebase project and enable:
   - Anonymous Authentication
   - Realtime Database
   - Remote Config
2. Deploy the Realtime Database rules from [backend/firebase/database.rules.json](backend/firebase/database.rules.json).
3. Deploy the cleanup functions from [backend/firebase/functions/index.js](backend/firebase/functions/index.js).
4. Set the Remote Config keys:
   - `min_required_version`
   - `update_url` (optional; overrides `RAIN_UPDATE_URL`)

Detailed Firebase instructions live in [backend/firebase/README.md](backend/firebase/README.md).

### Supabase

1. Create a Supabase project and enable anonymous sign-in.
2. Apply [backend/supabase/schema.sql](backend/supabase/schema.sql).
3. Deploy [backend/supabase/functions/presence-cleanup/index.ts](backend/supabase/functions/presence-cleanup/index.ts) with `--no-verify-jwt`.
4. Schedule the function every 3 minutes so stale users are marked offline after 7 minutes without heartbeat.

Detailed Supabase instructions live in [backend/supabase/README.md](backend/supabase/README.md).

## Verification

```powershell
melos run analyze
melos run test
cd apps/rain
flutter build windows --debug --no-pub
```

## MVP Notes

- Signaling data never stores message bodies in Firebase or Supabase.
- Rooms are deleted immediately after connect and also cleaned up server-side as a safety net.
- Local persistence and queue operations live behind Drift transactions in `rain_core`.
- Android background execution still requires device validation after Android SDK tooling is fixed on the host machine.
