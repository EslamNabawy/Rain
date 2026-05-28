# Connection Request Push Notifications V2 Spec

Status: future specification only

Date: 2026-05-28

Owner areas: product, Firebase backend, Flutter platform, security, QA, release

## Summary

Connection request notifications V1 are app-open or app-minimized only. V2 adds
optional closed-app push for Android after the existing server-side connection
request guardrails are proven in production.

This document is intentionally a specification, not an implementation plan. V1
must not add Firebase Cloud Messaging token storage, push token writes, push
fanout, or closed-app notification promises. Closed-app push starts only after
this spec is accepted and converted into a separate implementation plan.

## References

- Firebase Cloud Messaging overview: https://firebase.google.com/docs/cloud-messaging
- FCM Flutter receiving guide: https://firebase.google.com/docs/cloud-messaging/flutter/receive
- FCM Android receiving guide: https://firebase.google.com/docs/cloud-messaging/android/receive
- FCM send requests: https://firebase.google.com/docs/cloud-messaging/send-message
- Android notification permission: https://developer.android.com/develop/ui/views/notifications/notification-permission

## V1 Boundary

V1 does not implement:

- FCM token storage.
- FCM token upload.
- Push fanout from Cloud Functions.
- Closed-app inbound connection request notifications.
- Background auto-connect.
- Background peer session opening.
- Background voice/video call invite replacement.
- Push notification entitlements separate from connection request entitlements.

V1 may keep local notifications for active/minimized app states behind the
existing notification abstraction. Those local notifications must not imply that
Rain can wake from a fully closed state.

## Product Goal

If Rain is closed or backgrounded and Android can receive FCM, a user may receive
a notification that an accepted friend wants them to open the peer lane.

The notification is only a prompt. Tapping it opens Rain and takes the user to
the request context. The receiver still chooses whether to connect. Push must
never auto-connect, spend sender quota twice, bypass receiver mute/block rules,
or reveal sensitive receiver state to the sender.

## Platform Decision

### Android

Android is the only V2 closed-app push target.

Required platform work:

- Add and configure `firebase_messaging`.
- Request notification permission at a product-approved moment.
- Register a default Android notification channel for connection requests.
- Handle notification tap routing into the app.
- Handle token refresh events and logout/account-switch cleanup.
- Treat force-stopped apps and OS delivery limits as expected failure modes.

### Windows

Windows remains local-only in V2 unless a separate Windows notification provider
is approved.

Do not fake Windows push with polling. If a future provider is selected, it must
get a separate threat model, token lifecycle, privacy review, and cost model.

## System Contract

Closed-app push must reuse the existing connection request backend decision:

```text
client asks backend to create connection request
  -> backend validates sender, receiver, relationship, presence, mute/block,
     dedupe, inbox cap, quotas, credits, burst limits, and global kill switch
  -> backend creates the request if allowed
  -> backend sends push only for the same allowed request
  -> receiver opens Rain and handles the normal request lifecycle
```

Push is a delivery side effect, not a second request system.

The backend must not send push for:

- blocked sender or receiver relationship
- receiver-muted connection requests
- unaccepted friend relationship
- offline-denied or stale-presence-denied request
- duplicate pending sender/receiver pair
- quota-denied sender
- per-target-limit denial
- burst-limit or cooldown denial
- disabled sender entitlement
- disabled global feature
- failed or rolled-back request creation

## Proposed Firebase Paths

These paths are V2 candidates. They must not exist in V1.

```text
connectionPushTokens/{username}/{tokenId}
  tokenHash: string
  encryptedToken: string
  platform: "android"
  appVersion: string
  buildNumber: number
  channel: "stable" | "demo"
  deviceLabel: string?
  createdAt: millis
  updatedAt: millis
  lastSeenAt: millis
  expiresAt: millis
  disabled: bool

connectionPushPreferences/{username}
  enabled: bool
  quietHoursEnabled: bool
  quietHoursStartMinute: number?
  quietHoursEndMinute: number?
  mutedSenders/{sender}: bool
  updatedAt: millis

connectionPushDelivery/{yyyyMMddUtc}/{requestId}_{tokenId}
  requestId: string
  sender: string
  receiver: string
  tokenId: string
  status: "queued" | "sent" | "skipped" | "failed"
  reasonCode: string
  providerMessageId: string?
  createdAt: millis
  updatedAt: millis
  expiresAt: millis

connectionPushAudit/{yyyyMMddUtc}/{eventId}
  eventName: string
  requestId: string
  sender: string
  receiver: string
  tokenId: string?
  status: string
  reasonCode: string
  createdAt: millis
```

Token values must never be stored as plaintext. If FCM token encryption is not
available in the chosen backend environment, V2 must store tokens in a backend
system that supports secret handling instead of RTDB.

## Token Lifecycle

### Registration

Token registration happens only after:

- the user is authenticated locally
- the app has selected the active Rain username
- notification permission is granted where required
- the V2 Remote Config feature flag is enabled for the channel/platform
- App Check enforcement has been evaluated for the backend endpoint

The client sends the raw FCM token to a Cloud Function. The function validates
the authenticated user, stores an encrypted token, stores a stable token hash,
and updates `lastSeenAt`.

Clients must not write push token paths directly.

### Refresh

When FCM rotates the token:

- register the new token through the same Cloud Function
- mark the old token disabled when known
- keep only a bounded number of active tokens per user/device class
- record diagnostics for refresh success/failure

### Logout And Account Switch

On logout or account switch:

- unregister the current token for the old username through a Cloud Function
- remove local token association from app state
- do not reuse one token across usernames without a server-side rebind
- disable old token rows if the server can confirm ownership

If unregister fails because the app is offline, the app queues a best-effort
cleanup attempt for next launch. The server cleanup job still expires stale
tokens even if the client never returns.

### Inactivity And Uninstall

Uninstall cannot be handled perfectly by the client. V2 must rely on:

- token expiry based on `lastSeenAt`
- FCM send failures that mark tokens disabled
- scheduled cleanup for expired or disabled token rows
- bounded active-token count per user

## Push Payload

Use a privacy-minimal payload.

Allowed data:

- `type`: `connection_request`
- `requestId`
- `sender`
- `receiver`
- `createdAt`
- `expiresAt`
- `schema`

Avoid including:

- message text
- precise receiver-side denial reason
- sender diagnostics
- quota details
- relationship internals
- any token or device identifiers

Notification text must be neutral and short:

- Title: `Rain connection request`
- Body: `@sender wants to connect.`

The app resolves richer context after launch by reading the normal connection
request paths.

## Delivery Semantics

Push delivery is best effort. The database request remains the source of truth.

Required behavior:

- One push attempt per created request per eligible token unless explicitly
  retried by backend policy.
- Deduplicate by `requestId` and `tokenId`.
- Set FCM TTL no longer than the connection request TTL.
- Use a collapse key or equivalent grouping per sender/receiver pair where
  supported.
- If push fails, keep the request valid in Firebase.
- If request expires before delivery, receiver UI must show expired/not
  available after app open.
- If receiver accepts on another device, tapping an old notification must open
  an already-handled state, not a second request.

## Guardrails

Push must inherit all V1 connection request guardrails:

- global feature kill switch
- sender disable entitlement
- daily free limit
- extra credits
- temporary unlimited entitlement
- per-target daily limit
- burst limit
- cooldown
- receiver mute
- inbox cap
- pair dedupe
- relationship validation
- stale cleanup
- every denied action returns a user-facing message

Additional V2 push-specific guardrails:

- max active push tokens per user
- max push sends per request
- max failed sends per token before disabling
- max daily push sends per receiver
- global push kill switch separate from request creation
- per-channel rollout percentage
- Android-only platform gate
- quiet hours preference
- notification permission denied fallback
- App Check enforcement or explicit rollout exception

## User-Facing Error And Status Messages

No action may be blocked silently.

Required messages:

- Permission denied: `Notifications are off. Rain can show requests while the app is open.`
- Push unavailable: `Closed-app notifications are not available on this device.`
- Push disabled by settings: `Connection request notifications are muted.`
- Quiet hours: `Connection request notifications are paused until quiet hours end.`
- Request expired: `This connection request expired. Ask your friend to send it again.`
- Sender limited: `You have reached the connection request limit. Try again later.`
- Receiver unavailable: `@peer is unavailable for connection requests right now.`
- Feature disabled: `Connection request notifications are temporarily unavailable.`

Sender-facing copy must not reveal whether the receiver blocked or muted them.

## Runtime And UI Behavior

On notification tap:

1. Open Rain.
2. Restore identity/session state.
3. Fetch the request by `requestId`.
4. If valid and pending, show the normal inbound connection request UI.
5. If terminal, show the terminal state.
6. If missing/expired, show an expired request message.

Do not connect automatically on notification tap.

If the user has multiple accounts or no active account:

- route to login/account selection first
- preserve the notification intent only while it is safe and fresh
- discard expired intents with a visible message

## Security Review Checklist

Before implementation:

- Confirm clients cannot write token, delivery, or audit paths directly.
- Confirm only Cloud Functions can send push.
- Confirm token registration is authenticated and bound to the active username.
- Confirm token storage uses encryption or a backend secret store.
- Confirm token hash cannot be used to send notifications.
- Confirm token unregister cannot delete another user's token.
- Confirm App Check enforcement strategy is documented.
- Confirm push payload contains no sensitive relationship or quota details.
- Confirm blocked/muted/offline/quota-denied paths send no push.
- Confirm direct database tampering cannot trigger push fanout.
- Confirm stale request notification taps do not reopen terminal requests.
- Confirm push kill switch can stop fanout without disabling normal in-app
  requests.
- Confirm diagnostics keep raw internal reason codes but UI copy remains safe.

## Diagnostics And Audit

Client diagnostics:

- `push_permission_requested`
- `push_permission_denied`
- `push_token_register_started`
- `push_token_register_succeeded`
- `push_token_register_failed`
- `push_token_unregister_started`
- `push_token_unregister_failed`
- `push_notification_tap_received`
- `push_notification_request_missing`
- `push_notification_request_expired`

Backend audit:

- `connection_push_token_registered`
- `connection_push_token_disabled`
- `connection_push_send_skipped`
- `connection_push_send_queued`
- `connection_push_send_succeeded`
- `connection_push_send_failed`
- `connection_push_token_pruned`

Audit rows must include request id, sender, receiver, token id/hash reference,
reason code, status, platform, channel, and created timestamp. They must not
include the raw FCM token.

## Rollout Plan

1. Ship V1 without token storage.
2. Add V2 token schema/rules/functions behind a disabled Remote Config flag.
3. Enable internal demo channel for one Android device set.
4. Verify token register, refresh, logout cleanup, and stale cleanup.
5. Enable push send for internal accepted-friend requests only.
6. Verify all denied paths produce no push.
7. Enable limited stable rollout percentage.
8. Monitor audit summary, function errors, send failures, permission-denied
   rate, and complaint signals.
9. Expand only when failure rate and cost stay within budget.

## Test Plan

Unit and contract tests:

- token registration rejects unauthenticated users
- token registration rejects username mismatch
- token unregister cannot delete another user's token
- direct RTDB writes to token/delivery/audit paths are denied
- blocked/muted/quota-denied/duplicate requests skip push
- allowed request creates at most one push delivery row per token
- push failure does not roll back an already-created request
- token cleanup expires stale tokens
- notification tap into expired request shows expired message

Integration tests:

- app launch registers token only after permission and identity are ready
- logout unregisters token
- account switch rebinds token safely
- token refresh updates server state
- Android notification tap opens the request context
- denied notification permission falls back to app-open notifications only

Manual gate:

- Android cold-start notification tap
- Android background notification tap
- Android force-stop limitation documented
- permission denied path
- logout/account switch cleanup
- multiple-device same account delivery and dedupe
- receiver accept on one device while another notification is tapped

## Open Decisions

- Token storage backend: encrypted RTDB payload versus a dedicated secret-capable
  backend store.
- Whether App Check is mandatory on day one or staged with monitoring.
- Exact Android notification channel name, sound policy, and quiet-hours UI.
- Whether stable rollout is percentage-based, allowlist-based, or both.
- Whether Windows will stay local-only permanently or get a separate provider.

## Acceptance Criteria

- V1 remains free of FCM token storage and closed-app push behavior.
- V2 push can only be sent by backend code after the normal request guardrail
  decision allows creation.
- Closed-app push never creates, accepts, or connects a peer lane by itself.
- Every blocked, skipped, or failed push path has diagnostics and a safe user
  message where the user can act on it.
- Raw push tokens are never exposed to clients, rules, diagnostics, or audit
  exports.
- Android push can be disabled globally without disabling app-open request
  notifications.
