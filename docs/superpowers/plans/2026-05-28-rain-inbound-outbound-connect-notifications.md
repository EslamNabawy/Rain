# Rain Inbound And Outbound Connect Notification Plan

> **For agentic workers:** implement this plan phase by phase on `dev`. Commit after each completed phase. Do not change the working chat, call, file transfer, login, or release workflows unless a phase explicitly requires it.

## Goal

Add a clear notification flow for manual peer connection attempts. When Alice wants to connect to Bob, Alice should see an outbound pending state and Bob should receive an inbound notification that Alice wants to connect. Bob can connect, ignore, or reject. The feature must make manual connection intent understandable without reintroducing unwanted auto-reconnect behavior.

## Product Rules

- Accepted friends only.
- No notification is created for blocked, unaccepted, offline, or stale-presence peers.
- No notification is created for peers who muted connection requests from the sender.
- Pressing `Disconnect` still means: do not reconnect until the user explicitly presses `Connect`.
- Inbound connect notifications are advisory; they do not auto-open a WebRTC session without user action.
- Outbound notifications are local progress state plus optional cancellation.
- The app may show OS/local notifications only while Rain is running or background-capable on the platform.
- Usage limits, credits, cooldowns, and override values are stored in Firebase and enforced by backend code, not local storage.
- Users can read their own remaining quota, but only backend/admin credentials can change quota grants or extra credits.
- Server-side dedupe guarantees one pending request per sender/receiver pair.
- Receiver protection wins over sender credits: mute, block, offline, stale presence, and inbox caps reject before notification fan-out.
- True closed-app push notification is a separate phase because it requires device tokens, Firebase Cloud Messaging, permissions, privacy policy updates, and backend token lifecycle.

## Existing Constraints

- Rain currently uses Firebase Realtime Database for identity, presence, friendships, signaling, and ephemeral call state.
- `friendRequests/<to>/<from>` already exists for friendship requests and should not be reused for connection attempts.
- Voice/video call inboxes already prove the app can watch ephemeral Firebase inbox paths.
- Background service support is currently forced off in settings, and previous architecture docs explicitly mark push-notification ringing as unsupported.
- Current Firebase rules intentionally do not expose an unused push notification token surface.

## Target Behavior

### Outbound

When the local user presses `Connect` for an online accepted friend:

1. Runtime preflights accepted friendship, block state, network, local manual disconnect reset, and fresh peer presence.
2. Runtime writes a short-lived connect notification request to Firebase.
3. Sender UI shows:
   - `Waiting for @peer to connect...`
   - `Cancel`
   - status updates: `Sent`, `Seen`, `Accepted`, `Rejected`, `Expired`, `Failed`.
4. If the peer accepts, normal `connectPeer(peerId)` proceeds.
5. If the peer rejects, cancels, expires, or goes offline, no session is started and the sender gets a clear message.

### Inbound

When Rain receives an inbound connection notification:

1. Runtime validates sender is an accepted, non-blocked friend and presence is fresh.
2. UI shows a compact inbound prompt:
   - `@alice wants to connect`
   - `Connect`
   - `Ignore`
   - `Block` only in overflow or profile-level actions.
3. If the user taps `Connect`, Rain clears local manual-disconnect intent for that peer and starts the normal connection path.
4. If the user ignores/rejects, no session starts and the sender sees a rejected/ignored state.
5. Duplicate requests from the same peer collapse into one visible prompt.

## Proposed Firebase Shape

```text
connectionRequests/{to}/{requestId}
  requestId: string
  from: username
  to: username
  status: pending | seen | accepted | rejected | canceled | expired | failed
  createdAt: server timestamp millis
  updatedAt: server timestamp millis
  expiresAt: server timestamp millis
  senderPresenceAt: millis
  senderDevice: android | windows | unknown
  reason: manualConnect

connectionRequestOutboxes/{from}/{requestId}
  requestId: string
  from: username
  to: username
  status: pending | seen | accepted | rejected | canceled | expired | failed
  createdAt: server timestamp millis
  updatedAt: server timestamp millis
  expiresAt: server timestamp millis

connectionNotificationConfig/global
  defaultDailyLimit: number
  defaultCooldownMs: number
  defaultPerTargetDailyLimit: number
  maxPendingOutboundPerUser: number
  maxPendingInboundPerUser: number
  requestTtlMs: number
  maxBurstPerMinute: number
  enabled: boolean
  updatedAt: server timestamp millis

connectionNotificationEntitlements/{username}
  dailyLimitOverride: number | null
  extraCredits: number
  unlimitedUntil: millis | null
  disabled: boolean
  reason: string
  expiresAt: millis | null
  updatedAt: server timestamp millis
  updatedBy: admin uid or operator label

connectionNotificationUsage/{username}/{yyyyMMdd}
  used: number
  extraCreditsUsed: number
  rejectedByCooldown: number
  rejectedByLimit: number
  lastRequestAt: millis
  burstWindowStartedAt: millis
  burstCount: number

connectionNotificationTargetUsage/{from}/{to}/{yyyyMMdd}
  used: number
  rejectedByCooldown: number
  rejectedByLimit: number
  lastRequestAt: millis

connectionNotificationPairLocks/{fromToKey}
  requestId: string
  from: username
  to: username
  status: pending
  expiresAt: server timestamp millis
  createdAt: server timestamp millis

connectionNotificationMutes/{username}/{peer}
  muted: boolean
  updatedAt: server timestamp millis

connectionNotificationAudit/{yyyyMMdd}/{eventId}
  from: username
  to: username
  decision: allowed | denied
  reason: string
  requestId: string | null
  createdAt: server timestamp millis
```

The inbox is authoritative for the receiver. The outbox is a mirrored status projection for the sender. Both are ephemeral and cleaned by TTL.

The quota, entitlement, and usage paths are authoritative guardrail state. They must be updated with a transaction from trusted backend code. The Flutter app may read a sanitized quota summary for UI, but it must not write quota counters, grant credits, or bypass cooldowns.

## Guardrail Model

Connection notifications are intentionally rate-limited because every request creates Firebase writes, watcher events, optional local notifications, sound events, and user attention cost.

Default policy for first implementation:

- Daily free connect notifications per user: 30.
- Extra credits: consumed after the daily free allowance.
- Cooldown between requests to the same peer: 20 seconds.
- Per-target daily limit: 8 requests to the same peer.
- Max pending outbound requests per user: 5.
- Max pending inbound requests per receiver: 10.
- Max burst: 6 requests per minute.
- Request TTL: 45 seconds.

Firebase/admin override examples:

- Increase `connectionNotificationEntitlements/eslam/extraCredits` for one-off extra usage.
- Set `dailyLimitOverride` for trusted testers.
- Set `unlimitedUntil` for internal accounts.
- Set `disabled: true` to shut off abuse from one account without blocking the whole app.
- Change `connectionNotificationConfig/global/defaultDailyLimit` if production usage needs a different limit.

Security rule: client writes must never be allowed to mutate `connectionNotificationConfig`, `connectionNotificationEntitlements`, or `connectionNotificationUsage`. Request creation should go through a backend function so quota checks and request writes happen as one server-side operation.

## Critical Guardrails

These are non-negotiable for the feature to ship:

1. Server-only request creation.
   Clients must call a trusted backend function. They must not directly create inbox/outbox request rows.

2. Firebase-owned quota and credits.
   Daily usage, extra credits, admin overrides, and disabled flags live in Firebase/backend state and are updated transactionally.

3. Pending request dedupe.
   Only one pending request may exist for a sender/receiver pair. Repeated taps reuse the existing request or return its current status.

4. Per-target cooldown and daily limit.
   A sender cannot spend their whole global quota repeatedly pinging one peer.

5. Receiver protection.
   Receiver mute, block, inbox cap, offline, and stale presence checks happen before notifications, sounds, push, or inbox writes.

6. Global kill switch.
   `connectionNotificationConfig/global/enabled = false` disables new request creation immediately with a clean user message.

7. Abuse audit diagnostics.
   Allowed and denied backend decisions are recorded in a limited server audit log with reason and timestamp.

8. Admin override traceability.
   Extra credits and overrides include `updatedBy`, `reason`, and optional expiry so test/internal grants do not become invisible permanent state.

9. No silent blocking.
   Every denied, ignored, rate-limited, expired, disabled, or failed action must return a typed decision with a user-facing message and diagnostics reason. If exposing exact receiver state would leak privacy, use a neutral message but still explain what the user can do next.

## User-Facing Error Message Matrix

Every blocked action must map to one of these messages. Widgets must render the message through the normal error surface, toast/snackbar, inline status, or notification prompt. The runtime must also record the raw reason in diagnostics.

| Reason code | User-facing message | Notes |
| --- | --- | --- |
| `peerOffline` | `@peer is offline. Keep both apps open, then try again.` | No request row is created. |
| `presenceUnknown` | `Could not confirm @peer is online. Try again.` | Fail closed; no request row is created. |
| `notAcceptedFriend` | `You can only connect with accepted friends.` | Do not reveal hidden relationship data. |
| `blocked` | `Connection request unavailable for this peer.` | Neutral wording to avoid leaking block direction. |
| `mutedByReceiver` | `@peer is not receiving connection requests right now.` | Do not say they muted you. |
| `manualDisconnectActive` | `You disconnected @peer. Press Connect again to send a request.` | Applies to local manual intent. |
| `activeCall` | `Finish the active call before sending connection requests.` | Keep global one-call rule. |
| `activeTransfer` | `Finish the active file transfer before sending connection requests.` | Keep transfer conflict rule. |
| `rateLimited` | `Connection requests are cooling down. Try again in {seconds}s.` | Include retry-after when available. |
| `dailyLimitExceeded` | `Daily connection request limit reached.` | If extra credits exist, message may append `Using extra credits.` before allowing. |
| `extraCreditsExhausted` | `No extra connection request credits left.` | Include reset/renewal context if configured. |
| `perTargetLimitExceeded` | `You have sent too many requests to @peer today.` | Protects one receiver from repeated pings. |
| `tooManyPendingRequests` | `Too many connection requests are still pending. Cancel or wait for one to expire.` | Sender-side pending cap. |
| `receiverInboxFull` | `@peer has too many pending requests right now. Try again later.` | Receiver protection before quota spend. |
| `duplicatePendingRequest` | `Connection request already sent to @peer.` | Show existing pending request status instead of creating another row. |
| `notificationsDisabledByAdmin` | `Connection requests are disabled for this account.` | Per-user disabled flag. |
| `notificationsTemporarilyDisabled` | `Connection requests are temporarily unavailable.` | Global kill switch. |
| `expired` | `Connection request expired. Send a new request if you still want to connect.` | Sender and receiver terminal state. |
| `backendRejected` | `Connection request could not be sent. Try again.` | Diagnostics keep raw Firebase/function error. |
| `permissionDenied` | `Notifications are disabled. You will still see requests inside Rain.` | OS notification permission fallback. |
| `notificationUnavailable` | `System notifications are unavailable. Rain will show in-app alerts instead.` | Platform/plugin fallback. |

Message rules:

- Never disable a visible action without a tooltip, inline reason, or immediate feedback on tap.
- Do not consume quota or extra credits for attempts blocked before request creation.
- Do not show a receiver notification for any denied attempt.
- Use neutral wording when exact state could expose privacy-sensitive information.
- Diagnostics must keep the exact internal reason even when UI wording is neutral.
- Tests must assert both the reason code and the user-facing message for every guardrail.

## Public Types

- `ConnectionNotificationStatus`
  - `pending`
  - `seen`
  - `accepted`
  - `rejected`
  - `canceled`
  - `expired`
  - `failed`

- `ConnectionNotificationDirection`
  - `inbound`
  - `outbound`

- `ConnectionNotificationDecision`
  - `connect`
  - `ignore`
  - `cancel`
  - `reject`

- `ConnectionNotificationFailureReason`
  - `peerOffline`
  - `presenceUnknown`
  - `notAcceptedFriend`
  - `blocked`
  - `mutedByReceiver`
  - `manualDisconnectActive`
  - `activeCall`
  - `activeTransfer`
  - `rateLimited`
  - `dailyLimitExceeded`
  - `extraCreditsExhausted`
  - `tooManyPendingRequests`
  - `receiverInboxFull`
  - `perTargetLimitExceeded`
  - `duplicatePendingRequest`
  - `notificationsDisabledByAdmin`
  - `notificationsTemporarilyDisabled`
  - `expired`
  - `backendRejected`
  - `permissionDenied`
  - `notificationUnavailable`

- `ConnectionNotificationQuotaSnapshot`
  - `dailyLimit`
  - `usedToday`
  - `extraCreditsRemaining`
  - `cooldownRemainingMs`
  - `perTargetRemainingToday`
  - `pendingOutboundCount`
  - `pendingInboundCount`
  - `unlimitedUntil`
  - `disabled`

## Phase 00: Acceptance Lock And Baseline

**Purpose:** Define exactly what the notification feature is allowed to change before implementation begins.

- [ ] Confirm the feature is about data peer connection requests, not friend requests and not voice/video calls.
- [ ] Capture current manual connect, disconnect, recovering, and passive listener behavior.
- [ ] Lock the rule that inbound notifications never auto-connect without user action.
- [ ] Lock the rule that manual disconnect still blocks auto-recovery.
- [ ] Add skipped regression tests describing the desired inbound/outbound behavior.
- [ ] Record current Firebase paths and rule boundaries.

**Acceptance:**

- Plan has explicit tests for outbound pending, inbound prompt, reject, cancel, expiry, and manual disconnect.
- No implementation phase can reuse `friendRequests` for connection notifications.

## Phase 01: Connection Notification Contract

**Purpose:** Add typed models before touching runtime behavior.

- [ ] Add connection notification value types in `packages/protocol_brain`.
- [ ] Add parser validation for username, request id, timestamps, status, expiry, and direction.
- [ ] Add cleanup-safe parsing for corrupt old entries.
- [ ] Add failure reason mapping for UI messages.
- [ ] Add one exhaustive `ConnectionNotificationFailureReason -> userMessage` mapper.
- [ ] Add tests that fail if any reason code lacks a non-empty message.
- [ ] Add fake adapter support for tests.

**Acceptance:**

- Invalid payloads are rejected or cleanup-parsed without crashing streams.
- Unknown statuses are ignored safely.
- Expired entries are distinguishable from rejected/canceled entries.
- Every typed failure reason has a stable user-facing message.

## Phase 02: Firebase Schema, Rules, And Cleanup

**Purpose:** Add ephemeral backend support with strict safety rules.

- [ ] Add `connectionRequests/{to}/{requestId}` rules.
- [ ] Add `connectionRequestOutboxes/{from}/{requestId}` rules.
- [ ] Add read-only client access to sanitized quota summaries if needed.
- [ ] Add admin-only paths:
  - `connectionNotificationConfig/global`
  - `connectionNotificationEntitlements/{username}`
  - `connectionNotificationUsage/{username}/{yyyyMMdd}`
  - `connectionNotificationTargetUsage/{from}/{to}/{yyyyMMdd}`
  - `connectionNotificationPairLocks/{fromToKey}`
  - `connectionNotificationAudit/{yyyyMMdd}/{eventId}`
- [ ] Add receiver-owned mute path:
  - `connectionNotificationMutes/{username}/{peer}`
- [ ] Require authenticated user ownership for writes.
- [ ] Require accepted two-way friendship.
- [ ] Require no block in either direction.
- [ ] Require no receiver mute for the sender.
- [ ] Require fresh receiver presence for creating new inbound requests.
- [ ] Prevent users from writing requests on behalf of another sender.
- [ ] Prevent client writes to config, entitlements, usage counters, target counters, pair locks, and audit rows.
- [ ] Prevent direct client creation of request rows if the backend function owns quota enforcement.
- [ ] Allow receiver to mark `seen`, `accepted`, or `rejected`.
- [ ] Allow sender to mark `canceled`.
- [ ] Allow receiver to create/update/delete their own mute rows.
- [ ] Add cleanup function support for expired request inbox/outbox entries.
- [ ] Add cleanup function support for expired `connectionNotificationPairLocks`.
- [ ] Add cleanup or daily TTL rules for old usage/audit rows.
- [ ] Add rule tests and cleanup tests.

**Acceptance:**

- Offline/stale receivers cannot receive new connection notification rows.
- Blocked or unaccepted users cannot create requests.
- Muted senders cannot create requests to the receiver.
- Users cannot grant themselves credits or reset their own counters.
- Users cannot bypass dedupe by writing pair locks or request rows directly.
- Expired rows are cleaned without deleting active newer requests.

## Phase 03: Server Quota, Credit, And Rate-Limit Enforcement

**Purpose:** Protect Firebase limits and user attention with backend-owned guardrails.

- [ ] Add a trusted backend entry point for creating connection requests, preferably a callable/HTTPS Cloud Function:
  - validates Firebase Auth
  - resolves authenticated username
  - validates target peer
  - validates accepted friendship and block state
  - validates fresh receiver presence
  - checks receiver mute state
  - checks global feature enabled flag
  - checks per-user disabled flag
  - checks same-peer cooldown
  - checks per-target daily limit
  - checks burst window
  - checks pair pending dedupe lock
  - checks pending outbound count
  - checks receiver pending inbound count
  - checks daily free allowance
  - consumes extra credits only after daily allowance is exhausted
  - writes or reuses pair dedupe lock
  - writes inbox/outbox request rows
  - writes quota usage counters
  - writes per-target usage counters
- [ ] Check receiver protection before spending sender quota.
- [ ] Use transactions for usage counters and pending-request checks.
- [ ] Make request creation idempotent for duplicate taps from the same sender/peer within the cooldown window.
- [ ] Return the existing pending request instead of creating a second Firebase row for duplicate pending sender/receiver attempts.
- [ ] Return a typed quota decision to the app:
  - allowed
  - blocked reason
  - user-facing message
  - remaining daily requests
  - remaining extra credits
  - per-target remaining requests
  - retry-after timestamp when applicable
- [ ] Add an admin maintenance path or documented Firebase console workflow to grant extra credits.
- [ ] Require admin override metadata:
  - `updatedBy`
  - `reason`
  - `expiresAt` or `unlimitedUntil`
- [ ] Add diagnostics/audit rows that do not expose private data:
  - request id
  - sender
  - receiver
  - decision
  - denied reason
  - consumed free/extra credit
  - retryAfter
  - createdAt
- [ ] Ensure cancel/reject/expire decrements pending counts or computes pending counts from live request rows.

**Acceptance:**

- Client cannot exceed limits by editing local storage, replaying UI actions, or writing directly to Firebase.
- Admin can increase a user entitlement in Firebase and the next request uses the new value.
- Extra credits are consumed only after free daily allowance.
- Rate-limited attempts create no inbox/outbox request rows.
- Receiver mute/block/offline/inbox-full checks reject before consuming sender quota.
- Duplicate pending requests create no extra Firebase inbox/outbox rows.
- Per-target limits stop harassment even when global quota or extra credits remain.
- Global kill switch returns a clean `temporarily unavailable` decision.
- Every denied backend decision returns a deterministic user-safe message.

## Phase 04: Protocol Adapter API

**Purpose:** Expose connection notifications through `protocol_brain`, not directly from widgets.

- [ ] Add adapter methods:
  - `createConnectionRequest(peerId)` through the trusted backend entry point
  - `watchIncomingConnectionRequests(username)`
  - `watchOutgoingConnectionRequests(username)`
  - `watchConnectionNotificationQuota(username)` or `fetchConnectionNotificationQuota(username)`
  - `markConnectionRequestSeen(requestId)`
  - `acceptConnectionRequest(requestId)`
  - `rejectConnectionRequest(requestId)`
  - `cancelConnectionRequest(requestId)`
  - `cleanupConnectionRequest(requestId)`
- [ ] Mirror behavior in fake adapter.
- [ ] Add retry and idempotency rules.
- [ ] Keep WebRTC room/session creation outside this adapter.

**Acceptance:**

- Adapter can create, observe, accept, reject, cancel, and expire requests in tests.
- Duplicate create attempts for the same peer collapse or supersede cleanly.
- Adapter exposes quota decisions without requiring widgets to understand Firebase internals.

## Phase 05: Runtime Guard Integration

**Purpose:** Route all user connect actions through one central policy.

- [ ] Extend `RuntimeInteractionGuard` with:
  - `canSendConnectionNotification(peerId)`
  - `canAcceptConnectionNotification(peerId, requestId)`
  - `canCancelConnectionNotification(peerId, requestId)`
- [ ] Use existing active call and active file transfer blocks.
- [ ] Block notifications for offline, stale, unaccepted, blocked, or presence-unknown peers.
- [ ] Block or delay attempts while server quota says cooldown, per-target limit, daily limit, pending limit, disabled, receiver muted, or extra credits exhausted.
- [ ] Surface the message for every blocked decision through UI, not only diagnostics.
- [ ] Do not allow notification creation to clear manual disconnect by itself.
- [ ] Clear manual disconnect only when the user explicitly accepts/connects.

**Acceptance:**

- Pressing `Connect` on an offline peer does not write a request.
- Pressing `Connect` while out of credits does not write a request and shows remaining/retry information.
- Pressing `Connect` when the receiver muted requests does not write a request and does not notify the receiver.
- No `canSendConnectionNotification` denial is silent.
- Manual-disconnected peer does not auto-recover from inbound request arrival.
- Explicit inbound `Connect` clears manual intent only for that peer.

## Phase 06: Outbound Runtime Flow

**Purpose:** Make sender-side behavior predictable.

- [ ] Change user-triggered `connectPeer(peerId)` to create an outbound notification before waiting on a peer when appropriate.
- [ ] Show outbound pending state while request is pending.
- [ ] Add timeout, default 45 seconds unless product decides otherwise.
- [ ] Add `Cancel` behavior.
- [ ] If receiver accepts, call the existing connection path.
- [ ] If receiver rejects or request expires, keep session disconnected and show a clear message.
- [ ] If a direct passive offer succeeds before acceptance, reconcile the request to `accepted` or `connected` without duplicate UI.
- [ ] Show guardrail messages:
  - `Connection requests are cooling down. Try again in {n}s.`
  - `Daily connection request limit reached.`
  - `No extra connection request credits left.`
  - `Too many pending connection requests.`
  - `You have sent too many requests to @peer today.`
  - `@peer is not receiving connection requests right now.`
  - `Connection requests are temporarily unavailable.`

**Acceptance:**

- Sender never waits silently.
- Sender can cancel.
- Sender sees a terminal result for reject, expire, offline, and failed backend writes.
- Sender sees no outbound pending state when backend denies quota.

## Phase 07: Inbound Runtime Flow

**Purpose:** Make receiver-side behavior reliable and non-invasive.

- [ ] Start inbound watcher after login and accepted-friend sync.
- [ ] Validate each inbound request through current relationship and block state.
- [ ] Collapse multiple pending requests from the same sender.
- [ ] Mark visible requests as `seen`.
- [ ] Accept starts existing `connectPeer(peerId)` with explicit user intent.
- [ ] Reject marks request terminal and leaves all sessions unchanged.
- [ ] Add receiver-side `Mute requests from @peer` action that writes `connectionNotificationMutes/{self}/{peer}`.
- [ ] If an active global call or transfer blocks acceptance, show a typed message and keep the request pending or reject based on product choice.

**Acceptance:**

- Inbound prompt appears only for valid accepted friends.
- Invalid or stale request rows do not crash the runtime.
- Muting a peer removes their pending prompts locally and prevents future request prompts server-side.
- Accepting one peer does not affect any other peer connection state.

## Phase 08: In-App Notification UI

**Purpose:** Add visible prompts without making the app feel noisy.

- [ ] Add a compact top-level notification tray for inbound connection requests.
- [ ] Add per-chat outbound pending state near the connection/status area.
- [ ] Add a connection request badge in the friends rail/list.
- [ ] Add quota-aware outbound affordances:
  - remaining requests today where space allows
  - retry-after text when cooling down
  - per-peer cooldown/per-target limit text only when relevant
  - disabled state when admin-disabled
- [ ] Add disabled-action explanations:
  - tooltip on desktop
  - inline helper or snackbar on mobile
  - accessible semantic label for screen readers
- [ ] Add receiver protection affordances:
  - mute requests from this peer
  - unmute requests from this peer in friend/profile/settings surface
  - quiet rejection language that does not reveal more private state than needed
- [ ] Add desktop-friendly hover tooltips and mobile-friendly tap targets.
- [ ] Use Rain visual language: minimal dark ink surfaces, cyan/mint status, no noisy decorations.
- [ ] Ensure prompts respect safe areas and do not overlap call UI, snackbars, keyboard, or bottom nav.

**Acceptance:**

- Inbound request is visible when user is on any tab.
- Outbound pending is visible in the relevant chat.
- No duplicate prompts for the same peer.
- Quota UI never implies the user can bypass server limits.
- Every disabled button or denied tap explains why.
- Receiver mute controls are reachable without unfriending or blocking.

## Phase 09: OS Local Notifications

**Purpose:** Notify the user outside the active Rain window where platform support allows.

- [ ] Add a local notification abstraction:
  - `showConnectionRequestNotification`
  - `dismissConnectionRequestNotification`
  - `showConnectionRequestResultNotification`
- [ ] Android:
  - Add runtime notification permission flow for Android 13+.
  - Use a dedicated `Connection requests` notification channel.
  - Only show local notifications while Rain runtime is active or platform lifecycle allows it.
- [ ] Windows:
  - Add local toast support only if the chosen package supports Windows reliably.
  - Fallback to in-app notification if unavailable.
- [ ] Respect notification settings and quiet mode.
- [ ] Do not add FCM tokens in this phase.
- [ ] Do not show OS notifications for requests blocked by quota, cooldown, pending limits, or admin disable.
- [ ] Do not show OS notifications for duplicate pending requests, receiver-muted requests, blocked users, or offline/stale receivers.
- [ ] When OS notifications cannot be shown, show the in-app fallback message instead of failing silently.

**Acceptance:**

- App-active and minimized notification behavior works without crashing when notification APIs are unavailable.
- Permission denial leaves in-app notifications functional.
- No notification appears for stale/invalid/blocked requests.
- No notification appears for requests that were denied before inbox creation.
- Duplicate pending requests do not create repeated local or OS notifications.
- Notification permission/platform failures produce visible in-app fallback messaging.

## Phase 10: Sound, Rate Limit, And Abuse Controls

**Purpose:** Make notifications noticeable without becoming annoying or abusable.

- [ ] Add sound events:
  - inbound connection request
  - outbound accepted
  - outbound rejected/expired
- [ ] Reuse central sound event router.
- [ ] Burst-compress repeated requests from the same peer.
- [ ] Add local cooldown for repeated requests.
- [ ] Treat backend quota decisions as authoritative; local cooldown only reduces accidental taps and noise.
- [ ] Avoid counting normal chat messages as abuse.

**Acceptance:**

- Multiple quick requests from the same peer produce one prompt and controlled sound.
- Repeated abusive requests are suppressed locally and diagnostically visible.
- Backend-enforced quota still works if local cooldown is bypassed.

## Phase 11: Diagnostics And Recovery

**Purpose:** Make failures reportable.

- [ ] Add diagnostics:
  - `connection_request_outbound_created`
  - `connection_request_outbound_canceled`
  - `connection_request_outbound_expired`
  - `connection_request_inbound_received`
  - `connection_request_inbound_seen`
  - `connection_request_inbound_accepted`
  - `connection_request_inbound_rejected`
  - `connection_request_blocked`
  - `connection_request_corrupt_removed`
  - `connection_request_notification_permission_denied`
  - `connection_request_quota_allowed`
  - `connection_request_quota_denied`
  - `connection_request_credit_consumed`
  - `connection_request_entitlement_loaded`
  - `connection_request_pair_deduped`
  - `connection_request_target_limit_denied`
  - `connection_request_receiver_muted_denied`
  - `connection_request_global_disabled`
- [ ] Include peer id, request id, direction, status, presence freshness, guard reason, quota decision, remaining daily allowance, remaining extra credits, per-target remaining allowance, retry-after, dedupe lock state, and cleanup result.
- [ ] Include `userMessageKey` and rendered message in diagnostics for denied attempts.
- [ ] Ensure diagnostics buffering does not write synchronously per event.

**Acceptance:**

- Exported diagnostics explain why a request did or did not appear.
- Corrupt request entries are removed or ignored without poisoning watcher streams.
- Diagnostics can prove whether a blocked attempt was caused by cooldown, daily limit, pending limit, admin disable, or Firebase failure.
- Diagnostics can distinguish duplicate pending, receiver muted, per-target limit, and global kill-switch denials.
- Diagnostics prove which user-facing message was shown.

## Phase 12: Settings And User Control

**Purpose:** Let users control notification noise.

- [ ] Add settings:
  - `Connection request notifications`
  - `Connection request sound`
  - `Show notifications when minimized`
- [ ] Add a manageable muted-request senders list if the user muted any peers.
- [ ] Show platform permission status.
- [ ] Show a read-only quota summary:
  - requests used today
  - daily limit
  - extra credits remaining
  - cooldown status
- [ ] Add `Test notification` only in diagnostics/developer area if useful.
- [ ] Persist settings in the existing app settings store.

**Acceptance:**

- Turning off connection request notifications suppresses OS notifications but keeps essential in-app prompts.
- Turning off sounds does not suppress visual prompts.
- Quota summary is read-only and updates from Firebase/backend state.
- Unmuting a peer removes only `connectionNotificationMutes/{self}/{peer}` and does not alter friendships or blocks.

## Phase 13: Optional Push Notification Architecture

**Purpose:** Define the future path for closed-app notification support without forcing it into v1.

- [ ] Add a separate spec before implementation.
- [ ] Introduce `notificationTokens/{username}/{deviceId}` only after security review.
- [ ] Use Firebase Cloud Messaging for Android.
- [ ] Define token rotation, logout deletion, blocked-user filtering, and rate limiting.
- [ ] Reuse the same server quota/credit decision before sending push notifications.
- [ ] Decide whether Windows needs push, local-only, or no closed-app notifications.
- [ ] Update privacy policy and release notes before shipping.

**Acceptance:**

- No FCM token schema is added accidentally in v1.
- Closed-app notification support has a separate explicit approval gate.
- Push cannot bypass connection request quota.

## Phase 14: Automated Validation Gate

**Unit Tests**

- [ ] Contract parsing rejects malformed request payloads.
- [ ] Fake adapter creates inbox/outbox entries and mirrors statuses.
- [ ] Runtime guard denies offline, blocked, unaccepted, active-call, and active-transfer cases.
- [ ] Runtime guard denies cooldown, per-target limit, daily limit, extra credit exhaustion, admin disable, receiver mute, global kill switch, and too many pending requests.
- [ ] Every `ConnectionNotificationFailureReason` maps to a non-empty user-facing message.
- [ ] Neutral privacy-safe messages still preserve exact internal diagnostics reason.
- [ ] Manual disconnect blocks auto-connect from inbound request arrival.
- [ ] Explicit inbound accept clears manual disconnect for only that peer.
- [ ] Outbound cancel prevents later accept from starting a session.
- [ ] Expired requests do not start sessions.
- [ ] Duplicate requests collapse into one visible request.
- [ ] Server quota decision consumes free allowance before extra credits.
- [ ] Server quota decision does not consume quota for blocked, muted, offline, stale, inbox-full, or duplicate-pending attempts.
- [ ] Admin entitlement changes are reflected without app reinstall.

**Widget Tests**

- [ ] Inbound prompt renders on mobile and desktop.
- [ ] Outbound pending state renders in chat status area.
- [ ] Friend list badge appears for pending inbound request.
- [ ] Prompt respects safe areas and does not overlap call surfaces.
- [ ] Notification settings render and persist.
- [ ] Quota summary renders as read-only state.
- [ ] Cooldown and no-credit messages fit mobile and desktop.
- [ ] Disabled connect buttons expose reason through tooltip/semantics on desktop.
- [ ] Denied mobile taps show snackbar/inline error with the mapped message.
- [ ] Receiver mute/unmute controls render without exposing unrelated block/unfriend actions.
- [ ] Duplicate pending requests do not create duplicate visible prompts.

**Firebase Tests**

- [ ] Offline receiver cannot receive request.
- [ ] Unaccepted friend cannot receive request.
- [ ] Blocked user cannot create request.
- [ ] Receiver can accept/reject.
- [ ] Sender can cancel.
- [ ] Cleanup removes expired inbox/outbox rows.
- [ ] Client cannot write config, entitlements, or usage counters.
- [ ] Client cannot write target usage counters, pair locks, or audit rows.
- [ ] Backend function refuses quota-exceeded requests before writing inbox/outbox rows.
- [ ] Extra credits can be granted by admin data and consumed by request creation.
- [ ] Backend function reuses or returns existing pending pair lock instead of creating duplicate request rows.
- [ ] Backend function enforces per-target daily limit even when global quota remains.
- [ ] Backend function refuses muted receivers before notification fan-out.
- [ ] Global kill switch blocks request creation immediately.
- [ ] Every denied backend function response includes reason code, user-safe message, and diagnostics-safe raw detail.

**Validation Commands**

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

## Phase 15: Release Gate

- [ ] Commit each completed phase on `dev`.
- [ ] Push `dev`.
- [ ] Trigger cloud build only after automated validation passes.
- [ ] Verify Android v7a, Android v8/v9, and Windows artifacts.
- [ ] Update release notes:
  - connection request notifications
  - app-open/local notification limitation
  - no closed-app push in v1 unless Phase 12 is separately implemented

## Non-Goals For V1

- No closed-app push notification.
- No group connection requests.
- No connection request history.
- No automatic connection acceptance.
- No local-storage-only quota or credit system.
- No client-side bypass for admin/test accounts; admin/test usage still goes through Firebase entitlements.
- No paid billing or purchase flow for extra credits.
- No receiver-side forced notification delivery; receiver mute/block/offline protections always win.
- No changes to voice/video media transport.
- No changes to chat message encryption or delivery.

## Open Decisions

- Should inbound request expiry be 30 seconds, 45 seconds, or 60 seconds?
- What should the default daily free request limit be for normal users?
- Should extra credits reset daily, monthly, or remain until consumed?
- Should admin/test accounts use `extraCredits`, `dailyLimitOverride`, or `unlimitedUntil`?
- Should blocked quota attempts be invisible to the receiver, or should repeated abuse produce moderation diagnostics only?
- Should quota summaries be visible in Settings, beside the Connect button, or only after a quota error?
- Should receiver mute be temporary by default, or permanent until manually removed?
- Should duplicate pending taps refresh the existing request timestamp, or keep the original expiry to prevent nagging?
- Should reject tell the sender `Rejected` or softer `Unavailable`?
- Should Windows use real toast notifications in v1, or in-app/minimized-window notifications only?
- Should an inbound request from the currently open chat show a prompt, inline status, or both?
- Should accepting a connection request automatically select that chat?
