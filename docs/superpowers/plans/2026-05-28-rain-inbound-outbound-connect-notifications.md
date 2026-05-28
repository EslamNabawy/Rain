# Rain Inbound And Outbound Connect Notification Plan

> **For agentic workers:** implement this plan phase by phase on `dev`. Commit after each completed phase. Do not change the working chat, call, file transfer, login, or release workflows unless a phase explicitly requires it.

## Goal

Add a clear notification flow for manual peer connection attempts. When Alice wants to connect to Bob, Alice should see an outbound pending state and Bob should receive an inbound notification that Alice wants to connect. Bob can connect, ignore, or reject. The feature must make manual connection intent understandable without reintroducing unwanted auto-reconnect behavior.

## Product Rules

- Accepted friends only.
- No notification is created for blocked, unaccepted, offline, or stale-presence peers.
- Pressing `Disconnect` still means: do not reconnect until the user explicitly presses `Connect`.
- Inbound connect notifications are advisory; they do not auto-open a WebRTC session without user action.
- Outbound notifications are local progress state plus optional cancellation.
- The app may show OS/local notifications only while Rain is running or background-capable on the platform.
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
```

The inbox is authoritative for the receiver. The outbox is a mirrored status projection for the sender. Both are ephemeral and cleaned by TTL.

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
  - `manualDisconnectActive`
  - `activeCall`
  - `activeTransfer`
  - `rateLimited`
  - `expired`
  - `backendRejected`

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
- [ ] Add fake adapter support for tests.

**Acceptance:**

- Invalid payloads are rejected or cleanup-parsed without crashing streams.
- Unknown statuses are ignored safely.
- Expired entries are distinguishable from rejected/canceled entries.

## Phase 02: Firebase Schema, Rules, And Cleanup

**Purpose:** Add ephemeral backend support with strict safety rules.

- [ ] Add `connectionRequests/{to}/{requestId}` rules.
- [ ] Add `connectionRequestOutboxes/{from}/{requestId}` rules.
- [ ] Require authenticated user ownership for writes.
- [ ] Require accepted two-way friendship.
- [ ] Require no block in either direction.
- [ ] Require fresh receiver presence for creating new inbound requests.
- [ ] Prevent users from writing requests on behalf of another sender.
- [ ] Allow receiver to mark `seen`, `accepted`, or `rejected`.
- [ ] Allow sender to mark `canceled`.
- [ ] Add cleanup function support for expired request inbox/outbox entries.
- [ ] Add rule tests and cleanup tests.

**Acceptance:**

- Offline/stale receivers cannot receive new connection notification rows.
- Blocked or unaccepted users cannot create requests.
- Expired rows are cleaned without deleting active newer requests.

## Phase 03: Protocol Adapter API

**Purpose:** Expose connection notifications through `protocol_brain`, not directly from widgets.

- [ ] Add adapter methods:
  - `createConnectionRequest(peerId)`
  - `watchIncomingConnectionRequests(username)`
  - `watchOutgoingConnectionRequests(username)`
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

## Phase 04: Runtime Guard Integration

**Purpose:** Route all user connect actions through one central policy.

- [ ] Extend `RuntimeInteractionGuard` with:
  - `canSendConnectionNotification(peerId)`
  - `canAcceptConnectionNotification(peerId, requestId)`
  - `canCancelConnectionNotification(peerId, requestId)`
- [ ] Use existing active call and active file transfer blocks.
- [ ] Block notifications for offline, stale, unaccepted, blocked, or presence-unknown peers.
- [ ] Do not allow notification creation to clear manual disconnect by itself.
- [ ] Clear manual disconnect only when the user explicitly accepts/connects.

**Acceptance:**

- Pressing `Connect` on an offline peer does not write a request.
- Manual-disconnected peer does not auto-recover from inbound request arrival.
- Explicit inbound `Connect` clears manual intent only for that peer.

## Phase 05: Outbound Runtime Flow

**Purpose:** Make sender-side behavior predictable.

- [ ] Change user-triggered `connectPeer(peerId)` to create an outbound notification before waiting on a peer when appropriate.
- [ ] Show outbound pending state while request is pending.
- [ ] Add timeout, default 45 seconds unless product decides otherwise.
- [ ] Add `Cancel` behavior.
- [ ] If receiver accepts, call the existing connection path.
- [ ] If receiver rejects or request expires, keep session disconnected and show a clear message.
- [ ] If a direct passive offer succeeds before acceptance, reconcile the request to `accepted` or `connected` without duplicate UI.

**Acceptance:**

- Sender never waits silently.
- Sender can cancel.
- Sender sees a terminal result for reject, expire, offline, and failed backend writes.

## Phase 06: Inbound Runtime Flow

**Purpose:** Make receiver-side behavior reliable and non-invasive.

- [ ] Start inbound watcher after login and accepted-friend sync.
- [ ] Validate each inbound request through current relationship and block state.
- [ ] Collapse multiple pending requests from the same sender.
- [ ] Mark visible requests as `seen`.
- [ ] Accept starts existing `connectPeer(peerId)` with explicit user intent.
- [ ] Reject marks request terminal and leaves all sessions unchanged.
- [ ] If an active global call or transfer blocks acceptance, show a typed message and keep the request pending or reject based on product choice.

**Acceptance:**

- Inbound prompt appears only for valid accepted friends.
- Invalid or stale request rows do not crash the runtime.
- Accepting one peer does not affect any other peer connection state.

## Phase 07: In-App Notification UI

**Purpose:** Add visible prompts without making the app feel noisy.

- [ ] Add a compact top-level notification tray for inbound connection requests.
- [ ] Add per-chat outbound pending state near the connection/status area.
- [ ] Add a connection request badge in the friends rail/list.
- [ ] Add desktop-friendly hover tooltips and mobile-friendly tap targets.
- [ ] Use Rain visual language: minimal dark ink surfaces, cyan/mint status, no noisy decorations.
- [ ] Ensure prompts respect safe areas and do not overlap call UI, snackbars, keyboard, or bottom nav.

**Acceptance:**

- Inbound request is visible when user is on any tab.
- Outbound pending is visible in the relevant chat.
- No duplicate prompts for the same peer.

## Phase 08: OS Local Notifications

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

**Acceptance:**

- App-active and minimized notification behavior works without crashing when notification APIs are unavailable.
- Permission denial leaves in-app notifications functional.
- No notification appears for stale/invalid/blocked requests.

## Phase 09: Sound, Rate Limit, And Abuse Controls

**Purpose:** Make notifications noticeable without becoming annoying or abusable.

- [ ] Add sound events:
  - inbound connection request
  - outbound accepted
  - outbound rejected/expired
- [ ] Reuse central sound event router.
- [ ] Burst-compress repeated requests from the same peer.
- [ ] Add local cooldown for repeated requests.
- [ ] Add backend rate guard if Firebase rules/functions can enforce it safely.
- [ ] Avoid counting normal chat messages as abuse.

**Acceptance:**

- Multiple quick requests from the same peer produce one prompt and controlled sound.
- Repeated abusive requests are suppressed locally and diagnostically visible.

## Phase 10: Diagnostics And Recovery

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
- [ ] Include peer id, request id, direction, status, presence freshness, guard reason, and cleanup result.
- [ ] Ensure diagnostics buffering does not write synchronously per event.

**Acceptance:**

- Exported diagnostics explain why a request did or did not appear.
- Corrupt request entries are removed or ignored without poisoning watcher streams.

## Phase 11: Settings And User Control

**Purpose:** Let users control notification noise.

- [ ] Add settings:
  - `Connection request notifications`
  - `Connection request sound`
  - `Show notifications when minimized`
- [ ] Show platform permission status.
- [ ] Add `Test notification` only in diagnostics/developer area if useful.
- [ ] Persist settings in the existing app settings store.

**Acceptance:**

- Turning off connection request notifications suppresses OS notifications but keeps essential in-app prompts.
- Turning off sounds does not suppress visual prompts.

## Phase 12: Optional Push Notification Architecture

**Purpose:** Define the future path for closed-app notification support without forcing it into v1.

- [ ] Add a separate spec before implementation.
- [ ] Introduce `notificationTokens/{username}/{deviceId}` only after security review.
- [ ] Use Firebase Cloud Messaging for Android.
- [ ] Define token rotation, logout deletion, blocked-user filtering, and rate limiting.
- [ ] Decide whether Windows needs push, local-only, or no closed-app notifications.
- [ ] Update privacy policy and release notes before shipping.

**Acceptance:**

- No FCM token schema is added accidentally in v1.
- Closed-app notification support has a separate explicit approval gate.

## Phase 13: Automated Validation Gate

**Unit Tests**

- [ ] Contract parsing rejects malformed request payloads.
- [ ] Fake adapter creates inbox/outbox entries and mirrors statuses.
- [ ] Runtime guard denies offline, blocked, unaccepted, active-call, and active-transfer cases.
- [ ] Manual disconnect blocks auto-connect from inbound request arrival.
- [ ] Explicit inbound accept clears manual disconnect for only that peer.
- [ ] Outbound cancel prevents later accept from starting a session.
- [ ] Expired requests do not start sessions.
- [ ] Duplicate requests collapse into one visible request.

**Widget Tests**

- [ ] Inbound prompt renders on mobile and desktop.
- [ ] Outbound pending state renders in chat status area.
- [ ] Friend list badge appears for pending inbound request.
- [ ] Prompt respects safe areas and does not overlap call surfaces.
- [ ] Notification settings render and persist.

**Firebase Tests**

- [ ] Offline receiver cannot receive request.
- [ ] Unaccepted friend cannot receive request.
- [ ] Blocked user cannot create request.
- [ ] Receiver can accept/reject.
- [ ] Sender can cancel.
- [ ] Cleanup removes expired inbox/outbox rows.

**Validation Commands**

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
```

## Phase 14: Release Gate

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
- No changes to voice/video media transport.
- No changes to chat message encryption or delivery.

## Open Decisions

- Should inbound request expiry be 30 seconds, 45 seconds, or 60 seconds?
- Should reject tell the sender `Rejected` or softer `Unavailable`?
- Should Windows use real toast notifications in v1, or in-app/minimized-window notifications only?
- Should an inbound request from the currently open chat show a prompt, inline status, or both?
- Should accepting a connection request automatically select that chat?
