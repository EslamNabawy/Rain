# Rain Connection Request Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add inbound and outbound notifications for manual peer connection requests, with Firebase-owned quotas, credits, receiver protection, clear error messages, and no silent blocking.

**Architecture:** All request creation and state transitions go through trusted backend functions. Flutter may watch request inbox/outbox state and render UI, but it cannot create request rows, mutate quota, grant credits, bypass receiver protections, or directly complete request lifecycle transitions that affect counters/locks. Backend guardrails run before any notification fan-out, sound, local notification, or WebRTC connection attempt.

**Tech Stack:** Flutter, Dart, Riverpod, Firebase Auth, Firebase Realtime Database, Firebase Cloud Functions, existing Rain runtime diagnostics, existing sound router, optional local notification plugin behind an abstraction.

---

## Critical Review Of The Previous Plan

The previous plan had the right intent, but it was not yet safe enough to implement. These are the weak or incomplete parts that must be fixed in the rewritten roadmap.

1. **Mutation boundary was not strict enough.**
   The plan said request creation should go through backend code, but also allowed client status writes in places. That creates a bypass path for quota, locks, and audit. Fix: every lifecycle mutation that affects request state, quota, pending counts, locks, or notifications goes through Cloud Functions.

2. **Realtime Database transaction limits were under-specified.**
   RTDB cannot atomically transact many unrelated paths in one operation. Multi-location updates are atomic writes, not conditional cross-path transactions. Fix: use deterministic claim/lock paths, per-request reservation records, idempotent functions, and rollback/finalizer cleanup.

3. **Quota consumption rules were incomplete.**
   The previous plan did not define exactly when a quota is consumed, when it is not consumed, and whether cancel/expire refunds. Fix: quota is consumed only after backend allows and writes a real request. Preflight denials, duplicate pending requests, receiver mute/block/offline, and inbox-full denials do not consume quota. Cancel/ignore/expire after delivery do not refund because Firebase work and receiver attention already happened.

4. **Receiver protection needed to run before sender quota spend.**
   Spending credits before checking block, mute, stale presence, or receiver inbox cap would punish the sender for requests that never notify anyone. Fix: receiver protection gates run first.

5. **Duplicate request handling needed a server lock.**
   Client-side collapse is not enough. Multiple devices, retries, or replay can still create duplicate Firebase rows. Fix: `connectionRequestPairLocks/{pairKey}` is server-owned and deterministic.

6. **Error handling did not cover every denied path.**
   The plan said no silent blocking, but not every backend/runtime/UI path was required to return and render a message. Fix: every denied function response returns `reasonCode`, `userMessage`, and diagnostics detail. Every disabled UI action exposes a tooltip, inline helper, semantic label, or snackbar.

7. **Privacy-safe messages needed stronger rules.**
   Some messages can reveal whether a peer muted, blocked, or is overloaded. Fix: the UI uses neutral wording for privacy-sensitive cases while diagnostics keep exact internal reasons.

8. **Notification dependency was missing.**
   Rain currently has `audioplayers`, but no proven local notification implementation and no FCM token surface. Background services are forced off. Fix: local notifications are a dedicated phase behind an abstraction. Closed-app push is explicitly future work and cannot be implied by v1.

9. **Lifecycle races were incomplete.**
   Missing cases: sender cancels while receiver accepts, request expires while user taps accept, relationship changes while request is pending, app restarts during pending request, function succeeds but client times out. Fix: server request status is the source of truth and transitions are idempotent.

10. **Admin override safety was incomplete.**
    Extra credits need traceability and expiry. Fix: entitlements require `updatedBy`, `reason`, and optional expiry; clients can only read sanitized summaries.

11. **Cleanup and stale lock repair were not foundational enough.**
    If cleanup fails, pair locks and counters can block users indefinitely. Fix: cleanup and stale repair are implemented before UI rollout.

12. **Tests were too broad and late.**
    Tests need to lock each foundation before dependent UI is added. Fix: each phase has targeted unit/Firebase/runtime/widget tests and must pass before the next phase.

---

## Dependency Order

```text
Phase 00 acceptance lock
  -> Phase 01 contracts/messages
    -> Phase 02 Firebase security boundaries
      -> Phase 03 backend function foundation
        -> Phase 04 receiver protection/dedupe
          -> Phase 05 quota/credit engine
            -> Phase 06 lifecycle cleanup/idempotency
              -> Phase 07 protocol adapter
                -> Phase 08 runtime integration
                  -> Phase 09 outbound UI
                    -> Phase 10 inbound UI
                      -> Phase 11 local notification abstraction
                        -> Phase 12 sounds/settings
                          -> Phase 13 diagnostics/admin ops
                            -> Phase 14 optional push spec
                              -> Phase 15 validation
                                -> Phase 16 release
```

No UI phase may start until backend responses are typed, idempotent, quota-safe, and testable with fake adapters.

---

## Final Product Rules

- Only accepted friends can use connection request notifications.
- A request is for manual data-peer connection only. It is not a friend request and not a voice/video call invite.
- Request creation is server-only.
- Flutter never directly writes request rows, quota counters, entitlements, pair locks, audit rows, or pending counters.
- No notification is created for blocked, muted, unaccepted, offline, stale-presence, inbox-full, or quota-denied paths.
- Receiver protection runs before sender quota spend.
- One pending request per sender/receiver pair.
- Pressing `Disconnect` still means no reconnect until explicit user action.
- Inbound prompts never auto-connect without user action.
- Every denied action shows a user-facing message.
- Privacy-sensitive denials use neutral messages.
- Diagnostics keep exact internal reason codes.
- Closed-app push notifications are not v1.

---

## File Structure

### New Files

- `packages/protocol_brain/lib/src/connection_request_contract.dart`
  - Request status enum, reason enum, decision objects, payload parser, message mapper, quota snapshot models.

- `packages/protocol_brain/lib/src/connection_request_adapter.dart`
  - Abstract adapter API used by app runtime.

- `packages/protocol_brain/lib/src/testing/fake_connection_request_adapter.dart`
  - In-memory fake for runtime tests.

- `packages/protocol_brain/test/connection_request_contract_test.dart`
  - Parser, reason mapping, status transition, and message coverage tests.

- `packages/protocol_brain/test/connection_request_firebase_contract_test.dart`
  - Rules/function contract expectations for forbidden direct writes and allowed reads.

- `apps/rain/lib/application/runtime/connection_request_runtime.dart`
  - Runtime watcher, outbound send/cancel, inbound accept/reject/mute, state reconciliation.

- `apps/rain/lib/application/runtime/connection_request_state.dart`
  - Immutable UI/runtime state models.

- `apps/rain/lib/application/runtime/connection_request_messages.dart`
  - App-level message formatting using protocol reason codes.

- `apps/rain/lib/presentation/widgets/connection_requests/connection_request_tray.dart`
  - Top-level inbound request prompt surface.

- `apps/rain/lib/presentation/widgets/connection_requests/connection_request_status_chip.dart`
  - Outbound pending and terminal status chip in chat/connection area.

- `apps/rain/lib/infrastructure/notifications/rain_notification_service.dart`
  - Platform abstraction for local notification behavior and fallback.

- `apps/rain/test/connection_request_runtime_test.dart`
  - Runtime guard, watcher, idempotency, restart, and race tests.

- `apps/rain/test/connection_request_widgets_test.dart`
  - Inbound/outbound UI, disabled reasons, safe-area, desktop/mobile behavior.

- `backend/firebase/functions/connectionRequests.js`
  - Callable/HTTPS function implementation for create/cancel/accept/reject/mute/quota summary.

- `backend/firebase/functions/connectionRequestGuardrails.js`
  - Pure guardrail helpers for quota, dedupe, receiver protection, messages, and audit payloads.

- `backend/firebase/functions/connectionRequestCleanup.js`
  - Cleanup/finalizer helpers for expired requests, stale pair locks, old audit rows, and stale reservations.

- `backend/firebase/functions/test/connectionRequests.test.js`
  - Backend function tests for lifecycle, quota, races, and denial responses.

- `docs/releases/connection-request-notification-ops.md`
  - Admin runbook for config, entitlements, audit, credits, and emergency kill switch.

### Modified Files

- `packages/protocol_brain/lib/protocol_brain.dart`
  - Export connection request contracts and adapter interface.

- `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
  - Wire Firebase function calls and RTDB watchers behind the adapter.

- `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
  - Construct/start/stop connection request runtime; integrate with connect/disconnect intent.

- `apps/rain/lib/application/runtime/runtime_interaction_guard.dart`
  - Add connection request decisions and no-silent-blocking guarantees.

- `apps/rain/lib/application/state/runtime_providers.dart`
  - Expose request state and actions through Riverpod.

- `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
  - Show outbound pending status, disabled reasons, and request action wiring.

- `apps/rain/lib/presentation/widgets/home/friends_list.dart`
  - Show inbound request badges and mute state on full friend rows and compact rail entries.

- `apps/rain/lib/presentation/screens/home_screen.dart`
  - Render top-level inbound tray and global request messages.

- `apps/rain/lib/presentation/screens/settings_screen.dart`
  - Add notification settings, quota summary, and muted-request senders list.

- `apps/rain/lib/application/audio/sound_event_router.dart`
  - Add controlled connection request sound events.

- `apps/rain/lib/infrastructure/services/app_settings_store.dart`
  - Persist local notification/sound preferences only; not quota.

- `apps/rain/pubspec.yaml`
  - Add local notification dependency only after the notification spike confirms Android and Windows support.

- `backend/firebase/database.rules.json`
  - Deny direct client mutation of server-owned paths; allow safe reads and receiver-owned mute writes if not function-owned.

- `backend/firebase/functions/index.js`
  - Export connection request functions and cleanup schedule.

- `backend/firebase/README.md`
  - Document new Firebase paths and deployment steps.

---

## Firebase Data Model

All usernames are normalized before path construction. Any pair key must be generated with a single helper to avoid path injection or order bugs.

```text
connectionRequests/{to}/{requestId}
  requestId: string
  pairKey: string
  from: username
  to: username
  status: pending | seen | accepted | rejected | canceled | expired | failed
  reason: manualConnect
  createdAt: server millis
  updatedAt: server millis
  expiresAt: server millis
  senderPresenceAt: millis
  receiverPresenceAt: millis
  senderDevice: android | windows | unknown

connectionRequestOutboxes/{from}/{requestId}
  requestId: string
  pairKey: string
  from: username
  to: username
  status: pending | seen | accepted | rejected | canceled | expired | failed
  createdAt: server millis
  updatedAt: server millis
  expiresAt: server millis
  lastReasonCode: string | null

connectionRequestPairLocks/{pairKey}
  requestId: string
  from: username
  to: username
  status: pending
  createdAt: server millis
  expiresAt: server millis

connectionNotificationConfig/global
  enabled: boolean
  defaultDailyLimit: number
  defaultPerTargetDailyLimit: number
  defaultCooldownMs: number
  maxPendingOutboundPerUser: number
  maxPendingInboundPerUser: number
  maxBurstPerMinute: number
  requestTtlMs: number
  auditRetentionDays: number
  usageRetentionDays: number
  updatedAt: server millis

connectionNotificationEntitlements/{username}
  dailyLimitOverride: number | null
  extraCredits: number
  unlimitedUntil: millis | null
  disabled: boolean
  reason: string
  expiresAt: millis | null
  updatedAt: server millis
  updatedBy: admin uid or operator label

connectionNotificationUsage/{username}/{yyyyMMddUtc}
  used: number
  extraCreditsUsed: number
  rejectedByCooldown: number
  rejectedByLimit: number
  rejectedByPending: number
  burstWindowStartedAt: millis
  burstCount: number
  lastRequestAt: millis

connectionNotificationTargetUsage/{from}/{to}/{yyyyMMddUtc}
  used: number
  rejectedByCooldown: number
  rejectedByLimit: number
  lastRequestAt: millis

connectionNotificationMutes/{receiver}/{sender}
  muted: boolean
  updatedAt: server millis

connectionNotificationAudit/{yyyyMMddUtc}/{eventId}
  from: username
  to: username
  requestId: string | null
  pairKey: string | null
  decision: allowed | denied | deduped | finalized
  reasonCode: string
  createdAt: server millis

connectionNotificationReservations/{requestId}
  from: username
  to: username
  pairKey: string
  dayKey: string
  consumedDaily: boolean
  consumedExtraCredit: boolean
  finalized: boolean
  createdAt: server millis
  expiresAt: server millis
```

`connectionNotificationReservations` exists because RTDB transactions are per-path. If a later write fails after quota reservation, cleanup/finalizer can identify and resolve stale reservations without guessing.

---

## Status State Machine

Allowed server transitions:

```text
pending -> seen
pending -> accepted
pending -> rejected
pending -> canceled
pending -> expired
pending -> failed
seen -> accepted
seen -> rejected
seen -> canceled
seen -> expired
seen -> failed
```

Forbidden:

- terminal -> non-terminal
- accepted -> canceled
- rejected -> accepted
- expired -> accepted
- failed -> accepted

Race rules:

- If `accept` and `cancel` race, the first committed terminal transition wins. The loser receives the current terminal status and user message.
- If `accept` and `expire` race, accept succeeds only when `now < expiresAt` at commit time.
- If app restarts, runtime reloads inbox/outbox and resumes the current server state.
- If sender function succeeds but client times out, retry returns `duplicatePendingRequest` with the existing request.
- If friendship, block, or mute changes while pending, cleanup/finalizer moves the request to `failed` or `rejected` with a neutral message.

---

## Error Message Matrix

Every denied action returns `allowed: false`, `reasonCode`, `userMessage`, `retryAfterMs` when relevant, and diagnostics detail. Widgets must show the message through tooltip, inline helper, snackbar, tray, or notification fallback.

| Reason Code | User Message | Privacy / Behavior |
| --- | --- | --- |
| `peerOffline` | `@peer is offline. Keep both apps open, then try again.` | No row, no quota spend. |
| `presenceUnknown` | `Could not confirm @peer is online. Try again.` | No row, no quota spend. |
| `notAcceptedFriend` | `You can only connect with accepted friends.` | No relationship detail leak. |
| `blocked` | `Connection request unavailable for this peer.` | Neutral; exact block side only in diagnostics. |
| `mutedByReceiver` | `@peer is unavailable for connection requests right now.` | Do not say "muted you". |
| `manualDisconnectActive` | `You disconnected @peer. Press Connect again to send a request.` | Local-only state. |
| `activeCall` | `Finish the active call before sending connection requests.` | Local conflict. |
| `activeTransfer` | `Finish the active file transfer before sending connection requests.` | Local conflict. |
| `rateLimited` | `Connection requests are cooling down. Try again in {seconds}s.` | Use backend retry-after. |
| `dailyLimitExceeded` | `Daily connection request limit reached.` | No row; may mention reset if available. |
| `extraCreditsExhausted` | `No extra connection request credits left.` | No row. |
| `perTargetLimitExceeded` | `You have sent too many requests to @peer today.` | No row. |
| `tooManyPendingRequests` | `Too many connection requests are still pending. Cancel or wait for one to expire.` | Sender pending cap. |
| `receiverInboxFull` | `@peer is unavailable for connection requests right now. Try again later.` | Neutralized receiver state. |
| `duplicatePendingRequest` | `Connection request already sent to @peer.` | Show existing request. |
| `notificationsDisabledByAdmin` | `Connection requests are disabled for this account.` | Per-user admin flag. |
| `notificationsTemporarilyDisabled` | `Connection requests are temporarily unavailable.` | Global kill switch. |
| `expired` | `Connection request expired. Send a new request if you still want to connect.` | Terminal. |
| `backendRejected` | `Connection request could not be sent. Try again.` | Raw error only in diagnostics. |
| `permissionDenied` | `Notifications are disabled. You will still see requests inside Rain.` | OS notification fallback. |
| `notificationUnavailable` | `System notifications are unavailable. Rain will show in-app alerts instead.` | Platform fallback. |
| `staleRequest` | `This connection request is no longer valid.` | For accept/reject on old request. |
| `terminalRaceLost` | `This connection request was already handled.` | For accept/cancel race loser. |

Tests must fail if a reason code lacks a non-empty message.

---

## Phase 00: Scope, Threat Model, And Acceptance Lock

**Purpose:** Freeze the exact feature boundary before any implementation.

**Files:**

- Modify: `docs/superpowers/plans/2026-05-28-rain-inbound-outbound-connect-notifications.md`
- Create: `docs/qa/connection-request-notifications-acceptance.md`

**Steps:**

- [ ] Write acceptance doc defining v1 as app-open/minimized connection request notifications only, not closed-app push.
- [ ] Record that existing `friendRequests` and `voiceCallInboxes` are not reused.
- [ ] Record threat model:
  - client replay
  - direct RTDB writes
  - duplicate taps
  - multi-device same account
  - sender cancel vs receiver accept race
  - stale pair locks
  - entitlement abuse
  - receiver harassment
  - Firebase cost spike
- [ ] Add skipped tests in `packages/protocol_brain/test/connection_request_contract_test.dart` for every reason code and state transition.
- [ ] Commit: `docs: lock connection request notification acceptance`

**Validation:**

```powershell
dart run melos run analyze
```

Expected: no new analyzer failures.

---

## Phase 01: Contract, Status Machine, And Message Mapper

**Purpose:** Build the typed foundation used by backend, fake adapters, runtime, and UI.

**Files:**

- Create: `packages/protocol_brain/lib/src/connection_request_contract.dart`
- Modify: `packages/protocol_brain/lib/protocol_brain.dart`
- Create: `packages/protocol_brain/test/connection_request_contract_test.dart`

**Steps:**

- [ ] Define `ConnectionRequestStatus`, `ConnectionRequestReasonCode`, `ConnectionRequestDecision`, `ConnectionRequestQuotaSnapshot`, `ConnectionRequestPayload`, and `ConnectionRequestTransition`.
- [ ] Implement username/request id/pair key validation using normalized usernames only.
- [ ] Implement `isTerminalStatus(status)`.
- [ ] Implement `canTransition(from, to, now, expiresAt)`.
- [ ] Implement exhaustive `messageForConnectionRequestReason(reasonCode, peerLabel, retryAfter)`.
- [ ] Add parser tests for malformed status, invalid timestamps, path-injection usernames, expired payloads, unknown fields, and cleanup-safe parsing.
- [ ] Add message coverage test that iterates every enum value and expects a non-empty message.
- [ ] Add state transition tests for all allowed and forbidden transitions.
- [ ] Commit: `feat(protocol): add connection request contract`

**Validation:**

```powershell
dart test packages/protocol_brain/test/connection_request_contract_test.dart
```

Expected: all tests pass.

---

## Phase 02: Firebase Security Boundaries

**Purpose:** Lock the database so clients cannot bypass backend guardrails.

**Files:**

- Modify: `backend/firebase/database.rules.json`
- Modify: `backend/firebase/README.md`
- Create: `packages/protocol_brain/test/connection_request_firebase_contract_test.dart`

**Rules:**

- Clients may read their own inbox: `connectionRequests/{self}`.
- Clients may read their own outbox: `connectionRequestOutboxes/{self}`.
- Clients may read sanitized quota summary if implemented as a read path.
- Clients may not write:
  - request rows
  - outbox rows
  - usage counters
  - target usage counters
  - entitlements
  - global config
  - pair locks
  - reservations
  - audit rows
- Receiver-owned mute may either be function-owned or directly writable only at `connectionNotificationMutes/{authUsername}/{peer}`. Prefer function-owned if backend operations need audit.

**Steps:**

- [ ] Add denied direct-write rules for server-owned paths.
- [ ] Add safe read rules for own inbox/outbox.
- [ ] Add safe read rules for own quota summary only if the summary path exists.
- [ ] Add tests proving an authenticated user cannot create request rows directly.
- [ ] Add tests proving an authenticated user cannot grant themselves credits.
- [ ] Add tests proving an authenticated user cannot reset usage counters.
- [ ] Add tests proving an authenticated user cannot write pair locks.
- [ ] Add tests proving a user cannot read another user's inbox/outbox.
- [ ] Commit: `feat(firebase): lock connection request rules`

**Validation:**

```powershell
dart test packages/protocol_brain/test/connection_request_firebase_contract_test.dart
```

Expected: direct client bypass attempts are denied.

---

## Phase 03: Backend Function Foundation

**Purpose:** Add trusted mutation entry points before any app runtime uses the feature.

**Files:**

- Create: `backend/firebase/functions/connectionRequests.js`
- Create: `backend/firebase/functions/connectionRequestGuardrails.js`
- Modify: `backend/firebase/functions/index.js`
- Create: `backend/firebase/functions/test/connectionRequests.test.js`

**Callable functions:**

- `createConnectionRequest`
- `cancelConnectionRequest`
- `acceptConnectionRequest`
- `rejectConnectionRequest`
- `markConnectionRequestSeen`
- `muteConnectionRequestsFromPeer`
- `unmuteConnectionRequestsFromPeer`
- `getConnectionRequestQuotaSummary`

**Steps:**

- [ ] Add shared auth resolver that maps Firebase Auth uid to Rain username.
- [ ] Add normalized peer validation and pair key helper.
- [ ] Add server clock helper. Never trust client timestamps.
- [ ] Add standard response shape:
  - `allowed`
  - `requestId`
  - `status`
  - `reasonCode`
  - `userMessage`
  - `retryAfterMs`
  - `quota`
  - `diagnostics`
- [ ] Add exact denial responses for auth missing, unknown user, invalid peer, self-request, backend unavailable, and malformed request.
- [ ] Add unit tests for function response shape and message presence.
- [ ] Commit: `feat(functions): add connection request function shell`

**Validation:**

```powershell
cd backend/firebase/functions
npm test -- connectionRequests
```

Expected: response-shape tests pass.

---

## Phase 04: Receiver Protection And Dedupe Claims

**Purpose:** Prevent harassment and duplicate fan-out before quota is consumed.

**Files:**

- Modify: `backend/firebase/functions/connectionRequestGuardrails.js`
- Modify: `backend/firebase/functions/connectionRequests.js`
- Modify: `backend/firebase/functions/test/connectionRequests.test.js`

**Guard order:**

1. Auth and sender identity.
2. Target username validation.
3. Accepted friendship.
4. Block state.
5. Receiver mute.
6. Receiver fresh presence.
7. Global enabled flag.
8. Per-user disabled flag.
9. Pair lock dedupe.
10. Receiver pending inbox cap.
11. Sender quota/cooldown.
12. Write request and outbox.

**Steps:**

- [ ] Implement receiver block/mute/offline checks before quota spend.
- [ ] Implement deterministic `connectionRequestPairLocks/{pairKey}` transaction:
  - existing non-expired pending lock returns `duplicatePendingRequest`
  - expired lock can be replaced
  - terminal lock can be replaced
- [ ] Implement receiver pending cap using a server-maintained count or bounded query plus pair lock. If a count is used, store and repair it in cleanup.
- [ ] Add rollback of pair lock if later sender quota reservation fails.
- [ ] Add tests:
  - duplicate tap returns existing request
  - muted receiver gets no inbox row
  - blocked peer gets no inbox row
  - offline peer gets no inbox row
  - receiver inbox full gets no inbox row
  - none of those consume sender quota
- [ ] Commit: `feat(functions): add receiver protection and dedupe`

**Validation:**

```powershell
cd backend/firebase/functions
npm test -- connectionRequests
```

Expected: receiver protection and dedupe tests pass.

---

## Phase 05: Quota, Credits, And Entitlements

**Purpose:** Enforce cost and abuse limits from Firebase/backend state.

**Files:**

- Modify: `backend/firebase/functions/connectionRequestGuardrails.js`
- Modify: `backend/firebase/functions/connectionRequests.js`
- Modify: `backend/firebase/functions/test/connectionRequests.test.js`
- Create: `docs/releases/connection-request-notification-ops.md`

**Quota semantics:**

- UTC day key only.
- Free daily allowance is consumed before extra credits.
- `unlimitedUntil` bypasses daily count while still recording audit.
- `disabled` blocks immediately.
- `expiresAt` on entitlement disables stale admin grants.
- Duplicate pending attempts do not consume quota.
- Receiver-protection denials do not consume quota.
- Created request consumes quota even if later canceled, rejected, ignored, or expired.
- Extra credit is decremented only by backend transaction and cannot go below zero.

**Steps:**

- [ ] Implement global config loader with safe defaults.
- [ ] Implement entitlement loader with expiry handling.
- [ ] Implement sender daily quota transaction.
- [ ] Implement per-target daily quota transaction.
- [ ] Implement burst window and cooldown.
- [ ] Implement extra credit decrement transaction.
- [ ] Implement quota reservation record for every successful spend.
- [ ] Implement rollback/finalizer path for partial failures.
- [ ] Add admin runbook explaining how to grant extra credits:
  - set `extraCredits`
  - set `reason`
  - set `updatedBy`
  - set `expiresAt` or `unlimitedUntil`
- [ ] Add tests:
  - daily limit denies after configured limit
  - extra credits allow after free limit
  - extra credits cannot go negative
  - per-target limit denies while global remains
  - cooldown denies with retry-after
  - disabled user denied
  - global kill switch denied
  - expired entitlement ignored
- [ ] Commit: `feat(functions): enforce connection request quotas`

**Validation:**

```powershell
cd backend/firebase/functions
npm test -- connectionRequests
```

Expected: quota and entitlement tests pass.

---

## Phase 06: Lifecycle Transitions, Cleanup, And Race Safety

**Purpose:** Make request state self-healing before UI depends on it.

**Files:**

- Create: `backend/firebase/functions/connectionRequestCleanup.js`
- Modify: `backend/firebase/functions/connectionRequests.js`
- Modify: `backend/firebase/functions/index.js`
- Modify: `backend/firebase/functions/test/connectionRequests.test.js`

**Steps:**

- [ ] Implement `acceptConnectionRequest` with terminal race handling.
- [ ] Implement `cancelConnectionRequest` with terminal race handling.
- [ ] Implement `rejectConnectionRequest` with terminal race handling.
- [ ] Implement `markConnectionRequestSeen` as idempotent.
- [ ] On terminal transition, clear pair lock only if request id matches.
- [ ] On terminal transition, update inbox and outbox mirrors atomically.
- [ ] On expired request cleanup:
  - mark outbox expired or delete based on retention decision
  - remove inbox row
  - remove pair lock if matching
  - finalize reservation
- [ ] On corrupt row cleanup:
  - remove unreadable inbox/outbox rows
  - keep audit event
  - do not delete newer matching pair lock
- [ ] Add scheduled cleanup for:
  - expired requests
  - expired pair locks
  - stale reservations
  - old audit rows
  - expired entitlement overrides
- [ ] Add tests:
  - accept vs cancel first terminal wins
  - accept after expiry returns stale message
  - retry after client timeout returns existing pending request
  - cleanup removes stale pair lock
  - cleanup does not delete newer pair lock
  - corrupt row does not crash watcher-equivalent parser
- [ ] Commit: `feat(functions): add connection request cleanup`

**Validation:**

```powershell
cd backend/firebase/functions
npm test -- connectionRequests
```

Expected: lifecycle and cleanup tests pass.

---

## Phase 07: Protocol Adapter

**Purpose:** Hide Firebase/function details from Rain runtime and widgets.

**Files:**

- Create: `packages/protocol_brain/lib/src/connection_request_adapter.dart`
- Create: `packages/protocol_brain/lib/src/testing/fake_connection_request_adapter.dart`
- Modify: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Modify: `packages/protocol_brain/lib/protocol_brain.dart`
- Create: `packages/protocol_brain/test/connection_request_adapter_test.dart`

**Adapter API:**

- `Future<ConnectionRequestDecision> createConnectionRequest(String peerId)`
- `Future<ConnectionRequestDecision> cancelConnectionRequest(String requestId)`
- `Future<ConnectionRequestDecision> acceptConnectionRequest(String requestId)`
- `Future<ConnectionRequestDecision> rejectConnectionRequest(String requestId)`
- `Future<ConnectionRequestDecision> markConnectionRequestSeen(String requestId)`
- `Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(String peerId)`
- `Future<ConnectionRequestDecision> unmuteConnectionRequestsFromPeer(String peerId)`
- `Future<ConnectionRequestQuotaSnapshot> fetchConnectionRequestQuota()`
- `Stream<List<ConnectionRequestPayload>> watchIncomingConnectionRequests(String username)`
- `Stream<List<ConnectionRequestPayload>> watchOutgoingConnectionRequests(String username)`

**Steps:**

- [ ] Implement adapter interface.
- [ ] Implement fake adapter with the same state transition rules.
- [ ] Implement Firebase adapter using Cloud Functions for mutations and RTDB watchers for reads.
- [ ] Convert function/network errors into `backendRejected` with safe message and raw diagnostics.
- [ ] Add tests:
  - fake adapter mirrors status to inbox/outbox
  - duplicate create returns existing pending request
  - stream ignores corrupt rows and reports diagnostics
  - network failure returns safe message
- [ ] Commit: `feat(protocol): add connection request adapter`

**Validation:**

```powershell
dart test packages/protocol_brain/test/connection_request_adapter_test.dart
```

Expected: adapter tests pass.

---

## Phase 08: Runtime Integration

**Purpose:** Integrate request state with Rain connection intent without breaking manual disconnect.

**Files:**

- Create: `apps/rain/lib/application/runtime/connection_request_runtime.dart`
- Create: `apps/rain/lib/application/runtime/connection_request_state.dart`
- Create: `apps/rain/lib/application/runtime/connection_request_messages.dart`
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `apps/rain/lib/application/runtime/runtime_interaction_guard.dart`
- Modify: `apps/rain/lib/application/state/runtime_providers.dart`
- Create: `apps/rain/test/connection_request_runtime_test.dart`

**Runtime rules:**

- Starting Rain subscribes to incoming/outgoing request streams after identity and accepted friends load.
- Runtime does not auto-connect on inbound request arrival.
- Runtime does not clear manual disconnect unless user explicitly accepts/connects.
- Runtime displays every denied decision message.
- Runtime reconciles pending outbox after restart.
- Runtime handles relationship/block/mute changes by dismissing invalid prompts.

**Steps:**

- [ ] Add `ConnectionRequestRuntime` lifecycle start/stop/dispose.
- [ ] Add Riverpod state projection for incoming requests, outgoing requests, quota summary, and last user message.
- [ ] Add `sendConnectionRequest(peerId)` that calls adapter and never calls WebRTC directly on denial.
- [ ] Add `acceptConnectionRequest(requestId)` that clears manual disconnect only for that peer, then starts existing `connectPeer`.
- [ ] Add `cancel/reject/mute/unmute` actions.
- [ ] Add interaction guard methods.
- [ ] Add tests:
  - offline denied with message
  - duplicate pending shows existing status
  - manual disconnected peer does not auto-connect on inbound request
  - explicit accept clears manual disconnect for one peer only
  - app restart restores pending outbound state
  - active call/file transfer blocks with message
  - adapter failure produces safe message
- [ ] Commit: `feat(rain): add connection request runtime`

**Validation:**

```powershell
dart test apps/rain/test/connection_request_runtime_test.dart
```

Expected: runtime tests pass.

---

## Phase 09: Outbound UI

**Purpose:** Make the sender experience explicit and non-silent.

**Files:**

- Create: `apps/rain/lib/presentation/widgets/connection_requests/connection_request_status_chip.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/link_status.dart`
- Create: `apps/rain/test/connection_request_widgets_test.dart`

**Steps:**

- [ ] Add outbound pending chip near existing connection status.
- [ ] Add `Cancel` action for pending request.
- [ ] Show status text for pending, seen, accepted, rejected, canceled, expired, failed.
- [ ] Disable or intercept Connect with visible reason when guard denies.
- [ ] Desktop: denied/disabled action shows tooltip and semantic label.
- [ ] Mobile: denied tap shows snackbar or inline message.
- [ ] Add tests:
  - pending chip renders
  - cancel button calls runtime
  - duplicate pending message renders
  - daily limit message renders
  - cooldown retry-after renders
  - disabled button exposes semantic reason
- [ ] Commit: `feat(ui): add outbound connection request state`

**Validation:**

```powershell
dart test apps/rain/test/connection_request_widgets_test.dart --name "outbound"
```

Expected: outbound widget tests pass.

---

## Phase 10: Inbound UI

**Purpose:** Give receivers a clean prompt without forcing connection or harassment.

**Files:**

- Create: `apps/rain/lib/presentation/widgets/connection_requests/connection_request_tray.dart`
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/friends_list.dart`
- Modify: `apps/rain/lib/presentation/screens/friend_profile_screen.dart`
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Modify: `apps/rain/test/connection_request_widgets_test.dart`

**Steps:**

- [ ] Add top-level inbound tray visible from any tab.
- [ ] Add `Connect`, `Ignore`, and overflow `Mute requests from @peer`.
- [ ] Add friend list badge for pending inbound request.
- [ ] Collapse duplicate inbound requests from same peer.
- [ ] Add unmute control in friend profile or settings.
- [ ] Ensure tray respects call overlays, safe areas, keyboard, and bottom navigation.
- [ ] Add tests:
  - inbound prompt renders on mobile
  - inbound prompt renders on desktop
  - accept calls runtime
  - reject calls runtime
  - mute removes prompt
  - prompt does not overlap call overlay
  - duplicate inbound prompt collapses
- [ ] Commit: `feat(ui): add inbound connection request tray`

**Validation:**

```powershell
dart test apps/rain/test/connection_request_widgets_test.dart --name "inbound"
```

Expected: inbound widget tests pass.

---

## Phase 11: Local Notification Abstraction

**Purpose:** Notify users when Rain is active/minimized without promising closed-app push.

**Files:**

- Create: `apps/rain/lib/infrastructure/notifications/rain_notification_service.dart`
- Modify: `apps/rain/lib/application/state/runtime_providers.dart`
- Modify: `apps/rain/lib/application/runtime/connection_request_runtime.dart`
- Modify: `apps/rain/pubspec.yaml`
- Create: `apps/rain/test/rain_notification_service_test.dart`

**Dependency gate:**

- [ ] Spike Android and Windows local notification support with a minimal abstraction.
- [ ] Add dependency only after confirming it supports the maintained targets.
- [ ] If Windows support is weak, keep Windows in-app only for v1.

**Steps:**

- [ ] Add `RainNotificationService` interface.
- [ ] Add no-op fallback implementation.
- [ ] Add Android permission handling for Android 13+ if plugin supports it.
- [ ] Add notification channel/category for connection requests.
- [ ] Show local notification only for valid inbound request rows.
- [ ] Dismiss notification on accept/reject/mute/expire/cancel.
- [ ] On permission denied or plugin unavailable, show in-app fallback message.
- [ ] Add tests:
  - permission denied returns `permissionDenied`
  - unavailable plugin returns `notificationUnavailable`
  - blocked/duplicate/muted requests do not show notifications
  - notification dismissed on terminal state
- [ ] Commit: `feat(rain): add connection request notification service`

**Validation:**

```powershell
dart test apps/rain/test/rain_notification_service_test.dart
```

Expected: notification service tests pass.

---

## Phase 12: Sounds, Settings, And User Controls

**Purpose:** Add controlled notification sound and user preferences without abusing attention.

**Files:**

- Modify: `apps/rain/lib/application/audio/sound_event_router.dart`
- Modify: `apps/rain/lib/infrastructure/services/app_settings_store.dart`
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Modify: `apps/rain/test/sound_event_router_test.dart`
- Modify: `apps/rain/test/settings_screen_test.dart`

**Steps:**

- [ ] Add sound events:
  - inbound connection request
  - outbound accepted
  - outbound rejected
  - outbound expired
- [ ] Add burst compression for repeated inbound prompts.
- [ ] Add settings:
  - connection request notifications
  - connection request sound
  - show notifications when minimized
  - muted request senders
- [ ] Add read-only quota summary.
- [ ] Ensure local settings never alter backend quota.
- [ ] Add tests:
  - repeated inbound request sound is compressed
  - sound off suppresses sound only
  - notification off suppresses OS notification only
  - quota summary is read-only
  - unmute removes only mute row
- [ ] Commit: `feat(rain): add connection request settings and sounds`

**Validation:**

```powershell
dart test apps/rain/test/sound_event_router_test.dart
dart test apps/rain/test/settings_screen_test.dart
```

Expected: sound/settings tests pass.

---

## Phase 13: Diagnostics, Admin Ops, And Cost Guardrails

**Purpose:** Make production failures and Firebase usage spikes explainable.

**Files:**

- Modify: `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart`
- Modify: `apps/rain/lib/application/runtime/connection_request_runtime.dart`
- Modify: `backend/firebase/functions/connectionRequests.js`
- Modify: `docs/releases/connection-request-notification-ops.md`

**Steps:**

- [ ] Add client diagnostics:
  - request id
  - peer id
  - direction
  - status
  - reason code
  - user message key
  - rendered message
  - quota summary
  - retry-after
  - notification fallback state
- [ ] Add backend audit for allowed, denied, deduped, terminal, cleanup, and rollback events.
- [ ] Add cost guardrails:
  - global daily created count in audit summary
  - function log warning when denied/created ratio spikes
  - global kill switch runbook
- [ ] Add admin runbook:
  - grant credits
  - disable one account
  - enable/disable global feature
  - inspect audit
  - cleanup stale locks
- [ ] Add tests proving diagnostics include user-facing message and exact internal reason.
- [ ] Commit: `docs: add connection request operations diagnostics`

**Validation:**

```powershell
dart test apps/rain/test/connection_request_runtime_test.dart --name "diagnostics"
cd backend/firebase/functions
npm test -- connectionRequests
```

Expected: diagnostics tests pass.

---

## Phase 14: Optional Closed-App Push Specification

**Purpose:** Design future push without polluting v1.

**Files:**

- Create: `docs/superpowers/specs/connection-request-push-notifications-v2.md`

**Scope:**

- Android Firebase Cloud Messaging token registration.
- Token lifecycle on login/logout/account switch.
- Token deletion on uninstall/inactivity where possible.
- User privacy controls.
- App Check consideration.
- Push send path must reuse the same server guardrail decision.
- No push for blocked/muted/offline-denied/duplicate/quota-denied requests.
- Windows decision: local-only, no push, or future provider.

**Steps:**

- [ ] Write v2 push spec.
- [ ] Explicitly state v1 does not implement token storage.
- [ ] Add security review checklist.
- [ ] Commit: `docs: specify connection request push v2`

**Validation:**

No code validation; docs/spec only.

---

## Phase 15: Integrated Automated Validation Gate

**Purpose:** Prove the full feature works before any build.

**Commands:**

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
cd backend/firebase/functions
npm test
```

**Must Pass:**

- Contract tests.
- Firebase rules tests.
- Backend function tests.
- Runtime tests.
- Widget tests.
- Settings tests.
- Sound tests.
- Diagnostics tests.

**Scenario Coverage:**

- Alice sends Bob a request; Bob accepts; connection starts.
- Alice sends Bob a request; Bob rejects; Alice sees rejected message.
- Alice sends Bob a request; Alice cancels; Bob prompt disappears.
- Alice sends Bob a request; it expires; both sides reconcile.
- Alice taps Connect repeatedly; one request row exists.
- Alice exceeds global daily quota; no request row is created.
- Alice exceeds per-target limit; no request row is created.
- Alice has extra credits; request succeeds after free allowance.
- Alice has no extra credits; request denied with message.
- Bob mutes Alice; Alice gets neutral message; Bob gets no prompt.
- Bob blocks Alice; Alice gets neutral message; no quota spend.
- Bob offline/stale; no row and no quota spend.
- Receiver inbox full; no row and no quota spend.
- Sender cancel vs receiver accept race; first terminal state wins.
- Function succeeds but client times out; retry returns existing pending request.
- App restart restores pending inbox/outbox.
- OS notification permission denied; in-app fallback appears.
- Global kill switch blocks request creation immediately.

**Commit:**

```powershell
git add .
git commit -m "test: validate connection request notifications"
```

---

## Phase 16: Release Gate

**Purpose:** Ship only after the tested backend and app are aligned.

**Steps:**

- [ ] Deploy Firebase rules to staging/test project.
- [ ] Deploy Cloud Functions to staging/test project.
- [ ] Run emulator or staging smoke tests.
- [ ] Update Firebase backend README.
- [ ] Update release notes:
  - connection request notifications
  - quota and credits
  - app-open/minimized notification limitation
  - no closed-app push in v1
- [ ] Push `dev`.
- [ ] Trigger cloud build only after validation passes.
- [ ] Verify Android v7a, Android v8/v9, and Windows artifacts.

**Commit:**

```powershell
git add backend/firebase/README.md docs/releases/connection-request-notification-ops.md
git commit -m "docs: release connection request notifications"
```

---

## Non-Goals For V1

- No closed-app push notification.
- No group connection requests.
- No connection request history.
- No automatic connection acceptance.
- No local-storage quota or credit authority.
- No client-side admin/test bypass.
- No paid purchase flow for extra credits.
- No receiver-forced notification delivery.
- No changes to voice/video media transport.
- No changes to chat message encryption or delivery.

---

## Remaining Product Decisions

These are not blockers for foundation work, but must be resolved before UI copy is finalized.

- Is request TTL `45s` or another value?
- Is normal user daily limit `30`, lower, or remote-config only?
- Do extra credits persist until consumed, or expire monthly?
- Should receiver mute default to permanent until unmuted?
- Should duplicate pending taps refresh expiry or keep original expiry?
- Should rejection copy say `Rejected`, `Unavailable`, or `No response`?
- Should accepting a request auto-select that chat?
- Should Windows v1 use system toast or in-app only?
- Should quota summary show always in Settings, or only after a quota error?

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-28-rain-inbound-outbound-connect-notifications.md`.

Execution options:

1. **Subagent-driven implementation, recommended**: dispatch a fresh implementation worker per phase, review between phases, and keep commits small.
2. **Inline implementation**: execute phases in this session with checkpoints after each dependency boundary.
