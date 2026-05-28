# Rain GitHub CI/CD

Rain uses three GitHub Actions workflow layers:

- `CI`: runs workflow lint, dependency lock drift checks, analyze, tests,
  Firebase emulator integration tests, and debug/demo artifact checks on pushes
  and pull requests.
- `Build Rain Apps`: builds downloadable Windows and Android artifacts through
  manual `workflow_dispatch`.
- `Release Rain`: builds production artifacts and publishes a GitHub Release when a `v*` tag is pushed or the workflow is manually dispatched.

## Build Artifacts

For Spark/free-tier connection request builds, deploy Realtime Database rules
before triggering app artifacts. Do not deploy Cloud Functions for this gate.

```powershell
cd backend/firebase
firebase deploy --project rain-8fb4b --only database --non-interactive
```

Use **Actions -> Build Rain Apps -> Run workflow**.

Inputs:

- `platform`: `all`, `android`, or `windows`.
- `build_profile`: `demo` or `production`.
- `publish_test_release`: when enabled, publishes direct APK/Windows download
  assets to a `rain-test-*` GitHub pre-release.

Demo builds use `apps/rain/tool/dart_defines.example.json`, OpenRelay demo TURN, and a generated demo Android signing key. Demo artifacts are for testing only.
The workflow forces `CONNECTION_REQUEST_BACKEND_MODE=rtdbOnly` for demo builds
so downloadable free-tier artifacts do not depend on callable Cloud Functions.

Free-tier release order:

1. Run Dart/Melos validation.
2. Run Firebase emulator tests.
3. Deploy RTDB rules.
4. Push `dev`.
5. Trigger the app artifact workflow.
6. Verify Android APK and Windows artifacts.

Cloud Functions mode is stronger but blocked until the Firebase project can use
Blaze or until the same server-owned logic is moved to an external free backend
such as Cloudflare Workers.

Latest verified free-tier demo build:

- Date: 2026-05-28.
- Branch/SHA: `dev` at `5d98ade32eb74174530bcc50aa7b52f8680d606d`.
- Workflow run:
  `https://github.com/EslamNabawy/Rain/actions/runs/26594423504`.
- Direct download pre-release:
  `https://github.com/EslamNabawy/Rain/releases/tag/rain-test-66-1`.
- Published assets:
  - `Rain-Demo-Android-v7a.apk`
  - `Rain-Demo-Android-v8-v9.apk`
  - `Rain-Demo-Windows-x64.zip`
- Build inputs: `platform=all`, `build_profile=demo`,
  `publish_test_release=true`.
- Backend mode proof: successful Android and Windows demo jobs forced
  `CONNECTION_REQUEST_BACKEND_MODE=rtdbOnly` in `rain-defines.json` before
  building artifacts.

For fast phone installs, keep `publish_test_release` enabled. The workflow
creates a pre-release with individual APK assets, so Android devices can open
the release page and download:

- `Rain-Demo-Android-v7a.apk` or `Rain-Release-Android-v7a.apk`.
- `Rain-Demo-Android-v8-v9.apk` or `Rain-Release-Android-v8-v9.apk`.

The workflow summary also prints direct links to each generated asset. Old
`rain-test-*` pre-releases are pruned automatically after the latest ten builds.

Production builds require the secrets below.

## Production Secrets

Add these under **Repository Settings -> Secrets and variables -> Actions**:

- `RAIN_RELEASE_DART_DEFINES_JSON`: sanitized release dart defines JSON. Must include `RAIN_TURN_BROKER_URL` or project-owned TURN in `RAIN_ICE_SERVERS`.
- `RAIN_RELEASE_KEYSTORE_BASE64`: base64-encoded Android release keystore.
- `RAIN_RELEASE_STORE_PASSWORD`: Android keystore password.
- `RAIN_RELEASE_KEY_ALIAS`: Android key alias.
- `RAIN_RELEASE_KEY_PASSWORD`: Android key password.

`RAIN_RELEASE_DART_DEFINES_JSON` must not point at OpenRelay unless you are using the demo build path. Production release builds intentionally fail without `RAIN_TURN_BROKER_URL` or project-owned TURN.

## Release

Push a tag like `v1.0.0`, or run **Actions -> Release Rain -> Run workflow** with an existing tag.

The release workflow publishes:

- Windows portable zip.
- Android ARM v7 APK: `Rain-release-android-armeabi-v7a.apk`.
- Android ARM v8/v9 APK: `Rain-release-android-arm64-v8a.apk`.

The demo artifact workflow publishes:

- Windows portable folder: `Rain-Demo-Windows-x64-Build`.
- Android ARM v7 APK: `Rain-Demo-Android-ARM-v7a-Build.apk`.
- Android ARM v8/v9 APK: `Rain-Demo-Android-ARM-v8-v9-Build.apk`.

Universal and x86_64 APKs are not release artifacts unless a future release
plan explicitly adds them back as separate named artifacts.

## Pre-Release Live Smoke Checks

Before publishing a release with voice calling enabled, run a live 1:1 voice
call smoke test on Android and Windows using the release candidate artifacts.
Use `docs/qa/voice-call-manual-device-gate.md` as the required evidence record.

- Sign in two accepted friend accounts with both apps open and reachable.
- Start a call from Android to Windows, accept it, verify audio connects, mute
  toggles locally, hang up, and confirm the chat session remains connected.
- Repeat from Windows to Android.
- Repeat one call over a direct route and one call over a TURN relay route.
- Force a bad media negotiation or disconnect during call setup when practical,
  then confirm the call fails cleanly, local audio stops, a failed hangup is
  sent, and the existing chat session stays alive.
- Check diagnostics for the full native WebRTC error text when a media setup
  failure occurs.

## Local Android Parity

Local Android build verification needs the same major tooling CI installs:

- JDK 21 available on `PATH` or through `JAVA_HOME`.
- Android SDK command-line tools installed.
- Android SDK licenses accepted with `flutter doctor --android-licenses`.

Run `flutter doctor -v` before treating local Android build failures as app
failures. CI installs JDK 21 in the workflow, but it still depends on a valid
Flutter/Android SDK setup in the runner image.
