# Rain

Rain is a Melos-based Flutter monorepo for a peer-to-peer chat MVP. The codebase is split into transport, protocol, domain, and app layers so desktop and Android clients can share the same core behavior.

## Workspace Layout

- `apps/rain`: Flutter app shell for desktop and Android.
- `packages/peer_core`: WebRTC wrapper, state machine, channel lifecycle, and message chunking.
- `packages/protocol_brain`: Signaling adapters, session manager, retry logic, and connection memory.
- `packages/rain_core`: Drift database, identity, friends, messages, offline queue, and delivery rules.
- `backend/firebase`: Firebase Realtime Database rules and scheduled cleanup functions.

## Prerequisites

- Flutter `3.44.0`
- Dart `3.12.0`
- Melos `7.x`
- Windows desktop toolchain for local desktop development
- Android SDK cmdline-tools and accepted licenses before Android validation
- Firebase CLI for Firebase deployment

## Bootstrap

```powershell
dart pub get
dart run melos bootstrap
dart run melos run analyze
dart run melos run test
```

## Run Locally

Firebase is the default signaling backend for this app. Copy the example defines file and run the app:

```powershell
cd apps/rain
Copy-Item tool/dart_defines.example.json tool/dart_defines.local.json
flutter run -d windows --dart-define-from-file=tool/dart_defines.local.json
```

Do not commit `tool/dart_defines.local.json`; it is gitignored because it holds secrets.

If you want the local demo mode with no backend, run:

```powershell
cd apps/rain
flutter run -d windows --dart-define=RAIN_BACKEND=noop
```

## UI And Navigation

Rain uses a simple gated entry flow:

```mermaid
flowchart TD
  A["App start"] --> B["Force update check"]
  B -->|update required| C["Update gate"]
  B -->|identity missing| D["Onboarding"]
  B -->|identity present| E["Home"]
  D --> E
  E --> F["Search users"]
  E --> G["Settings"]
  E --> H["Friend profile"]
  E --> I["Chat panel"]
```

- `RootScreen` decides whether the app shows the update gate, onboarding, or the main shell.
- `OnboardingScreen` creates or logs in the local identity, then saves it to Drift.
- `HomeScreen` is the main hub. It shows the friend list, conversation panel, and the top-bar actions.
- `SearchScreen` is used to find users and send friend requests.
- `SettingsScreen` handles display name changes, theme selection, and blocked users.
- `FriendProfileScreen` exposes the same friend actions from a detail view.

Navigation behavior inside the shell is intentionally compact:

- Selecting a friend opens the chat panel.
- On narrow widths, the chat panel replaces the friend list and uses an in-panel back button.
- Long-pressing a friend opens the profile page.
- The add-friend, search, settings, and logout actions all live in the `HomeScreen` header.

## Dart Defines

The app reads compile-time configuration from `apps/rain/tool/dart_defines.local.json`. The supported keys are:

- `RAIN_BACKEND`: `firebase` or `noop`
- `RAIN_ICE_SERVERS`: JSON array of WebRTC ICE server objects
- `RAIN_ALLOW_PUBLIC_TURN`: local/demo escape hatch for public OpenRelay TURN
- `RAIN_TURN_BROKER_URL`: optional production TURN credential broker URL
- `RAIN_UPDATE_URL`: fallback update page used by the force-update gate
- `FIREBASE_DATABASE_URL`

The bundled example defines use OpenRelay only for demo/dev runs. Production
release validation rejects OpenRelay/public TURN unless the demo build flag is
explicitly enabled. Production publishing still needs project-owned TURN
servers or a broker later; the release script intentionally fails without one.

## Backend Setup

1. Create a Firebase project and enable:
   - Anonymous Authentication
   - Realtime Database
   - Remote Config
2. Run `flutterfire configure --project=rain-8fb4b` inside `apps/rain`. This repo already includes the generated [apps/rain/lib/infrastructure/firebase/firebase_options.dart](apps/rain/lib/infrastructure/firebase/firebase_options.dart) for project `rain-8fb4b`.
3. Create or verify the Realtime Database instance and set `FIREBASE_DATABASE_URL`. The current project URL is `https://rain-8fb4b-default-rtdb.firebaseio.com`.
4. Deploy the Realtime Database rules from [backend/firebase/database.rules.json](backend/firebase/database.rules.json).
5. Deploy the cleanup functions from [backend/firebase/functions/index.js](backend/firebase/functions/index.js).
6. Set the Remote Config keys:
   - `min_required_version`
   - `update_url` (optional; overrides `RAIN_UPDATE_URL`)

Detailed Firebase instructions live in [backend/firebase/README.md](backend/firebase/README.md).

## Verification

```powershell
dart run melos run analyze
dart run melos run test
```

## Local Testing
- Quick per-package tests:
  - In each maintained package/app: `flutter pub get && flutter test`
- Full monorepo tests via Melos:
  - `dart run melos bootstrap`
  - `dart run melos run test`
- Cross-platform local testing:
  - Windows: powershell -ExecutionPolicy Bypass -File scripts/test_all.ps1
  - macOS/Linux: `dart run melos run test` (or implement test_all.sh if desired)

## MVP Notes

- Signaling data never stores message bodies in Firebase.
- Rooms are deleted immediately after connect and also cleaned up server-side as a safety net.
- Local persistence and queue operations live behind Drift transactions in `rain_core`.
- Android background execution still requires device validation after Android SDK tooling is fixed on the host machine.
