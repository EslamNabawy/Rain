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

Relay-test builds use `RAIN_RELEASE_DART_DEFINES_JSON`, require `RAIN_TURN_BROKER_URL`, reject OpenRelay, and use a generated Android signing key. Use this profile for mobile-data/VPN validation after the Coturn/DuckDNS broker is live.

For now, the main `CI/CD` workflow and push-triggered `Build Rain Apps` runs default to OpenRelay demo artifacts so APK/EXE builds are available without the Oracle broker. Demo artifacts are convenient for testing, but they are not production reliability proof.

Use `docs/architecture/rain-turn-fallback-recovery.md` to record the required same Wi-Fi, different Wi-Fi, mobile data, mobile data + VPN, and stale-room recovery evidence for relay-test artifacts.

Production builds require the secrets below.

## Production Secrets

Add these under **Repository Settings -> Secrets and variables -> Actions**:

- `RAIN_RELEASE_DART_DEFINES_JSON`: sanitized release dart defines JSON. For relay-test, start from `apps/rain/tool/dart_defines.relay-test.example.json`, replace `RAIN_SIGNALING_ENCRYPTION_KEY`, and keep `RAIN_TURN_BROKER_URL=https://rain-p2p-turn.duckdns.org/rainTurnCredentials`. For production, use the same broker or project-owned TURN entries.
- `RAIN_RELEASE_KEYSTORE_BASE64`: base64-encoded Android release keystore.
- `RAIN_RELEASE_STORE_PASSWORD`: Android keystore password.
- `RAIN_RELEASE_KEY_ALIAS`: Android key alias.
- `RAIN_RELEASE_KEY_PASSWORD`: Android key password.

`RAIN_RELEASE_DART_DEFINES_JSON` must not point at OpenRelay unless you are using the demo build path. Relay-test builds intentionally fail without `RAIN_TURN_BROKER_URL`; production release builds intentionally fail without project-owned TURN or a TURN broker.

## TURN Broker

The preferred zero-cost broker is the self-hosted Oracle Always Free Coturn broker in `backend/turn`. It exposes `POST https://rain-p2p-turn.duckdns.org/rainTurnCredentials`, verifies Firebase Auth ID tokens, and returns short-lived Coturn REST/HMAC credentials.

The older Firebase broker function is still kept in `backend/firebase/functions` as a managed-provider option, but it requires Firebase Blaze plus Twilio or Cloudflare secrets. Do not use the Firebase broker URL for mobile-data/VPN validation unless it has been deployed and the unauthenticated check returns `401`.

Base ICE should stay STUN-first with Google and Cloudflare:

- `stun:stun.l.google.com:19302`
- `stun:stun1.l.google.com:19302`
- `stun:stun.cloudflare.com:3478`

Managed or self-hosted TURN is fetched through the broker. For the zero-cost path, deploy `backend/turn` to the Oracle VM and set `RAIN_TURN_BROKER_URL` to the DuckDNS HTTPS endpoint.

For the Firebase managed-provider broker, set `RAIN_TURN_PROVIDER` to `twilio,cloudflare`, `twilio`, or `cloudflare`. The default is `twilio,cloudflare`, which tries Twilio first and Cloudflare second.

Twilio Firebase v2 secrets:

- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`

Cloudflare Firebase v2 secrets:

- `CLOUDFLARE_TURN_KEY_ID`
- `CLOUDFLARE_TURN_KEY_API_TOKEN`

The unauthenticated broker check should return `401`; authenticated app calls should return ICE servers with at least one `turn:` or `turns:` URL. The app never stores provider secrets in APK/EXE artifacts.

## Scalability and Cost

The zero-cost Oracle/Coturn path is a reliability fix for early Rain testing, not unlimited production capacity. The default Coturn template uses relay ports `49160-49300`, which is 140 UDP ports or about 70 concurrent relayed sessions. It also caps each relayed session at `512000` bps to reduce the chance of burning through the free egress tier.

Set an OCI budget alert at roughly 7 TB/month, watch Coturn session counts, and move to a paid multi-region TURN provider or larger Coturn fleet when relayed sessions regularly approach 70 concurrent sessions, users report relay saturation, or monthly egress approaches the free-tier ceiling.

## Release

Push a tag like `v1.0.0`, or run **Actions -> Release Rain -> Run workflow** with an existing tag.

The release workflow publishes:

- Windows portable zip.
- Android universal APK.
- Android `arm64-v8a` APK.
- Android `armeabi-v7a` APK.
- Android `x86_64` APK.
