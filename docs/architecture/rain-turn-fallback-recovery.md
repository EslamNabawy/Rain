# Rain TURN Fallback Recovery Test Matrix

This document is the manual acceptance runbook for Rain's direct-first,
relay-backed WebRTC connection path. Use it only with broker-backed
`Rain-Relay-Test` artifacts. Demo/OpenRelay artifacts are useful for build
checks, but they are not proof that mobile data, VPN, or different Wi-Fi
connections are fixed.

## Test Rule

Rain is accepted only when the app is truthful:

- Same Wi-Fi may connect as `Direct`.
- Different Wi-Fi, mobile data, and VPN may connect as `Direct` or `Relay`.
- If direct fails, the status dialog must show a relay stage such as
  `primaryRelay`.
- If relay fails, the app must show a precise relay/data-channel failure.
- The app must not sit indefinitely on generic `Connecting`.
- Messages must show `Delivered` only after peer ACK.
- File transfer must complete with matching byte/hash validation, or fail with
  a clear transfer error.

## Build Under Test

Fill this block before every manual test run.

```text
Git commit: 61c8298 or later
Branch: dev
Android artifact: Rain-Relay-Test-android-arm64-v8a.apk / Rain-Relay-Test-android-armeabi-v7a.apk
Windows artifact: Rain-Relay-Test-Windows-x64-Build
Build workflow: Build Rain Apps
Build profile: relay-test
Manual CI input: build_relay_test=true
RAIN_TURN_BROKER_URL: https://rain-p2p-turn.duckdns.org/rainTurnCredentials
RAIN_ALLOW_PUBLIC_TURN: false
RAIN_ICE_STRATEGY: staged
Base STUN list: stun:stun.l.google.com:19302, stun:stun1.l.google.com:19302, stun:stun.cloudflare.com:3478
TURN provider: pending capture from status dialog
TURN URL count: pending capture from status dialog
Has UDP TURN: pending capture from broker response/status dialog
Has TCP TURN: pending capture from broker response/status dialog
Has TURNS TCP: pending capture from broker response/status dialog
Signaling encryption key: same non-demo key on both devices; do not record value here
```

## Preflight

Before installing artifacts:

1. Trigger `Build Rain Apps` manually.
2. Select `build_profile=relay-test` or set `build_relay_test=true`.
3. Confirm the workflow validates `RAIN_TURN_BROKER_URL`.
4. Confirm unauthenticated `POST` to the broker returns `401`, not `404`.
5. Install the exact produced APK and Windows artifact on both test devices.
6. Create fresh accounts using the same current build.
7. Add/accept friendship before testing connection.

Required broker behavior:

```text
Unauthenticated POST: 401
Authenticated app request: returns at least one turn: or turns: URL
OpenRelay in relay-test artifact: no
RAIN_ALLOW_PUBLIC_TURN in relay-test artifact: false
```

## Evidence To Capture

For each scenario, capture a screenshot or screen recording of the status
dialog after pressing Connect. Record:

```text
Scenario:
Device A:
Device B:
Network A:
Network B:
VPN A:
VPN B:
Connection result:
Final visible status:
ICE stage:
Provider tier:
Provider:
TURN URLs:
Route:
Local candidate type:
Remote candidate type:
Protocol:
Relay protocol:
RTT:
Bitrate:
Attempt number:
Last error:
Message ACK both directions:
File transfer A -> B:
File transfer B -> A:
Notes:
```

## Scenario 1: Same Wi-Fi Baseline

Purpose: prove the direct path still works after relay hardening.

Steps:

1. Put Windows and Android on the same Wi-Fi.
2. Open Rain on both devices.
3. Confirm both users show online.
4. Press Connect from one side.
5. If needed, press Connect on the other side.
6. Send one short message A -> B.
7. Send one short message B -> A.
8. Send one small file A -> B.
9. Send one small file B -> A.
10. Open the status dialog and capture diagnostics.

Expected:

- Status moves through the direct attempt.
- Final route is `Direct` when possible.
- If direct is not selected, `Relay` is acceptable only if diagnostics prove
  the selected ICE candidates are relay candidates.
- Messages ACK both directions.
- File transfer succeeds both directions.

Result:

```text
Status: Pending manual run
Final route:
Message ACK:
File transfer:
Evidence path/link:
```

## Scenario 2: Different Wi-Fi

Purpose: prove Rain does not rely on LAN-only host candidates.

Steps:

1. Put Windows on Wi-Fi A.
2. Put Android on Wi-Fi B.
3. Confirm neither device is using the same router/LAN.
4. Open Rain on both devices.
5. Press Connect.
6. Wait until final state is `Direct`, `Relay`, or `Failed`.
7. Capture status dialog diagnostics.
8. If connected, send messages and files both directions.

Expected:

- Final route is `Direct` or `Relay`.
- If direct fails, `ICE stage` shows `Primary relay` or later.
- If relay fails, status has exact provider or data-channel error.
- The app does not remain indefinitely on generic `Connecting`.

Result:

```text
Status: Pending manual run
Final route:
ICE stage:
Provider error:
Message ACK:
File transfer:
Evidence path/link:
```

## Scenario 3: Mobile Data

Purpose: prove carrier NAT does not trap Rain in direct-only behavior.

Steps:

1. Put Windows on Wi-Fi.
2. Put Android on mobile data only.
3. Disable Android Wi-Fi.
4. Confirm Android internet works.
5. Open Rain on both devices.
6. Press Connect.
7. Wait until final state is `Direct`, `Relay`, or `Failed`.
8. Capture status dialog diagnostics.
9. If connected, send messages and files both directions.

Expected:

- Direct may fail.
- Relay stage must appear if direct cannot open data channels.
- Successful connection should show `Relay` when direct is blocked by carrier
  NAT.
- If it fails, error must be one of:
  - `Relay credentials unavailable.`
  - `Relay authorization failed. Sign in again.`
  - `Relay provider timed out.`
  - `Data channel did not open.`
  - `All connection routes failed.`

Result:

```text
Status: Pending manual run
Final route:
ICE stage:
Provider:
TURN URLs:
Last error:
Message ACK:
File transfer:
Evidence path/link:
```

## Scenario 4: Mobile Data + VPN

Purpose: prove VPN routing does not hide a broken relay fallback.

Steps:

1. Put Windows on Wi-Fi.
2. Put Android on mobile data.
3. Enable VPN on Android.
4. Confirm Android internet works through the VPN.
5. Open Rain on both devices.
6. Press Connect.
7. Wait until final state is `Relay` or precise `Failed`.
8. Capture status dialog diagnostics.
9. If connected, send messages and files both directions.

Expected:

- TURNS TCP/443 is available from the provider and can be selected if UDP/TCP
  relay paths are blocked.
- Final status is `Relay` or a precise relay failure.
- The app must not sit indefinitely on generic `Connecting`.
- If provider has no TURNS TCP/443, record that as a provider limitation, not
  an app success.

Result:

```text
Status: Pending manual run
Final route:
ICE stage:
Provider:
TURN URLs:
Has TURNS TCP:
Last error:
Message ACK:
File transfer:
Evidence path/link:
```

## Scenario 5: Stale Room And Reopen

Purpose: prove stale signaling rooms and stale ICE candidates do not trap
reconnect after one device closes mid-attempt.

Steps:

1. Open both apps.
2. Press Connect on device A.
3. Close device B during the direct attempt.
4. Reopen device B.
5. Press Connect on both devices.
6. Open the status dialog.
7. Capture attempt number, ICE stage, and final state.
8. If connected, send messages both directions.

Expected:

- New `connectAttemptId` is used for the fresh attempt.
- Stale direct ICE is ignored.
- Stale room is deleted before retry.
- Connection reaches `Direct`, `Relay`, or precise `Failed`.
- `Delivered` never appears for messages that did not receive peer ACK.

Result:

```text
Status: Pending manual run
Attempt before close:
Attempt after reopen:
Final route:
ICE stage:
Last error:
Message ACK:
Evidence path/link:
```

## Failure Classification

Use this table when a scenario fails.

| Visible Error | Meaning | Next Action |
| --- | --- | --- |
| `Relay credentials unavailable.` | Relay-test build has no usable broker TURN credentials. | Check `RAIN_TURN_BROKER_URL`, app auth, and broker response. |
| `Relay authorization failed. Sign in again.` | Broker rejected Firebase Auth token. | Re-login, confirm broker verifies the current Firebase project. |
| `Relay provider timed out.` | TURN URL was present but connection did not open in time. | Check provider ports, firewall, UDP/TCP/TLS coverage, and VPN behavior. |
| `Data channel did not open.` | ICE may have connected, but required data channels did not open. | Capture route diagnostics and inspect protocol brain logs. |
| `All connection routes failed.` | Direct and relay stages were exhausted. | Compare status dialog evidence against broker/TURN server logs. |
| File says missing/mismatch | File integrity validation rejected the transfer. | Retry after stable connection; inspect transfer byte/hash evidence. |

## Acceptance Gate

Do not call mobile/VPN reliability fixed until this table is filled with real
device evidence.

| Scenario | Required Result | Current Result |
| --- | --- | --- |
| Same Wi-Fi | `Direct` preferred, messages/files pass | Pending |
| Different Wi-Fi | `Direct` or truthful `Relay`, no stuck connecting | Pending |
| Mobile data | Relay stage visible, final `Relay` or precise failure | Pending |
| Mobile data + VPN | TURNS TCP/443 attempted, final `Relay` or precise failure | Pending |
| Stale room/reopen | New attempt, stale room cleared, no fake delivered | Pending |

## Notes

- Firebase remains signaling/presence only. Chat and file bytes must not pass
  through Firebase.
- TURN relay traffic is still WebRTC encrypted, but relay metadata and traffic
  volume are visible to the TURN provider.
- Relay-test artifacts must use the same signaling encryption key on both
  devices.
- If a demo artifact is installed by mistake, discard that test result.
