# Rain GitHub CI/CD

Rain uses three GitHub Actions workflow layers:

- `CI`: runs analyze and tests on pushes and pull requests.
- `Build Rain Apps`: builds downloadable Windows and Android artifacts on pushes or manual dispatch.
- `Release Rain`: builds production artifacts and publishes a GitHub Release when a `v*` tag is pushed or the workflow is manually dispatched.

## Build Artifacts

Use **Actions -> Build Rain Apps -> Run workflow**.

Inputs:

- `platform`: `all`, `android`, or `windows`.
- `build_profile`: `demo`, `relay-test`, or `production`.

Demo builds use `apps/rain/tool/dart_defines.example.json`, OpenRelay demo TURN, and a generated demo Android signing key. Demo artifacts are for testing only.

Relay-test builds use `RAIN_RELEASE_DART_DEFINES_JSON`, require `RAIN_TURN_BROKER_URL`, reject OpenRelay, and use a generated Android signing key. Use this profile for mobile-data/VPN validation before production signing is ready.

The main `CI/CD` workflow builds relay-test artifacts, not demo artifacts. Push-triggered `Build Rain Apps` runs also default to relay-test. Both paths preflight `RAIN_TURN_BROKER_URL` before packaging so a missing Firebase/managed TURN broker fails CI instead of producing APKs that only work on LAN.

Production builds require the secrets below.

## Production Secrets

Add these under **Repository Settings -> Secrets and variables -> Actions**:

- `RAIN_RELEASE_DART_DEFINES_JSON`: sanitized release dart defines JSON. For relay-test, start from `apps/rain/tool/dart_defines.relay-test.example.json`, replace `RAIN_SIGNALING_ENCRYPTION_KEY`, and keep `RAIN_TURN_BROKER_URL=https://us-central1-rain-8fb4b.cloudfunctions.net/rainTurnCredentials`. For production, use the same broker or project-owned TURN entries.
- `RAIN_RELEASE_KEYSTORE_BASE64`: base64-encoded Android release keystore.
- `RAIN_RELEASE_STORE_PASSWORD`: Android keystore password.
- `RAIN_RELEASE_KEY_ALIAS`: Android key alias.
- `RAIN_RELEASE_KEY_PASSWORD`: Android key password.

`RAIN_RELEASE_DART_DEFINES_JSON` must not point at OpenRelay unless you are using the demo build path. Relay-test builds intentionally fail without `RAIN_TURN_BROKER_URL`; production release builds intentionally fail without project-owned TURN or a TURN broker.

## TURN Broker

The Firebase broker function is `rainTurnCredentials` in project `rain-8fb4b`, region `us-central1`. It requires Cloud Functions and Cloud Run APIs to be enabled.

Base ICE should stay STUN-first with Google and Cloudflare:

- `stun:stun.l.google.com:19302`
- `stun:stun1.l.google.com:19302`
- `stun:stun.cloudflare.com:3478`

Managed TURN is fetched through the broker. Set `RAIN_TURN_PROVIDER` to `twilio,cloudflare`, `twilio`, or `cloudflare`. The default is `twilio,cloudflare`, which tries Twilio first and Cloudflare second.

Twilio Firebase v2 secrets:

- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`

Cloudflare Firebase v2 secrets:

- `CLOUDFLARE_TURN_KEY_ID`
- `CLOUDFLARE_TURN_KEY_API_TOKEN`

The unauthenticated broker check should return `401`; authenticated app calls should return Twilio or Cloudflare ICE servers with at least one `turn:` or `turns:` URL. The app never stores provider secrets in APK/EXE artifacts.

## Release

Push a tag like `v1.0.0`, or run **Actions -> Release Rain -> Run workflow** with an existing tag.

The release workflow publishes:

- Windows portable zip.
- Android universal APK.
- Android `arm64-v8a` APK.
- Android `armeabi-v7a` APK.
- Android `x86_64` APK.
