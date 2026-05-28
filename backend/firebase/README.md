# Firebase Backend

This directory contains the Firebase assets needed by Rain's Realtime Database signaling flow.

## Services To Enable

- Anonymous Authentication
- Realtime Database
- Remote Config
- Cloud Functions, optional future stronger backend; not required for the
  free-tier `rtdbOnly` release path.

## Free-Tier Release Decision

Rain connection request notifications ship in `rtdbOnly` mode until the Firebase
project can use a server backend. Cloud Functions remain in the repository but
are not required for free-tier app builds. The free-tier release gate deploys
Realtime Database rules only.

Free-tier V1 does not provide server-authoritative quotas, admin credits,
scheduled cleanup, backend audit integrity, or closed-app push. These require a
server backend such as Firebase Cloud Functions on Blaze or a separate free
external backend.

Do not distribute app artifacts that depend on callable connection request
Functions unless those Functions are deployed successfully to the same Firebase
project used by the app build.

## Data Layout

- `users/<username>`: identity ownership, presence, and heartbeat timestamps
- `friendRequests/<to>/<from>`: username-based request inbox
- `rooms/<roomId>`: offer, answer, and ICE candidates only
- `activeVoicePairs/<pairId>`: ephemeral one-call lock for a caller/callee pair
- `activeVoiceUsers/<username>`: ephemeral one-call lock for a user across all peers
- `voiceCallInboxes/<username>/<callId>`: ephemeral incoming call pointer
- `voiceCalls/<callId>`: ephemeral voice call state, encrypted SDP, and encrypted ICE
- `connectionRequests/<username>/<requestId>`: inbound connection notification projection for the receiver; Spark `rtdbOnly` clients may create/transition only guarded request rows
- `connectionRequestOutboxes/<username>/<requestId>`: outbound connection notification projection for the sender; Spark `rtdbOnly` clients may create/transition only guarded request rows
- `connectionRequestQuotaSummaries/<username>`: sanitized read-only quota summary for the signed-in user
- `connectionRequestUsage/<username>/<yyyyMMddUtc>`: Spark `rtdbOnly` best-effort client counter for per-user request friction
- `connectionRequestTargetUsage/<from>/<to>/<yyyyMMddUtc>`: Spark `rtdbOnly` best-effort client counter for per-target request friction
- `connectionRequestPairLocks/<pairKey>`: pending request dedupe lock; Spark `rtdbOnly` clients may create/terminal-transition only matching locks
- `connectionNotificationEntitlements/<username>`: server-owned quota overrides and extra credits
- `connectionNotificationUsage/<username>/<yyyyMMddUtc>`: server-owned per-user usage counters
- `connectionNotificationTargetUsage/<from>/<to>/<yyyyMMddUtc>`: server-owned per-target usage counters
- `connectionNotificationMutes/<receiver>/<sender>`: receiver-owned mute state in Spark `rtdbOnly`, readable by the receiver
- `connectionNotificationAudit/<yyyyMMddUtc>/<eventId>`: server-owned audit records
- `connectionNotificationAuditSummary/<yyyyMMddUtc>`: server-owned daily audit and cost summary
- `connectionNotificationReservations/<requestId>`: server-owned quota reservation repair records

Room nodes never store chat message content.
Voice call nodes are signaling state only and are removed by TTL cleanup; they are not call history.
In Cloud Functions mode, connection notification nodes are mutated by Cloud
Functions only. In free-tier `rtdbOnly` mode, client writes are allowed only
through strict Realtime Database rules and transactions. Clients may read their
own inbox, outbox, quota summary, best-effort Spark usage counters, and mute
projection, but direct writes to server-only counters, entitlements,
reservations, config, audit summaries, and audit records remain denied.

## Deploy Realtime Database Rules

From this directory:

```powershell
firebase deploy --project <staging-or-production-project-id> --only database
```

For the current free-tier Rain project:

```powershell
cd backend/firebase
firebase deploy --project rain-8fb4b --only database --non-interactive
```

The rules file is [database.rules.json](database.rules.json).

## Deploy Functions

Install dependencies and deploy:

```powershell
cd functions
npm install
npm run lint
cd ..
firebase deploy --project <staging-or-production-project-id> --only functions
```

Cloud Functions deployment requires the Firebase project to be on the Blaze
pay-as-you-go plan because Firebase must enable Cloud Build and Artifact
Registry for function packaging.

The Cloud Functions do two things:

- mark users offline when `lastHeartbeat` is older than 7 minutes
- remove abandoned signaling rooms after 15 minutes
- remove expired voice call rooms, inbox pointers, and active pair/user locks
- expose trusted callable shells for connection request notifications:
  `createConnectionRequest`, `cancelConnectionRequest`, `acceptConnectionRequest`,
  `rejectConnectionRequest`, `markConnectionRequestSeen`,
  `muteConnectionRequestsFromPeer`, `unmuteConnectionRequestsFromPeer`, and
  `getConnectionRequestQuotaSummary`

## Free-Tier Connection Request Release Order

Use this order for Spark/free-tier builds after the `rtdbOnly` implementation
phases are complete:

1. Run Dart/Melos validation.
2. Run Firebase emulator tests.
3. Deploy RTDB rules.
4. Push `dev`.
5. Trigger the app artifact workflow.
6. Verify Android APK and Windows artifacts.

Concrete free-tier rule deploy command:

```powershell
cd backend/firebase
firebase deploy --project rain-8fb4b --only database --non-interactive
```

This path does not deploy Cloud Functions.

Cloud Functions mode is stronger but blocked until the Firebase project can use
Blaze or until the same server-owned logic is moved to an external free backend
such as Cloudflare Workers.

## Cloud Functions Connection Request Release Order

Use this stronger release order only when the Firebase project can deploy Cloud
Functions:

1. Run local validation from the repository root:
   `dart pub get`, `dart run melos run analyze`, and
   `dart run melos run test`.
2. Run backend validation from `backend/firebase/functions`: `npm test`.
3. Run emulator smoke validation from the repository root:
   `.\scripts\ci_run_firebase_emulators.ps1`.
4. Deploy Realtime Database rules to the target Firebase project.
5. Deploy Cloud Functions to the same target Firebase project.
6. Confirm the callable functions exist in the Firebase console:
   `createConnectionRequest`, `cancelConnectionRequest`,
   `acceptConnectionRequest`, `rejectConnectionRequest`,
   `markConnectionRequestSeen`, `muteConnectionRequestsFromPeer`,
   `unmuteConnectionRequestsFromPeer`, and
   `getConnectionRequestQuotaSummary`.
7. Confirm these paths are not client-writable:
   `connectionRequests`, `connectionRequestOutboxes`,
   `connectionRequestPairLocks`, `connectionNotificationUsage`,
   `connectionNotificationTargetUsage`,
   `connectionNotificationReservations`,
   `connectionNotificationEntitlements`, `connectionNotificationAudit`, and
   `connectionNotificationAuditSummary`.
8. Only after the backend is aligned, build and publish Android/Windows app
   artifacts.

V1 connection request notifications are app-open or app-minimized only. V1 does
not register Firebase Cloud Messaging tokens and does not support closed-app
push notifications.

## Remote Config

Create this key in Remote Config:

- `rain_release_manifest_v1`

Use [../../docs/releases/rain_release_manifest_v1.example.json](../../docs/releases/rain_release_manifest_v1.example.json) as the template. Update the matching `stable` or `demo` channel for each platform after publishing a release. The app uses this manifest to show optional updates and block versions older than the configured minimum.

Keep these legacy fallback keys until all installed builds support the manifest:

- `min_required_version`
- `update_url`

`update_url` is optional. When omitted, the app falls back to `RAIN_UPDATE_URL` from dart-defines.

## Suggested Validation

1. Register two desktop users and confirm `users/<username>/uid` is owned by the anonymous auth user.
2. Send a friend request and confirm it appears under `friendRequests/<recipient>/<sender>`.
3. Connect two peers and confirm `rooms/<roomId>` is deleted immediately after the session is established.
4. Stop sending heartbeats and confirm the cleanup job marks the user offline within the next scheduler run.
