# Rain GitHub CI/CD

Rain uses these GitHub Actions workflow layers:

- `CI`: runs workflow lint, dependency lock drift checks, analyze, tests,
  Firebase emulator integration tests, and debug/demo artifact checks on pushes
  and pull requests.
- `Fast Release Apps`: manually publishes Android and/or Windows release-page
  assets after confirming the exact target SHA has already passed `CI/CD`.
  Android and Windows build in parallel, and each platform uploads as soon as it
  finishes.
- `Validated Release Apps`: manually validates the selected ref, builds Android
  and Windows release artifacts only after validation succeeds, and uploads the
  final assets to a GitHub release page.
- `Build Rain Apps`: builds downloadable Windows and Android artifacts through
  manual `workflow_dispatch`.
- `Release Rain`: builds production artifacts and publishes a GitHub Release when a `v*` tag is pushed or the workflow is manually dispatched.

## Build Artifacts

For Spark/free-tier connection request builds, deploy Realtime Database rules
and Remote Config before triggering app artifacts. Do not deploy Cloud Functions
for this gate.

```powershell
cd backend/firebase
firebase deploy --project rain-8fb4b --only database,remoteconfig --non-interactive
```

Use **Actions -> Build Rain Apps -> Run workflow**.

Inputs:

- `platform`: `all`, `android`, or `windows`.
- `build_profile`: `demo` or `production`.
- `publish_test_release`: when enabled, publishes direct APK/Windows download
  assets to a `rain-test-*` GitHub pre-release.

Demo builds use `apps/rain/tool/dart_defines.example.json`, OpenRelay demo TURN,
and the checked-in public demo Android signing key at
`apps/rain/android/demo/rain-demo-stable-release.jks.base64`. Demo artifacts are
for testing only. The demo key is intentionally not a production secret; it
exists so new demo APKs can install over previous demo APKs during device
testing. The build fails if that stable demo key is missing; it must not fall
back to a generated throwaway key because Android would reject later APK updates
with a signature mismatch.
The workflow forces `CONNECTION_REQUEST_BACKEND_MODE=rtdbOnly` for demo builds
so downloadable free-tier artifacts do not depend on callable Cloud Functions.

After every released build, update Firebase Remote Config key
`rain_release_manifest_v1` from `docs/releases/rain_release_manifest_v1.example.json`.
Old installed apps can only show optional or required update prompts after that
remote manifest advertises a newer `latestVersion`/`latestBuild` for their
channel and platform.

Free-tier release order:

1. Run Dart/Melos validation.
2. Run Firebase emulator tests.
3. Deploy RTDB rules and Remote Config.
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

## Fast Release Apps

Use **Actions -> Fast Release Apps -> Run workflow** when the target commit has
already passed `CI/CD` and you want the release-page apps faster.

This workflow does not remove validation. It waits for the newest `CI/CD` run
for the exact target SHA to complete successfully. If that SHA has no successful
`CI/CD` run, the fast release stops before building.

Inputs:

- `target_ref`: branch, tag, or SHA to release. Default: `dev`.
- `platform`: `all`, `android`, or `windows`.
- `build_profile`: `demo` or `production`.
- `prerelease`: marks the release page as a pre-release.
- `release_tag`: optional tag. If blank, the workflow creates a `rain-fast-*`
  tag for demo builds or a `rain-fast-release-*` tag for production builds.
- `clean_build`: when enabled, deletes Flutter/Gradle project build state before
  building. Keep it disabled for normal fast builds; enable it only when
  investigating stale build state or native/dependency changes.
- `ci_wait_minutes`: how long to wait for `CI/CD` success on the exact SHA.

Fast release behavior:

- Creates the GitHub release page once after the CI gate passes.
- Builds Android APKs and Windows portable zip in parallel.
- Uploads Android APKs to the release page as soon as Android finishes; it does
  not wait for Windows.
- Uploads Windows zip as soon as Windows finishes.
- Keeps direct phone-download APK names:
  - `Rain-Demo-Android-v7a.apk` or `Rain-Release-Android-v7a.apk`
  - `Rain-Demo-Android-v8-v9.apk` or `Rain-Release-Android-v8-v9.apk`
  - `Rain-Demo-Windows-x64.zip` or `Rain-Release-Windows-x64.zip`

Recommended fast testing flow:

1. Push `dev`.
2. Wait for `CI/CD` to pass on that commit.
3. Run `Fast Release Apps` with `platform=android` for phone-only testing, or
   `platform=all` when you also need Windows.
4. Leave `clean_build=false` unless the artifact looks stale or native build
   inputs changed.

## Validated Release Apps

Use **Actions -> Validated Release Apps -> Run workflow** when you want one
workflow to test the selected ref, build the release apps, and publish the
download files on a GitHub release page.

Inputs:

- `target_ref`: branch, tag, or SHA to validate. Default: `dev`.
- `platform`: `all`, `android`, or `windows`.
- `build_profile`: `demo` or `production`.
- `publish_github_release`: uploads the built assets to a release page.
- `prerelease`: marks the generated GitHub release as a pre-release.
- `release_tag`: optional tag. If blank, the workflow creates a
  `rain-validated-*` tag for demo builds or a `rain-release-*` tag for
  production builds.

Validation runs before any release artifact is built:

- workflow lint
- Dart formatting
- workspace analyze
- full workspace tests
- Firebase JSON validation
- Firebase Functions lint, audit, and tests
- Firebase emulator integration tests

The workflow publishes clean direct-download assets:

- `Rain-Demo-Android-v7a.apk` or `Rain-Release-Android-v7a.apk`
- `Rain-Demo-Android-v8-v9.apk` or `Rain-Release-Android-v8-v9.apk`
- `Rain-Demo-Windows-x64.zip` or `Rain-Release-Windows-x64.zip`

Demo builds use the Spark/free-tier `rtdbOnly` connection request backend by
default. Production builds preserve the value in
`RAIN_RELEASE_DART_DEFINES_JSON`; if it is missing, the workflow writes
`CONNECTION_REQUEST_BACKEND_MODE=rtdbOnly` before building.

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
