# Rain GitHub CI/CD

Rain uses three GitHub Actions workflow layers:

- `CI`: runs workflow lint, dependency lock drift checks, analyze, tests,
  Firebase emulator integration tests, and debug/demo artifact checks on pushes
  and pull requests.
- `Build Rain Apps`: builds downloadable Windows and Android artifacts on pushes or manual dispatch.
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
- Android universal APK.
- Android `arm64-v8a` APK.
- Android `armeabi-v7a` APK.
- Android `x86_64` APK.

## Local Android Parity

Local Android build verification needs the same major tooling CI installs:

- JDK 21 available on `PATH` or through `JAVA_HOME`.
- Android SDK command-line tools installed.
- Android SDK licenses accepted with `flutter doctor --android-licenses`.

Run `flutter doctor -v` before treating local Android build failures as app
failures. CI installs JDK 21 in the workflow, but it still depends on a valid
Flutter/Android SDK setup in the runner image.
