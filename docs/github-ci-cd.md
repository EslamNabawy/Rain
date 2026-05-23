# Rain GitHub CI/CD

Rain uses three GitHub Actions workflow layers:

- `CI`: runs workflow lint, dependency lock drift checks, analyze, tests,
  Firebase emulator integration tests, and debug/demo artifact checks on pushes
  and pull requests.
- `Build Rain Apps`: builds downloadable Windows and Android artifacts through
  manual `workflow_dispatch`.
- `Release Rain`: builds production artifacts and publishes a GitHub Release when a `v*` tag is pushed or the workflow is manually dispatched.

## Build Artifacts

Use **Actions -> Build Rain Apps -> Run workflow**.

Inputs:

- `platform`: `all`, `android`, or `windows`.
- `build_profile`: `demo` or `production`.

Demo builds use `apps/rain/tool/dart_defines.example.json`, OpenRelay demo TURN, and a generated demo Android signing key. Demo artifacts are for testing only.

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
- Android ARM v8/v9 APK: `Rain-release-android-arm64-v8a.apk`.

The demo artifact workflow publishes:

- Windows portable folder: `Rain-Demo-Windows-x64-Build`.
- Android ARM v8/v9 APK: `Rain-Demo-Android-ARM-v8-v9-Build.apk`.

Universal, ARM v7, and x86_64 APKs are not release artifacts unless a future
release plan explicitly adds them back as separate named artifacts.

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
