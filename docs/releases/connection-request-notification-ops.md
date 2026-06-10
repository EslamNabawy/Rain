# Connection Request Notification Ops

This runbook covers inbound/outbound connection request notifications. Rain is
moving to a Firebase Spark/free-tier `rtdbOnly` release path first. Cloud
Functions remain in the repository as the stronger future backend, but free-tier
app builds must not require deploying Functions.

## Free-Tier Release Decision

Rain connection request notifications ship in `rtdbOnly` mode until the Firebase
project can use a server backend. Cloud Functions remain in the repository but
are not required for free-tier app builds. The release gate deploys Realtime
Database rules only.

Free-tier V1 does not provide server-authoritative quotas, admin credits,
scheduled cleanup, backend audit integrity, or closed-app push. These require a
server backend such as Firebase Cloud Functions on Blaze or a separate free
external backend.

## V1 Release Notes

Connection request notifications let accepted friends ask each other to open the
normal Rain peer lane without bypassing manual disconnect intent.

V1 behavior:

- Inbound and outbound request state is synchronized through Firebase-owned
  request inbox and outbox projections.
- Receivers can accept, reject, ignore, mute, and unmute request senders.
- Senders see pending, accepted, rejected, canceled, expired, failed, duplicate,
  quota, cooldown, and unavailable states with explicit user-facing messages.
- A request never auto-connects the receiver; accepting remains a user action.
- Active calls and active file transfers block new connection requests with a
  visible explanation.
- App-open and app-minimized notification surfaces are supported through the
  app runtime and local notification abstraction where available.

Free-tier quota and credit behavior:

- Daily limit, sender-to-peer limit, burst cooldown, and duplicate suppression
  are best-effort abuse friction enforced by client logic, RTDB transactions,
  and security rules.
- Duplicate pending requests, receiver mute, block, offline/stale presence, and
  receiver inbox-full denials must not create receiver prompts.
- Successfully created requests spend quota even when later canceled, rejected,
  ignored, or expired.
- Admin extra credits and temporary unlimited entitlements are disabled in
  free-tier `rtdbOnly` mode because there is no trusted server authority.

V1 limitations:

- No closed-app push notification.
- No Firebase Cloud Messaging token registration or storage.
- No automatic connection acceptance.
- No connection request history.
- No group connection requests.

Closed-app push is reserved for the separate V2 specification at
`docs/superpowers/specs/connection-request-push-notifications-v2.md`.

## Release Gate

Before distributing free-tier app builds that include connection request
notifications:

1. Run Dart/Melos validation.
2. Run Firebase emulator tests.
3. Deploy RTDB rules.
4. Push `dev`.
5. Trigger the app artifact workflow.
6. Verify Android APK and Windows artifacts.

Use this RTDB-only deploy command for the current free-tier project:

```powershell
cd backend/firebase
firebase deploy --project rain-8fb4b --only database --non-interactive
```

Confirm the app build uses `CONNECTION_REQUEST_BACKEND_MODE=rtdbOnly` before
publishing artifacts.

Do not deploy Cloud Functions for the free-tier release gate.

Cloud Functions mode is stronger but blocked until the Firebase project can use
Blaze or until the same server-owned logic is moved to an external free backend
such as Cloudflare Workers.

## Latest Free-Tier Build Gate

Phase 11 was completed on 2026-05-28 for the free-tier `rtdbOnly` path.

- RTDB rules were deployed to `rain-8fb4b` with `firebase deploy --project
  rain-8fb4b --only database --non-interactive`.
- No Cloud Functions deploy was required or performed.
- `dev` was pushed at `5d98ade32eb74174530bcc50aa7b52f8680d606d`.
- The `Build Rain Apps` workflow completed successfully:
  `https://github.com/EslamNabawy/Rain/actions/runs/26594423504`.
- The direct test download pre-release is:
  `https://github.com/EslamNabawy/Rain/releases/tag/rain-test-66-1`.
- Release assets:
  - `Rain-Demo-Android-v7a.apk`
  - `Rain-Demo-Android-v8-v9.apk`
  - `Rain-Demo-Windows-x64.zip`
- Workflow logs confirmed both Android and Windows demo jobs generated
  `rain-defines.json` with `CONNECTION_REQUEST_BACKEND_MODE=rtdbOnly`.

## Firebase Paths

- `connectionNotificationConfig/global`
  - `enabled`: set `false` to stop new connection request notifications.
  - `requestTtlMs`: pending request TTL, default `45000`.
  - `maxPendingInboundPerUser`: receiver inbox cap, default `25`.
  - `dailyFreeLimit`: sender free daily allowance, default `20`.
  - `perTargetDailyLimit`: sender-to-peer daily cap, default `3`.
  - `burstLimit`: max sends within `burstWindowMs`, default `3`.
  - `burstWindowMs`: rolling burst window, default `60000`.
  - `cooldownMs`: cooldown after burst denial, default `15000`.
- `connectionNotificationEntitlements/{username}`
  - `disabled`: blocks this sender while the entitlement is active.
  - `extraCredits`: additional sends after daily free allowance.
  - `unlimitedUntil`: UTC epoch ms. Bypasses daily free/credit count until this time.
  - `expiresAt`: UTC epoch ms. Once elapsed, the entitlement is ignored.
  - `reason`: short admin reason for the grant or restriction.
  - `updatedBy`: admin/operator identifier.
- `connectionNotificationUsage/{username}/{yyyyMMddUtc}`
  - Server-maintained daily sender usage. Do not edit for normal grants.
- `connectionNotificationTargetUsage/{from}/{to}/{yyyyMMddUtc}`
  - Server-maintained sender-to-peer usage.
- `connectionNotificationReservations/{requestId}`
  - Server-maintained quota reservation/finalization record.
- `connectionNotificationAudit/{yyyyMMddUtc}/{eventId}`
  - Server-maintained event stream for allowed, denied, deduped, terminal, cleanup, and rollback decisions.
- `connectionNotificationAuditSummary/{yyyyMMddUtc}`
  - Server-maintained daily counters for created, allowed, denied, deduped, terminal, and rollback events.

## Diagnostics Contract

Client diagnostics for every connection request decision must include:

- `requestId`
- `peerId`
- `direction`
- `status`
- `reasonCode`
- `userMessageKey`
- `renderedMessage`
- `quotaSummary`
- `retryAfterMs`
- `notificationFallbackState`

The UI uses `renderedMessage`. The exact internal denial remains in
`reasonCode`. Do not expose private receiver state in copy. For example,
`mutedByReceiver` should remain a diagnostic reason while the UI says the peer
is unavailable for connection requests.

Backend audit rows must include:

- `eventName`
- `createdAt`
- `action`
- `requestId`
- `sender`
- `peer`
- `pairKey`
- `allowed`
- `status`
- `reasonCode`
- `userMessageKey`
- `renderedMessage`
- `retryAfterMs`
- `costEffect`
- `rollbackPairLock`
- `rollbackQuota`

Use audit rows for incident reconstruction. Use the summary row for dashboards,
daily limits, and quick cost checks.

## Grant Extra Credits

Set `connectionNotificationEntitlements/{username}`:

```json
{
  "extraCredits": 25,
  "reason": "manual operator credit",
  "updatedBy": "admin@example.com",
  "expiresAt": 1770000000000
}
```

Credits are consumed only by backend transaction. They cannot decrement below
zero. Free daily allowance is consumed before extra credits.

## Grant Temporary Unlimited Use

Set `unlimitedUntil` for the user:

```json
{
  "unlimitedUntil": 1770000000000,
  "reason": "internal QA",
  "updatedBy": "admin@example.com"
}
```

Unlimited use bypasses the daily free/extra-credit count only. Receiver
protection, pair dedupe, inbox cap, per-target cap, burst limit, and cooldown
still apply.

## Disable A Sender

Set an active entitlement:

```json
{
  "disabled": true,
  "reason": "abuse review",
  "updatedBy": "admin@example.com",
  "expiresAt": 1770000000000
}
```

If `expiresAt` is in the past, the entitlement is ignored and does not block the
sender. Use the global kill switch for an incident affecting all users.

## Enable Or Disable The Global Feature

Set `connectionNotificationConfig/global/enabled`:

```json
{
  "enabled": false
}
```

This stops new connection request notifications before pair locks or quota
reservations are created. Existing pending requests still expire or can be
handled by their normal terminal actions.

To re-enable:

```json
{
  "enabled": true
}
```

Do not delete the config node during an incident. Explicit `false` is easier to
audit and easier to roll back.

## Inspect Audit And Cost

For one UTC day, inspect:

- `connectionNotificationAuditSummary/{yyyyMMddUtc}`
- `connectionNotificationAudit/{yyyyMMddUtc}`

Important counters:

- `createdCount`: successful request creations that spent quota.
- `deniedCount`: denied attempts, including rate limits and receiver protection.
- `dedupedCount`: duplicate pending requests that did not spend quota.
- `terminalCount`: accepted, rejected, canceled, or expired transitions.
- `rollbackCount`: failed creation paths where locks or quota were rolled back.

The function logs a warning when the daily denied/created ratio is elevated.
Use that warning as an abuse or rollout signal, not as a reason to block users
silently. Every denied client action must still show a user-facing message.

## Cleanup Stale Locks And Reservations

In free-tier `rtdbOnly` mode, app clients perform opportunistic cleanup on app
startup, chat open, request creation, terminal actions, and inbox/outbox
snapshot reads. There is no scheduled cleanup function in the free release
gate.

Only the future Cloud Functions mode owns scheduled stale repair. In that mode,
run or wait for `cleanupConnectionRequests` when you see:

- old `connectionRequestPairLocks` with expired `expiresAt`
- `connectionNotificationReservations` stuck in `reserved`
- corrupt request rows in `connectionRequests` or `connectionRequestOutboxes`
- old `connectionNotificationAudit` and `connectionNotificationAuditSummary`
  day buckets beyond retention

Never manually delete a live pair lock unless you confirmed the request row is
missing, terminal, corrupt, or expired and the `requestId` still matches.

## Operational Rules

- Duplicate pending requests do not consume quota.
- Receiver mute/block/offline/inbox-full denials do not consume quota.
- A successfully created request consumes quota even if it is later canceled,
  rejected, ignored, or expired.
- If inbox/outbox writes fail after quota reservation, the function rolls back
  the pair lock, daily usage, per-target usage, extra credit, and reservation.
- Do not manually delete usage counters unless repairing a confirmed backend
  incident. Prefer adding `extraCredits` or `unlimitedUntil`.

## Firebase Console Checklist

1. Confirm the username is normalized lowercase.
2. Check `connectionNotificationEntitlements/{username}` for active disable or
   expired grants.
3. For extra sends, update `extraCredits` and include `reason`, `updatedBy`, and
   `expiresAt`.
4. For internal unlimited testing, set `unlimitedUntil` and keep the expiry
   short.
5. Check `connectionNotificationAuditSummary/{yyyyMMddUtc}` before raising
   global limits.
6. Inspect recent `connectionNotificationAudit/{yyyyMMddUtc}` rows for the
   exact `reasonCode` and `costEffect`.
7. Do not edit `connectionNotificationReservations` unless repairing a failed
   deployment with a known request id.
