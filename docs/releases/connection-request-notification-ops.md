# Connection Request Notification Ops

This runbook covers the backend-controlled guardrails for inbound/outbound
connection request notifications. The Cloud Functions own writes to request
inboxes, outboxes, pair locks, quota usage, reservations, and entitlement
credits. Clients must not write these paths directly.

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
5. Do not edit `connectionNotificationReservations` unless repairing a failed
   deployment with a known request id.
