# Free Firebase Connection Requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Rain connection request notifications to work on the Firebase Spark/free tier without Cloud Functions or Blaze billing.

**Architecture:** Keep the existing app/runtime/UI contract, but add a Spark-safe `rtdbOnly` backend mode that uses Firebase Realtime Database writes, transactions, security rules, and opportunistic cleanup instead of callable Cloud Functions. Cloud Functions remain in the repo as the stronger future backend, but free-tier releases must not depend on deploying them.

**Tech Stack:** Flutter, Dart, Riverpod, Firebase Auth, Firebase Realtime Database, Firebase RTDB security rules, Melos, existing Rain connection request contract types.

---

## Executive Decision

Rain is sticking to the Firebase free tier for now.

Firebase Cloud Functions cannot be part of the release path because deploying
Functions requires Blaze. The current Functions implementation remains valuable
as a future stronger backend, but it must be disabled for free-tier builds.

The free-tier V1 architecture is:

```text
Rain client
  -> Firebase Auth identity
  -> Firebase Realtime Database rules and transactions
  -> connection request inbox/outbox/pair-lock paths
  -> existing Rain runtime and UI
```

This is not as strong as server-owned guardrails. It is still good enough for a
demo/small-user free-tier release if the app is honest about the security level
and every failure has a visible message.

## Firestore Question

Yes, Cloud Firestore has a free tier, but it is not the best V1 workaround for
this app.

Official Firebase docs currently list Cloud Firestore free quota as one free
database per project, 1 GiB stored data, 50,000 document reads/day, 20,000
writes/day, 20,000 deletes/day, and 10 GiB/month outbound transfer. The same
docs state that TTL deletes, point-in-time recovery, backups, restores, and
clones require billing. That means Firestore can store request documents for
free, but it does not give us free server functions, free secure TTL cleanup, or
free backend-owned quotas.

Decision for this plan:

- Do not add Firestore for connection request V1.
- Use Realtime Database only because Rain already stores users, friends,
  presence, rooms, voice signaling, and current connection request projections
  there.
- Avoid a dual-database architecture until there is a real need.
- Keep Firestore as a future option for analytics/admin dashboards or a cleaner
  request document model if the app later outgrows RTDB rules.

References:

- Firebase Cloud Firestore pricing:
  https://firebase.google.com/docs/firestore/pricing
- Firestore TTL behavior and pricing:
  https://firebase.google.com/docs/firestore/ttl
- Firebase pricing plans:
  https://firebase.google.com/docs/projects/billing/firebase-pricing-plans

## What We Keep

- Existing connection request UI surfaces.
- Existing `ConnectionRequestAdapter` interface.
- Existing `ConnectionRequestPayload`, `ConnectionRequestDecision`,
  `ConnectionRequestQuotaSnapshot`, `ConnectionRequestStatus`, and
  `ConnectionRequestReasonCode` types.
- Existing runtime rules:
  - no auto-connect
  - accepted friends only
  - no request during active call
  - no request during active file transfer
  - every blocked action shows a message
  - app-open/minimized notifications only
- Existing Cloud Functions code remains checked in but is not required by free
  builds.

## What Changes

- Add a backend mode switch:
  - `cloudFunctions`: current stronger backend, requires Blaze deployment.
  - `rtdbOnly`: free-tier backend, no Cloud Functions deployment.
- Free/demo builds use `rtdbOnly`.
- RTDB rules allow narrowly scoped client writes for connection requests.
- Client adapter uses RTDB transactions and multi-location updates.
- Quota, credits, dedupe, and cleanup become best-effort instead of
  server-authoritative.
- Release gate deploys only RTDB rules before building apps.

## Honest Security Level

Free-tier `rtdbOnly` gives:

- good UI behavior
- good casual abuse resistance
- rule-protected ownership checks
- rule-protected friend checks
- pair-lock dedupe friction
- best-effort quotas
- diagnostics

It does not give:

- secret server authority
- trusted admin credit enforcement
- unbypassable rate limits against a modified client
- scheduled cleanup
- guaranteed audit integrity
- closed-app push

The app must not claim stronger protection than it actually has in `rtdbOnly`.

---

## File Structure

### Create

- `packages/protocol_brain/lib/src/connection_request_backend_mode.dart`
  - Defines `ConnectionRequestBackendMode`.
  - Keeps backend mode parsing out of UI/runtime.

- `packages/protocol_brain/lib/src/connection_request_rtdb_adapter.dart`
  - Implements `ConnectionRequestAdapter` with RTDB-only writes and watches.
  - Uses RTDB transactions for pair locks and counters.

- `packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart`
  - Unit/fake tests for adapter behavior without Cloud Functions.

- `packages/protocol_brain/test/connection_request_rtdb_rules_contract_test.dart`
  - Contract tests that security rules contain the expected Spark-safe write
    boundaries.

- `apps/rain/test/connection_request_backend_mode_test.dart`
  - Confirms app wiring selects RTDB-only mode in demo/free builds and still
    allows Cloud Functions mode when explicitly configured.

### Modify

- `packages/protocol_brain/lib/protocol_brain.dart`
  - Export backend mode and RTDB adapter.

- `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
  - Split current callable function behavior into a selectable mode or delegate.
  - Keep existing watchers.

- `packages/protocol_brain/lib/src/connection_request_adapter.dart`
  - Add diagnostics fields for backend mode and authority level.

- `packages/protocol_brain/lib/src/connection_request_contract.dart`
  - Add any missing reason codes required for free-tier mode:
    `bestEffortLimit`, `rtdbConflict`, `repairNotAllowed`.

- `apps/rain/lib/core/config/app_environment.dart`
  - Add `CONNECTION_REQUEST_BACKEND_MODE`.
  - Default demo/free builds to `rtdbOnly`.

- `apps/rain/lib/application/state/runtime_providers.dart`
  - Instantiate the correct adapter for the active backend mode.

- `apps/rain/lib/application/runtime/connection_request_runtime.dart`
  - Add diagnostics for `backendMode`, `serverAuthority`, and
    `securityLevel`.
  - Do not change UI behavior.

- `apps/rain/lib/presentation/screens/settings_screen.dart`
  - Hide or relabel admin credit controls in `rtdbOnly`.
  - Show a concise diagnostic note: `Spark mode uses best-effort request limits.`

- `backend/firebase/database.rules.json`
  - Replace server-owned-only write rules for connection request V1 paths with
    strict Spark-safe client write rules.
  - Keep function-owned/admin paths denied in `rtdbOnly`.

- `backend/firebase/README.md`
  - Document free-tier release path and Cloud Functions optional future path.

- `docs/releases/connection-request-notification-ops.md`
  - Update operations guidance for free-tier mode.

- `.github/workflows/build-artifacts.yml`
  - Ensure demo/free builds pass `CONNECTION_REQUEST_BACKEND_MODE=rtdbOnly`.
  - Do not deploy Cloud Functions.

---

## Data Model For RTDB-Only V1

Use existing path names so the UI/runtime watchers do not need a new surface.

```text
connectionRequests/{receiver}/{requestId}
  v: 1
  requestId: string
  from: sender username
  to: receiver username
  pairKey: "lowerA:lowerB"
  status: pending|seen|accepted|rejected|canceled|expired|failed
  reasonCode: string?
  createdAt: client millis
  updatedAt: client millis
  expiresAt: client millis
  seenAt: client millis?
  respondedAt: client millis?
  senderPresenceAt: millis?
  receiverPresenceAt: millis?

connectionRequestOutboxes/{sender}/{requestId}
  same payload

connectionRequestPairLocks/{pairKey}
  requestId: string
  from: sender username
  to: receiver username
  status: pending|accepted|rejected|canceled|expired|failed
  createdAt: client millis
  updatedAt: client millis
  expiresAt: client millis

connectionNotificationMutes/{receiver}/{sender}
  muted: true
  updatedAt: client millis

connectionRequestUsage/{sender}/{yyyyMMddUtc}
  usedToday: number
  updatedAt: client millis

connectionRequestTargetUsage/{sender}/{receiver}/{yyyyMMddUtc}
  usedToday: number
  updatedAt: client millis
```

Do not use these server-only paths in free-tier V1:

```text
connectionNotificationEntitlements
connectionNotificationReservations
connectionNotificationAudit
connectionNotificationAuditSummary
connectionRequestQuotaSummaries
```

They stay denied to clients until a server backend exists.

---

## Phase 00: Free-Tier Scope Lock

**Purpose:** Prevent accidental release of a Functions-dependent app.

**Files:**

- Modify: `docs/superpowers/plans/2026-05-28-rain-inbound-outbound-connect-notifications.md`
- Modify: `docs/releases/connection-request-notification-ops.md`
- Modify: `backend/firebase/README.md`

- [x] **Step 1: Document the free-tier release decision**

Add a section that states:

```markdown
## Free-Tier Release Decision

Rain connection request notifications ship in `rtdbOnly` mode until the Firebase
project can use a server backend. Cloud Functions remain in the repository but
are not required for free-tier app builds. The release gate deploys Realtime
Database rules only.
```

- [x] **Step 2: Document non-negotiable limitations**

Add:

```markdown
Free-tier V1 does not provide server-authoritative quotas, admin credits,
scheduled cleanup, backend audit integrity, or closed-app push. These require a
server backend such as Firebase Cloud Functions on Blaze or a separate free
external backend.
```

- [x] **Step 3: Commit**

```powershell
git add docs/superpowers/plans/2026-05-28-rain-inbound-outbound-connect-notifications.md docs/releases/connection-request-notification-ops.md backend/firebase/README.md
git commit -m "docs: lock free firebase connection request scope"
```

---

## Phase 01: Backend Mode Contract

**Purpose:** Make backend selection explicit and testable.

**Files:**

- Create: `packages/protocol_brain/lib/src/connection_request_backend_mode.dart`
- Modify: `packages/protocol_brain/lib/protocol_brain.dart`
- Modify: `apps/rain/lib/core/config/app_environment.dart`
- Test: `apps/rain/test/connection_request_backend_mode_test.dart`

- [x] **Step 1: Add backend mode enum**

Create:

```dart
enum ConnectionRequestBackendMode {
  cloudFunctions,
  rtdbOnly;

  static ConnectionRequestBackendMode parse(String value) {
    switch (value.trim()) {
      case 'cloudFunctions':
        return ConnectionRequestBackendMode.cloudFunctions;
      case 'rtdbOnly':
      case '':
        return ConnectionRequestBackendMode.rtdbOnly;
    }
    throw FormatException('Unsupported connection request backend mode: $value');
  }
}
```

- [x] **Step 2: Export the enum**

Add to `packages/protocol_brain/lib/protocol_brain.dart`:

```dart
export 'src/connection_request_backend_mode.dart';
```

- [x] **Step 3: Add app environment define**

Add `CONNECTION_REQUEST_BACKEND_MODE` to `AppEnvironment`.

Default behavior:

```dart
final connectionRequestBackendMode =
    ConnectionRequestBackendMode.parse(
      const String.fromEnvironment(
        'CONNECTION_REQUEST_BACKEND_MODE',
        defaultValue: 'rtdbOnly',
      ),
    );
```

- [x] **Step 4: Add tests**

Test cases:

```dart
test('connection request backend defaults to rtdbOnly', () {
  final environment = AppEnvironment.fromEnvironment();
  expect(
    environment.connectionRequestBackendMode,
    ConnectionRequestBackendMode.rtdbOnly,
  );
});

test('connection request backend parser accepts cloudFunctions', () {
  expect(
    ConnectionRequestBackendMode.parse('cloudFunctions'),
    ConnectionRequestBackendMode.cloudFunctions,
  );
});

test('connection request backend parser rejects unknown mode', () {
  expect(
    () => ConnectionRequestBackendMode.parse('firestore'),
    throwsFormatException,
  );
});
```

- [x] **Step 5: Validate**

```powershell
flutter test --no-test-assets apps/rain/test/connection_request_backend_mode_test.dart
```

Expected: PASS.

- [x] **Step 6: Commit**

```powershell
git add packages/protocol_brain/lib/src/connection_request_backend_mode.dart packages/protocol_brain/lib/protocol_brain.dart apps/rain/lib/core/config/app_environment.dart apps/rain/test/connection_request_backend_mode_test.dart
git commit -m "feat: add connection request backend mode"
```

---

## Phase 02: RTDB-Only Adapter Foundation

**Purpose:** Add a second adapter that satisfies the existing app runtime
without Cloud Functions.

**Files:**

- Create: `packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart`
- Create: `packages/protocol_brain/lib/src/connection_request_rtdb_adapter.dart`
  export shim
- Modify: `packages/protocol_brain/lib/protocol_brain.dart`
- Modify: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Modify: `packages/protocol_brain/lib/src/connection_request_adapter.dart`
- Test: `packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart`

- [x] **Step 1: Create adapter skeleton**

The adapter must implement:

```dart
final class RtdbOnlyConnectionRequestAdapter
    implements ConnectionRequestAdapter {
  RtdbOnlyConnectionRequestAdapter({
    required DatabaseReference root,
    required Future<String> Function() currentUsername,
    required Future<bool> Function(String peerId) isAcceptedFriend,
    required Future<bool> Function(String peerId) isPeerOnline,
    ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
    DateTime Function()? clock,
  });

  @override
  Future<ConnectionRequestDecision> createConnectionRequest(String peerId);

  @override
  Future<ConnectionRequestDecision> cancelConnectionRequest(String requestId);

  @override
  Future<ConnectionRequestDecision> acceptConnectionRequest(String requestId);

  @override
  Future<ConnectionRequestDecision> rejectConnectionRequest(String requestId);

  @override
  Future<ConnectionRequestDecision> markConnectionRequestSeen(String requestId);

  @override
  Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(
    String peerId,
  );

  @override
  Future<ConnectionRequestDecision> unmuteConnectionRequestsFromPeer(
    String peerId,
  );

  @override
  Future<ConnectionRequestQuotaSnapshot> fetchConnectionRequestQuota();

  @override
  Stream<List<ConnectionRequestPayload>> watchIncomingConnectionRequests(
    String username,
  );

  @override
  Stream<List<ConnectionRequestPayload>> watchOutgoingConnectionRequests(
    String username,
  );
}
```

- [x] **Step 2: Implement watchers by reusing parsing behavior**

Move or duplicate the safe parser from `FirebaseSignalingAdapter`:

```dart
Stream<List<ConnectionRequestPayload>> _watchConnectionRequestList({
  required String path,
}) {
  return root.child(path).onValue.map(
    (event) => connectionRequestPayloadsFromSnapshotValue(
      path: path,
      value: event.snapshot.value,
      diagnosticsSink: diagnosticsSink,
    ),
  );
}
```

If the parser is currently private, extract it to
`connection_request_adapter.dart` as:

```dart
List<ConnectionRequestPayload> connectionRequestPayloadsFromSnapshotValue({
  required String path,
  required Object? value,
  ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
});
```

- [x] **Step 3: Add first adapter tests**

Use a fake in-memory RTDB abstraction if available. If not, keep the adapter
logic split so pure helpers can be tested without Firebase.

Required tests:

```dart
test('rtdbOnly adapter starts empty', () async {
  final adapter = buildFakeRtdbOnlyAdapter(username: 'alice');
  expect(
    await adapter.watchIncomingConnectionRequests('alice').first,
    isEmpty,
  );
});

test('rtdbOnly quota summary uses best effort defaults', () async {
  final adapter = buildFakeRtdbOnlyAdapter(username: 'alice');
  final quota = await adapter.fetchConnectionRequestQuota();
  expect(quota.dailyLimit, greaterThan(0));
  expect(quota.disabled, isFalse);
});
```

- [x] **Step 4: Validate**

```powershell
flutter test --no-test-assets packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart
```

Expected: PASS.

- [x] **Step 5: Commit**

```powershell
git add packages/protocol_brain/lib/src/connection_request_rtdb_adapter.dart packages/protocol_brain/lib/protocol_brain.dart packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart
git commit -m "feat: add rtdb connection request adapter"
```

---

## Phase 03: RTDB Create Request Flow

**Purpose:** Create pending request rows without Cloud Functions.

**Files:**

- Modify: `packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart`
- Modify: `packages/protocol_brain/lib/src/connection_request_contract.dart`
- Test: `packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart`

- [x] **Step 1: Add request id helper**

Use a deterministic-enough client id:

```dart
String createConnectionRequestId({
  required String from,
  required String to,
  required int now,
  required String randomSuffix,
}) {
  final pair = connectionRequestPairKey(from, to).replaceAll(':', '_');
  return validateConnectionRequestId('${now}_${pair}_$randomSuffix');
}
```

The random suffix must be alphanumeric and short enough to satisfy existing id
validation.

- [x] **Step 2: Preflight before writes**

`createConnectionRequest(peerId)` must deny before writing when:

- user is unauthenticated
- peer id is invalid
- peer equals self
- peer is not an accepted friend
- peer is offline or presence unknown
- local active call or transfer guard already denied through runtime
- sender local cooldown is active

Return existing `ConnectionRequestDecision` values with user-facing messages.

- [x] **Step 3: Claim pair lock by transaction**

Transaction behavior:

```text
if lock is null -> write pending lock
if lock is pending and not expired -> abort duplicate
if lock is terminal or expired -> replace
otherwise -> abort duplicate/conflict
```

Return:

- `duplicatePendingRequest` if a live pending lock exists.
- `rtdbConflict` if the transaction aborts for an unknown live value.

- [x] **Step 4: Write inbox/outbox mirror**

After lock claim succeeds, write:

```dart
final updates = <String, Object?>{
  'connectionRequests/$to/$requestId': payload.toJson(),
  'connectionRequestOutboxes/$from/$requestId': payload.toJson(),
};
await root.update(updates);
```

If mirror write fails, attempt best-effort lock rollback only when the lock
still points to the same `requestId`.

- [x] **Step 5: Add tests**

Required tests:

```dart
test('create writes receiver inbox and sender outbox', () async {});
test('create duplicate returns existing pending decision', () async {});
test('create denied for offline peer writes no request rows', () async {});
test('create mirror failure attempts matching lock rollback', () async {});
```

- [x] **Step 6: Validate and commit**

```powershell
flutter test --no-test-assets packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart
dart run melos run analyze
dart run melos run test
git add packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart packages/protocol_brain/lib/src/connection_request_contract.dart packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart docs/superpowers/plans/2026-05-28-rain-free-firebase-connection-requests.md
git commit -m "feat: create connection requests without functions"
```

---

## Phase 04: RTDB Terminal Transitions

**Purpose:** Let users cancel, accept, reject, seen, mute, and unmute without
Cloud Functions while preserving race safety.

**Files:**

- Modify: `packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart`
- Test: `packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart`

- [x] **Step 1: Implement request lookup**

Lookup order:

```text
connectionRequestOutboxes/{self}/{requestId}
connectionRequests/{self}/{requestId}
```

Reject missing or malformed rows as `staleRequest`.

- [x] **Step 2: Implement valid actor checks**

Rules in adapter:

- sender can `cancel`
- receiver can `accept`
- receiver can `reject`
- receiver can `mark seen`
- receiver can mute/unmute a sender
- neither side can mutate terminal rows except idempotent no-op return

- [x] **Step 3: Implement terminal mirror update**

For `accepted`, `rejected`, `canceled`, and `expired`, write both mirrors:

```text
connectionRequests/{to}/{requestId}
connectionRequestOutboxes/{from}/{requestId}
connectionRequestPairLocks/{pairKey}
```

Pair lock release:

- If lock `requestId` matches, set terminal status or remove it.
- If lock has another `requestId`, leave it untouched and emit diagnostic.

- [x] **Step 4: Implement seen**

`markConnectionRequestSeen` updates receiver inbox and sender outbox to
`seen` only when current status is `pending`.

- [x] **Step 5: Implement mute/unmute**

Write:

```text
connectionNotificationMutes/{receiver}/{sender}
```

Mute payload:

```json
{
  "muted": true,
  "updatedAt": 1770000000000
}
```

Unmute removes that sender row only.

- [x] **Step 6: Add tests**

Required tests:

```dart
test('sender can cancel and receiver prompt disappears', () async {});
test('receiver can accept and outbox becomes accepted', () async {});
test('receiver can reject and outbox becomes rejected', () async {});
test('cancel versus accept first terminal state wins', () async {});
test('mark seen is idempotent', () async {});
test('mute removes inbound prompts from that sender', () async {});
test('unmute removes only the selected muted sender', () async {});
```

- [x] **Step 7: Validate and commit**

```powershell
flutter test --no-test-assets packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart
dart run melos run analyze
dart run melos run test
git add packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart docs/superpowers/plans/2026-05-28-rain-free-firebase-connection-requests.md
git commit -m "feat: handle rtdb connection request transitions"
```

---

## Phase 05: Spark-Safe RTDB Rules

**Purpose:** Move direct-write denial from server-owned-only to strict
Spark-safe client writes.

**Files:**

- Modify: `backend/firebase/database.rules.json`
- Modify: `backend/firebase/README.md`
- Test: `packages/protocol_brain/test/connection_request_firebase_contract_test.dart`
- Test: `packages/protocol_brain/test/connection_request_rtdb_rules_contract_test.dart`

- [x] **Step 1: Define rule helpers**

Rules must have helper predicates equivalent to:

```json
"isOwner": "auth != null && root.child('users/' + $username + '/uid').val() == auth.uid"
```

Required checks:

- auth owns sender username
- auth owns receiver username for receiver-only actions
- sender and receiver are accepted friends
- sender is not receiver
- request id in path equals payload `requestId`
- request `from`, `to`, and `pairKey` match path and pair lock
- `expiresAt - createdAt` is within allowed TTL range
- initial status is `pending`
- terminal transitions only move from non-terminal to terminal
- terminal rows cannot be overwritten

- [x] **Step 2: Allow sender create as multi-path-compatible writes**

Allow sender to write own outbox row and receiver inbox row only when the new
payload matches the same request id and pair key.

Rules cannot perfectly guarantee multi-location atomicity. The adapter must
repair partial mirrors opportunistically.

- [x] **Step 3: Allow pair lock writes narrowly**

Allow pair lock create when:

- auth owns `from`
- pair key is deterministic for `from` and `to`
- lock status is `pending`
- lock request id matches request payload
- `expiresAt` is valid

Allow pair lock terminal/remove only when:

- request id matches the existing lock
- actor is sender for cancel
- actor is receiver for accept/reject/seen-driven cleanup
- lock is expired by timestamp

- [x] **Step 4: Deny server-only paths**

Keep these denied:

```json
"connectionNotificationEntitlements": { ".read": false, ".write": false },
"connectionNotificationReservations": { ".read": false, ".write": false },
"connectionNotificationAudit": { ".read": false, ".write": false },
"connectionNotificationAuditSummary": { ".read": false, ".write": false },
"connectionRequestQuotaSummaries": { ".read": "auth-owned read only", ".write": false }
```

- [x] **Step 5: Add contract tests**

At minimum, assert rules text contains helper names and denies server-only paths.
If the Firebase emulator rules harness is available, add live rules tests:

```dart
test('non-friend cannot create connection request rows', () async {});
test('wrong sender cannot write outbox row', () async {});
test('sender cannot accept receiver inbox request', () async {});
test('receiver cannot cancel sender outbox request', () async {});
test('terminal request cannot be overwritten', () async {});
test('pair lock request id mismatch is denied', () async {});
```

- [x] **Step 6: Validate and commit**

```powershell
flutter test --no-test-assets packages/protocol_brain/test/connection_request_rtdb_rules_contract_test.dart
flutter test --no-test-assets packages/protocol_brain/test/connection_request_firebase_contract_test.dart
dart run melos run analyze
dart run melos run test
git add backend/firebase/database.rules.json backend/firebase/README.md packages/protocol_brain/test/connection_request_firebase_contract_test.dart packages/protocol_brain/test/connection_request_rtdb_rules_contract_test.dart docs/superpowers/plans/2026-05-28-rain-free-firebase-connection-requests.md
git commit -m "security: allow spark-safe connection request writes"
```

---

## Phase 06: Best-Effort Quotas And Cooldowns

**Purpose:** Add abuse friction without pretending it is server-grade billing.

**Files:**

- Modify: `packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart`
- Modify: `packages/protocol_brain/lib/src/connection_request_contract.dart`
- Modify: `apps/rain/lib/application/runtime/connection_request_messages.dart`
- Modify: `apps/rain/lib/application/runtime/connection_request_runtime.dart`
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `backend/firebase/database.rules.json`
- Modify: `backend/firebase/README.md`
- Test: `packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart`
- Test: `packages/protocol_brain/test/connection_request_rtdb_rules_contract_test.dart`
- Test: `packages/protocol_brain/test/connection_request_firebase_contract_test.dart`
- Test: `packages/protocol_brain/test/connection_request_contract_test.dart`
- Test: `apps/rain/test/connection_request_runtime_test.dart`

- [x] **Step 1: Add mode-specific reason codes**

Add:

```dart
bestEffortLimit,
rtdbConflict,
repairNotAllowed,
```

Message mapping:

```dart
bestEffortLimit => 'Connection requests are cooling down. Try again soon.'
rtdbConflict => 'Another request is already in progress.'
repairNotAllowed => 'This request could not be repaired. Try again.'
```

- [x] **Step 2: Add local cooldown**

Runtime keeps an in-memory cooldown per target:

```text
3 sends per 60 seconds per sender
15 second cooldown after burst denial
```

This protects normal users from accidental spam and duplicate taps.

- [x] **Step 3: Add RTDB daily counters**

Adapter updates:

```text
connectionRequestUsage/{from}/{yyyyMMddUtc}
connectionRequestTargetUsage/{from}/{to}/{yyyyMMddUtc}
```

Default limits:

```text
dailyLimit = 20
perTargetDailyLimit = 3
```

Because clients write these counters, diagnostics must mark:

```json
{
  "serverAuthority": "bestEffort",
  "securityLevel": "sparkRules"
}
```

- [x] **Step 4: Disable admin credits in Spark mode**

Return quota snapshot:

```dart
ConnectionRequestQuotaSnapshot(
  dailyLimit: 20,
  usedToday: usedToday,
  extraCreditsRemaining: 0,
  perTargetRemainingToday: remaining,
  pendingOutboundCount: pendingOutbound,
  pendingInboundCount: pendingInbound,
  disabled: false,
)
```

- [x] **Step 5: Add tests**

Required tests:

```dart
test('best effort daily limit blocks after configured sends', () async {});
test('per target limit blocks without creating rows', () async {});
test('duplicate pending does not increment counters twice', () async {});
test('quota diagnostics say bestEffort and sparkRules', () async {});
```

- [x] **Step 6: Validate and commit**

```powershell
flutter test --no-test-assets packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart
flutter test --no-test-assets packages/protocol_brain/test/connection_request_rtdb_rules_contract_test.dart
flutter test --no-test-assets packages/protocol_brain/test/connection_request_firebase_contract_test.dart
flutter test --no-test-assets packages/protocol_brain/test/connection_request_contract_test.dart
cd apps/rain; flutter test test/connection_request_runtime_test.dart
dart run melos run analyze
dart run melos run test
git add packages/protocol_brain/lib/adapters/connection_request_rtdb_adapter.dart packages/protocol_brain/lib/src/connection_request_contract.dart apps/rain/lib/application/runtime/connection_request_messages.dart apps/rain/lib/application/runtime/connection_request_runtime.dart apps/rain/lib/application/runtime/rain_runtime_controller.dart backend/firebase/database.rules.json backend/firebase/README.md packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart packages/protocol_brain/test/connection_request_rtdb_rules_contract_test.dart packages/protocol_brain/test/connection_request_firebase_contract_test.dart packages/protocol_brain/test/connection_request_contract_test.dart apps/rain/test/connection_request_runtime_test.dart docs/superpowers/plans/2026-05-28-rain-free-firebase-connection-requests.md
git commit -m "feat: add spark best-effort request limits"
```

---

## Phase 07: Opportunistic Cleanup

**Purpose:** Replace scheduled function cleanup with safe client-triggered
cleanup.

**Files:**

- Modify: `packages/protocol_brain/lib/src/connection_request_rtdb_adapter.dart`
- Modify: `apps/rain/lib/application/runtime/connection_request_runtime.dart`
- Test: `packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart`

- [ ] **Step 1: Add cleanup trigger points**

Run cleanup on:

- app startup after identity is known
- opening a chat
- creating a request
- accepting/rejecting/canceling
- receiving an inbox/outbox snapshot

- [ ] **Step 2: Cleanup rules**

Only cleanup when:

- request is expired
- request is terminal and older than retention window
- pair lock points to the same request id
- row is malformed enough to ignore but path owner is current user

Never delete a newer lock.

- [ ] **Step 3: Add retention constants**

```dart
const connectionRequestTtl = Duration(seconds: 45);
const connectionRequestTerminalRetention = Duration(hours: 24);
const connectionRequestMirrorRepairWindow = Duration(minutes: 2);
```

- [ ] **Step 4: Add tests**

Required tests:

```dart
test('expired request becomes expired on snapshot reconciliation', () async {});
test('terminal rows older than retention are removed from own mirrors', () async {});
test('cleanup removes only matching pair lock request id', () async {});
test('cleanup does not remove newer lock', () async {});
```

- [ ] **Step 5: Validate and commit**

```powershell
flutter test --no-test-assets packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart
git add packages/protocol_brain/lib/src/connection_request_rtdb_adapter.dart apps/rain/lib/application/runtime/connection_request_runtime.dart packages/protocol_brain/test/connection_request_rtdb_adapter_test.dart
git commit -m "feat: add opportunistic connection request cleanup"
```

---

## Phase 08: App Wiring And Settings Polish

**Purpose:** Make the app use RTDB-only mode by default and remove UI promises
that require server authority.

**Files:**

- Modify: `apps/rain/lib/application/state/runtime_providers.dart`
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Modify: `.github/workflows/build-artifacts.yml`
- Test: `apps/rain/test/connection_request_backend_mode_test.dart`
- Test: `apps/rain/test/settings_screen_test.dart`

- [ ] **Step 1: Wire adapter selection**

Runtime provider behavior:

```dart
switch (environment.connectionRequestBackendMode) {
  case ConnectionRequestBackendMode.cloudFunctions:
    return firebaseSignalingAdapter;
  case ConnectionRequestBackendMode.rtdbOnly:
    return RtdbOnlyConnectionRequestAdapter(...);
}
```

- [ ] **Step 2: Update settings UI**

In `rtdbOnly`:

- hide admin extra credit controls
- hide unlimited entitlement text
- show `Spark mode uses best-effort request limits.`
- keep mute/unmute controls
- keep local notification controls

- [ ] **Step 3: Update cloud build defines**

For demo/free builds, ensure the workflow passes:

```json
{
  "CONNECTION_REQUEST_BACKEND_MODE": "rtdbOnly"
}
```

Production builds may pass:

```json
{
  "CONNECTION_REQUEST_BACKEND_MODE": "cloudFunctions"
}
```

only after Functions deploy is available.

- [ ] **Step 4: Add tests**

Required tests:

```dart
testWidgets('settings shows Spark best-effort note in rtdbOnly mode', (tester) async {});
test('runtime provider selects rtdb adapter in default mode', () async {});
```

- [ ] **Step 5: Validate and commit**

```powershell
flutter test --no-test-assets apps/rain/test/connection_request_backend_mode_test.dart apps/rain/test/settings_screen_test.dart
git add apps/rain/lib/application/state/runtime_providers.dart apps/rain/lib/presentation/screens/settings_screen.dart .github/workflows/build-artifacts.yml apps/rain/test/connection_request_backend_mode_test.dart apps/rain/test/settings_screen_test.dart
git commit -m "feat: wire free-tier connection request backend"
```

---

## Phase 09: Firebase Rules Deploy Gate Without Functions

**Purpose:** Make release possible without Blaze.

**Files:**

- Modify: `backend/firebase/README.md`
- Modify: `docs/releases/connection-request-notification-ops.md`
- Modify: `docs/github-ci-cd.md`

- [ ] **Step 1: Update free-tier release command**

Document:

```powershell
cd backend/firebase
firebase deploy --project rain-8fb4b --only database --non-interactive
```

- [ ] **Step 2: Remove Functions from free release checklist**

Free-tier release order:

```text
1. Run Dart/Melos validation.
2. Run Firebase emulator tests.
3. Deploy RTDB rules.
4. Push dev.
5. Trigger app artifact workflow.
6. Verify APK/Windows artifacts.
```

- [ ] **Step 3: Keep Functions future path documented**

Add:

```markdown
Cloud Functions mode is stronger but blocked until the Firebase project can use
Blaze or until the same server-owned logic is moved to an external free backend
such as Cloudflare Workers.
```

- [ ] **Step 4: Commit**

```powershell
git add backend/firebase/README.md docs/releases/connection-request-notification-ops.md docs/github-ci-cd.md
git commit -m "docs: document free-tier release gate"
```

---

## Phase 10: Full Validation Gate

**Purpose:** Prove the free-tier implementation works before building apps.

**Commands:**

```powershell
dart pub get
dart run melos run analyze
dart run melos run test
.\scripts\ci_run_firebase_emulators.ps1
```

**Must pass:**

- protocol contract tests
- RTDB adapter tests
- RTDB rules contract tests
- runtime tests
- widget tests
- settings tests
- emulator integration smoke tests

**Commit:**

```powershell
git add docs/superpowers/plans/2026-05-28-rain-free-firebase-connection-requests.md
git commit -m "test: validate free-tier connection requests"
```

---

## Phase 11: Final Free-Tier Build Gate

**Purpose:** Build app artifacts only after the Spark-safe backend is ready.

**Steps:**

- [ ] Deploy RTDB rules to `rain-8fb4b`.
- [ ] Confirm no Cloud Functions deploy is required.
- [ ] Push `dev`.
- [ ] Trigger the existing `Build Rain Apps` workflow with:
  - `platform=all`
  - `build_profile=demo`
  - `publish_test_release=true`
- [ ] Verify release assets include:
  - `Rain-Demo-Android-v7a.apk`
  - `Rain-Demo-Android-v8-v9.apk`
  - `Rain-Demo-Windows-x64.zip`
- [ ] Confirm generated artifacts use `CONNECTION_REQUEST_BACKEND_MODE=rtdbOnly`.

**Commit:**

```powershell
git add docs/releases/connection-request-notification-ops.md docs/github-ci-cd.md
git commit -m "docs: record free-tier release artifacts"
```

---

## Future Upgrade Path: Cloudflare Worker Instead Of Blaze

If RTDB-only becomes too weak but Blaze is still impossible, move the existing
Cloud Functions logic to Cloudflare Workers Free.

Architecture:

```text
Rain app
  -> Cloudflare Worker HTTPS endpoint
  -> Worker validates request, quotas, credits, dedupe
  -> Worker writes to Firebase RTDB through REST with a server secret
  -> Rain watches RTDB inbox/outbox
```

Benefits:

- keeps Firebase Spark
- restores server-owned guardrails
- preserves current data model
- can reuse much of `backend/firebase/functions/connectionRequests.js`

Risks:

- extra deployment platform
- service-account/REST secret management
- separate logs and rate limiting
- more operational complexity than RTDB-only

Do not implement Worker migration in the free-tier V1. Keep it as a later
reliability/security upgrade.

---

## Self-Review

Spec coverage:

- Free Firebase tier only: covered in Executive Decision and Phases 09-11.
- Avoid paying for Blaze: covered by replacing Functions with RTDB-only mode.
- Firestore question: covered with current free-tier limits and decision.
- Existing app behavior preserved: covered in What We Keep and runtime/UI tasks.
- Every blocked action has a message: covered in Phases 03, 06, and tests.
- No silent security downgrade: covered in Honest Security Level and settings
  diagnostic note.
- Future stronger backend path: covered by Cloud Functions parking and
  Cloudflare Worker upgrade path.

Dependency order:

1. Lock scope.
2. Add mode contract.
3. Add adapter.
4. Add write flows.
5. Add rules.
6. Add best-effort guardrails.
7. Add cleanup.
8. Wire app.
9. Update release path.
10. Validate.
11. Build.

Known production limitation:

RTDB-only cannot enforce server-grade abuse prevention against a modified
client. This is accepted for the free-tier release and must remain visible in
diagnostics and operations docs.

---

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-05-28-rain-free-firebase-connection-requests.md`.

Execution options:

1. **Subagent-Driven (recommended)** - dispatch a fresh worker per phase, review
   between phases, keep commits small.
2. **Inline Execution** - execute phases here using `executing-plans`, with a
   checkpoint after every phase.
