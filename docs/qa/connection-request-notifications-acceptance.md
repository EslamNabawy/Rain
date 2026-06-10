# Connection Request Notifications Acceptance Lock

Status: Phase 00 acceptance baseline

Last updated: 2026-05-28

## Scope

Connection request notifications are a manual data-peer connection feature. They
let one accepted friend ask another accepted friend to open the normal Rain
peer lane.

V1 includes:

- App-open and app-minimized in-app prompts.
- Optional local OS notifications where the platform implementation is proven.
- Sender outbound pending, cancel, accepted, rejected, expired, and failed
  states.
- Receiver inbound prompt, connect, ignore/reject, mute, and unmute controls.
- Firebase-owned quotas, extra credits, receiver protections, pair dedupe, and
  audit diagnostics.
- Server-owned creation and lifecycle transitions through Cloud Functions.

V1 does not include:

- Closed-app push notifications.
- Firebase Cloud Messaging token storage.
- Group connection requests.
- Connection request history.
- Automatic connection acceptance.
- Friend request replacement.
- Voice/video call invite replacement.
- Client-owned quota, credits, or direct request creation.

## Existing Path Boundaries

Do not reuse these paths:

- `friendRequests/<to>/<from>` remains only for friendship requests.
- `voiceCallInboxes/<username>/<callId>` remains only for voice/video call
  signaling pointers.
- `voiceCalls/<callId>` remains only for call signaling state.

Connection request notifications must use dedicated `connectionRequest*` and
`connectionNotification*` paths, owned by the new backend contract.

## Product Rules

- Only accepted friends can use this feature.
- Blocked, muted, unaccepted, offline, stale-presence, inbox-full, and
  quota-denied paths create no receiver notification.
- Receiver protection runs before sender quota spend.
- One pending request may exist per sender/receiver pair.
- Pressing Disconnect still means no reconnect until explicit user action.
- Inbound prompts never auto-connect.
- Every denied action shows a user-facing message.
- Privacy-sensitive denials use neutral copy.
- Diagnostics keep exact internal reason codes.

## Threat Model

The implementation must defend against:

- Client replay of old request ids.
- Direct Realtime Database writes that bypass Cloud Functions.
- Duplicate taps and retry storms.
- Multiple devices signed into the same account.
- Sender cancel racing receiver accept.
- Receiver accept racing request expiry.
- Stale pair locks blocking future requests.
- Partial backend writes after quota reservation.
- Entitlement abuse or permanent untracked admin overrides.
- Receiver harassment through repeated requests.
- Firebase cost spikes from request spam.
- Notification permission denial or platform notification failure.
- Relationship changes while a request is pending.
- App restart during an inbound or outbound pending request.

## Phase Owners

| Area | Owner Role | Responsibility |
| --- | --- | --- |
| Backend contract | Protocol engineer | Shared types, status machine, reason codes, message mapper |
| Firebase rules | Backend/security engineer | Read/write boundaries and direct-write denial tests |
| Cloud Functions | Backend engineer | Request lifecycle, quota, dedupe, cleanup, audit |
| Protocol adapter | Flutter/platform engineer | Function calls and RTDB watchers behind one adapter |
| Runtime | Flutter runtime engineer | Riverpod state, manual disconnect policy, session handoff |
| UI/UX | Product designer and Flutter UI engineer | Tray, chip, badge, settings, accessibility, responsive layout |
| QA | Test owner | Unit, rules, function, runtime, widget, and scenario tests |
| Release/Ops | Release owner | Staging deploy, production deploy, kill switch, release notes |

## Production Success Metrics

Track these after rollout:

- Created request count.
- Accepted request ratio.
- Rejected, canceled, and expired ratios.
- Duplicate suppression ratio.
- Denied reason distribution.
- Per-target-limit denial count.
- Receiver mute denial count.
- Stale cleanup count.
- Notification permission denied count.
- Notification fallback count.
- Request function error rate.
- Request function latency.
- Stale pair-lock cleanup count.

## Acceptance Criteria

- A direct client write cannot create request, quota, entitlement, pair lock, or
  audit rows.
- A denied backend decision returns reason code, safe message, retry metadata
  when relevant, and diagnostics detail.
- A request denied before creation consumes no quota and notifies no receiver.
- Duplicate pending sender/receiver attempts create one request row.
- Receiver mute/block/offline/stale/inbox-full checks run before quota spend.
- App restart restores pending inbox/outbox state.
- Manual disconnect is not cleared by inbound request arrival.
- Explicit inbound Connect clears manual disconnect only for that peer.
- Every visible disabled action has tooltip, semantic label, inline reason, or
  tap feedback.
- Closed-app push cannot be implemented in v1 without a separate approved spec.
