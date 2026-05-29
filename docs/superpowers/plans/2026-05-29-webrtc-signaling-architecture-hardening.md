# WebRTC Signaling Architecture Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the structural reliability, Firebase efficiency, WebRTC lifecycle, file transfer, media interruption, security, and state-management issues found in the architecture audit.

**Architecture:** Keep Rain's current product model: Flutter app, Riverpod runtime, Firebase RTDB for signaling/presence, WebRTC for data/media, and one global voice/video call. The work converts fragile best-effort paths into explicit contracts: terminal call state is durable, call start has one preflight source of truth, Firebase writes are bounded, media failure has recovery states, and UI/runtime state follows the same finite-state decisions.

**Tech Stack:** Flutter, Dart, Riverpod, flutter_webrtc, Firebase RTDB/Auth/Remote Config, Melos, Firebase rules tests, existing Rain runtime/test harness.

---

## Execution Rules

- Work on `dev`.
- Commit after each completed task.
- Do not change `main` directly.
- Do not rewrite the working chat, file transfer, or call UX while fixing runtime reliability.
- Do not run platform release builds until Task 14.
- Every blocked user action must produce a user-facing message and a structured diagnostic event.
- Firebase is signaling only. Audio, video, chat data, and file bytes remain WebRTC.

## File Responsibility Map

### Existing files to modify

- `apps/rain/lib/application/runtime/voice_call_runtime.dart`
  - Owns app-level voice/video call lifecycle, call start, call end, terminal reconciliation, and call diagnostics.

- `apps/rain/lib/application/runtime/runtime_interaction_guard.dart`
  - Owns local action policy for connect, call, file transfer, offline, busy, active-transfer, and presence decisions.

- `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
  - Owns heartbeat, app lifecycle, peer connect/disconnect, network recovery, and top-level runtime orchestration.

- `apps/rain/lib/application/runtime/friend_runtime.dart`
  - Owns friend presence reactions and passive peer listener reconciliation.

- `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
  - Owns Firebase RTDB signaling adapter, call room writes, call locks, inboxes, ICE writes, presence heartbeat, and cleanup.

- `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
  - Owns typed voice/video signaling room, status, ICE, lock, and adapter contract types.

- `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
  - Owns chat/data WebRTC session lifecycle, room signaling, ICE fallback, relay fallback, and session recovery.

- `packages/protocol_brain/lib/src/session_retry_policy.dart`
  - Owns session retry and cached ICE feature flags.

- `packages/peer_core/lib/src/call/call_media_connection.dart`
  - Owns dedicated call RTCPeerConnection, local media capture, offer/answer, ICE candidates, sender parameters, and media state.

- `packages/peer_core/lib/src/default_peer_core.dart`
  - Owns data-channel PeerCore. Must stop acting as a second media stack and must gain generic send backpressure.

- `packages/peer_core/lib/src/models.dart`
  - Owns PeerConfig and shared peer/media model types.

- `packages/rain_core/lib/file_transfer/file_transfer_protocol.dart`
  - Owns file-transfer size/chunk constants and frame contracts.

- `apps/rain/lib/application/runtime/file_transfer_runtime.dart`
  - Owns file-transfer send/receive flow and DataChannel backpressure.

- `backend/firebase/database.rules.json`
  - Owns RTDB access control and must enforce role-specific signaling writes.

### New files to create

- `apps/rain/lib/application/runtime/call_start_preflight.dart`
  - Typed preflight result used by UI/runtime/adapters before any call state, media capture, or Firebase lock claim.

- `apps/rain/lib/application/runtime/call_terminal_write_policy.dart`
  - Bounded retry and durable terminal write policy for user hangup, failure cleanup, and system terminal transitions.

- `apps/rain/lib/application/runtime/call_media_recovery_policy.dart`
  - Timeouts and retry decisions for `disconnected`, `failed`, network switch, ICE restart, and media reconnect.

- `packages/protocol_brain/lib/src/ice_candidate_batcher.dart`
  - Small batching helper for Firebase ICE candidate writes.

- `packages/protocol_brain/lib/src/signaling_cost_budget.dart`
  - Constants for max ICE candidates, max candidate batch size, heartbeat budget labels, and diagnostic counters.

- `packages/protocol_brain/lib/src/voice_call_cleanup_janitor.dart`
  - Cleanup policy for expired, terminal, corrupt, and missing call rooms/locks/inboxes.

- `packages/peer_core/lib/src/data_channel_backpressure.dart`
  - Shared helper for waiting on RTCDataChannel `bufferedAmount` before sending generic chunks.

- `packages/peer_core/lib/src/call/media_interruption.dart`
  - Typed device/audio/camera interruption events.

- `docs/security/signaling-security-model.md`
  - Documents what WebRTC encrypts, what Firebase exposes, current limits, and future identity verification.

---

## Phase 00: Baseline Lock And Failing Tests

**Purpose:** Freeze current failure evidence before changing implementation.

**Files:**
- Modify: `apps/rain/test/friend_flow_test.dart`
- Modify: `apps/rain/test/runtime_interaction_guard_test.dart`
- Modify: `packages/protocol_brain/test/voice_signaling_contract_test.dart`
- Modify: `packages/protocol_brain/test/firebase_contract_test.dart`
- Modify: `packages/peer_core/test/call_media_connection_test.dart`

- [ ] **Step 1: Add failing voice hangup propagation tests**

Add tests proving:

```dart
test('local voice hangup writes terminal room before local idle', () async {
  // Alice and Bob have an active voice call.
  // Alice hangs up.
  // Assert Firebase room status becomes ended.
  // Assert Bob runtime observes terminal room and becomes idle.
});

test('voice hangup still reaches remote when session hangup frame fails', () async {
  // Force VoiceCallSession.hangUp to throw.
  // Assert terminal room write still happens.
  // Assert remote closes from Firebase terminal state.
});
```

Run:

```powershell
dart test apps/rain/test/friend_flow_test.dart -n "voice hangup"
```

Expected: fail because terminal room write is best-effort and remote can remain active.

- [ ] **Step 2: Add failing central preflight tests**

In `apps/rain/test/runtime_interaction_guard_test.dart`, add:

```dart
test('canStartCall requires explicit peerOnline decision', () {
  expect(
    () => RuntimeInteractionGuard.canStartCall(
      peerId: 'bob',
      state: RuntimeInteractionState.idle(),
      mediaMode: RuntimeCallMediaMode.voice,
    ),
    throwsA(isA<AssertionError>()),
  );
});
```

Expected: fail because `peerOnline` currently defaults to `true`.

- [ ] **Step 3: Add failing Firebase role-write tests**

In `packages/protocol_brain/test/firebase_contract_test.dart`, add source-string tests that require role-specific room write rules:

```dart
test('rooms rules contain role-specific callerICE and calleeICE write guards', () {
  final rules = File('backend/firebase/database.rules.json').readAsStringSync();
  expect(rules, contains('callerICE'));
  expect(rules, contains('calleeICE'));
  expect(rules, contains('root.child(\\'users/\\' + data.child(\\'userA\\').val()'));
  expect(rules, contains('root.child(\\'users/\\' + data.child(\\'userB\\').val()'));
});
```

Expected: fail until child-level `.write` rules are explicit.

- [ ] **Step 4: Add failing media disconnected recovery tests**

In `packages/peer_core/test/call_media_connection_test.dart`, add:

```dart
test('media disconnected emits reconnecting before failed timeout', () async {
  // Trigger RTCIceConnectionStateDisconnected.
  // Assert CallMediaPhase.reconnecting or equivalent recovery phase is emitted.
});
```

Expected: fail because disconnected is currently ignored.

- [ ] **Step 5: Commit baseline tests**

```powershell
git add apps/rain/test packages/protocol_brain/test packages/peer_core/test
git commit -m "test: lock WebRTC signaling hardening failures"
```

---

## Phase 01: Durable Voice Hangup And Terminal State

**Purpose:** Fix the highest-risk live bug: voice ending on one peer does not reliably close the other peer.

**Files:**
- Create: `apps/rain/lib/application/runtime/call_terminal_write_policy.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
- Test: `apps/rain/test/friend_flow_test.dart`

- [ ] **Step 1: Add terminal write policy**

Create:

```dart
enum CallTerminalWriteOutcome {
  written,
  alreadyTerminal,
  alreadyDeleted,
  failed,
}

final class CallTerminalWriteResult {
  const CallTerminalWriteResult({
    required this.outcome,
    required this.attempts,
    this.error,
  });

  final CallTerminalWriteOutcome outcome;
  final int attempts;
  final Object? error;

  bool get isDurable =>
      outcome == CallTerminalWriteOutcome.written ||
      outcome == CallTerminalWriteOutcome.alreadyTerminal ||
      outcome == CallTerminalWriteOutcome.alreadyDeleted;
}

final class CallTerminalWritePolicy {
  const CallTerminalWritePolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 180),
  });

  final int maxAttempts;
  final Duration initialDelay;

  Duration delayForAttempt(int attempt) =>
      Duration(milliseconds: initialDelay.inMilliseconds * attempt);
}
```

- [ ] **Step 2: Make user hangup terminal write non-best-effort**

In `voice_call_runtime.dart`, change `_writeTerminalRoomBeforeSessionHangup` so it calls `_endVoiceCallInSignaling(... bestEffort: false)` with bounded retry. Keep `session.hangUp` best-effort after Firebase terminal state is durable.

Required behavior:

```dart
// Order:
// 1. write terminal Firebase room
// 2. release matching locks
// 3. dispose media
// 4. send session/data hangup best-effort
// 5. local runtime returns idle or failed based on terminal write result
```

- [ ] **Step 3: Remote terminal state beats all late frames**

Ensure room statuses `ended`, `failed`, `rejected`, `busy`, and `expired` immediately close local media and set runtime idle or failed. Late `hangup`, `markConnected`, `answer`, or ICE frames after terminal room must record diagnostics only.

Required diagnostic names:

- `voice_terminal_write_before_session_hangup`
- `voice_terminal_write_retry`
- `voice_terminal_write_durable`
- `voice_terminal_write_failed`
- `voice_remote_terminal_room_reconciled`
- `voice_late_frame_after_terminal_ignored`

- [ ] **Step 4: Run focused tests**

```powershell
dart test apps/rain/test/friend_flow_test.dart -n "voice hangup"
```

Expected: all new voice hangup propagation tests pass.

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/runtime apps/rain/test/friend_flow_test.dart packages/protocol_brain/lib/src/voice_signaling_contract.dart
git commit -m "fix: make voice hangup terminal state durable"
```

---

## Phase 02: Single Call Start Preflight Source

**Purpose:** Prevent offline, stale, busy, or conflicting calls from entering partial UI/media/Firebase states.

**Files:**
- Create: `apps/rain/lib/application/runtime/call_start_preflight.dart`
- Modify: `apps/rain/lib/application/runtime/runtime_interaction_guard.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/chat_panel.dart`
- Test: `apps/rain/test/runtime_interaction_guard_test.dart`
- Test: `apps/rain/test/friend_flow_test.dart`

- [ ] **Step 1: Add `CallStartPreflightResult`**

```dart
enum CallStartPreflightDecision {
  allowed,
  peerOffline,
  presenceUnknown,
  activeCallExists,
  activeTransferExists,
  localManualDisconnect,
  permissionRequired,
}

final class CallStartPreflightResult {
  const CallStartPreflightResult({
    required this.decision,
    required this.peerId,
    required this.mediaMode,
    this.blockingPeerId,
    this.userMessage,
    this.diagnostics = const <String, Object?>{},
  });

  final CallStartPreflightDecision decision;
  final String peerId;
  final String mediaMode;
  final String? blockingPeerId;
  final String? userMessage;
  final Map<String, Object?> diagnostics;

  bool get allowed => decision == CallStartPreflightDecision.allowed;
}
```

- [ ] **Step 2: Remove `peerOnline = true` default**

Change `RuntimeInteractionGuard.canStartCall` so `peerOnline` is required and nullable:

```dart
static RuntimeInteractionDecision canStartCall({
  required String peerId,
  required RuntimeInteractionState state,
  required RuntimeCallMediaMode mediaMode,
  required bool? peerOnline,
})
```

Rules:

- `peerOnline == true`: continue to call/file conflict checks.
- `peerOnline == false`: deny with `peerOffline`.
- `peerOnline == null`: deny with `presenceUnknown`.

- [ ] **Step 3: Move backend presence fetch before UI/media/Firebase mutation**

In `_startCall`:

1. Fetch backend identity.
2. Build `CallStartPreflightResult`.
3. If denied, keep `VoiceCallState.idle`.
4. Do not capture mic/camera.
5. Do not create call id.
6. Do not claim Firebase locks.

- [ ] **Step 4: Update UI button state**

In `chat_panel.dart`, use the same preflight reason to disable or message voice/video calls. Do not invent separate UI logic.

Required messages:

- `@peer is offline. Keep both apps open, then try again.`
- `Could not confirm @peer is online. Try again.`
- `End the current call before starting another.`
- `Finish the active file transfer before starting a call.`

- [ ] **Step 5: Run focused tests**

```powershell
dart test apps/rain/test/runtime_interaction_guard_test.dart
dart test apps/rain/test/friend_flow_test.dart -n "offline"
```

- [ ] **Step 6: Commit**

```powershell
git add apps/rain/lib/application/runtime apps/rain/lib/presentation/widgets/home/chat_panel.dart apps/rain/test
git commit -m "fix: centralize call start preflight"
```

---

## Phase 03: Firebase Rules Role Hardening

**Purpose:** Stop malicious or corrupted clients from writing the wrong signaling role or hijacking rooms.

**Files:**
- Modify: `backend/firebase/database.rules.json`
- Modify: `packages/protocol_brain/test/firebase_contract_test.dart`
- Modify: `packages/protocol_brain/test/voice_signaling_contract_test.dart`

- [ ] **Step 1: Split `rooms/$roomId` child writes by role**

Rules must enforce:

- Only `userA` can write the offer path if userA is the offer owner.
- Only the expected answer owner can write the answer path.
- Only the caller role can write `callerICE`.
- Only the callee role can write `calleeICE`.
- Neither participant can replace `userA`, `userB`, `createdAt`, or `attemptId` after creation except through a valid new attempt reset.

- [ ] **Step 2: Harden voice call room writes**

Rules must enforce:

- `caller`, `callee`, `pairId`, `callId`, `createdAt`, and `expiresAt` are immutable after create.
- Only caller can create outgoing room.
- Only callee can accept/reject/busy incoming room.
- Either participant can write terminal `ended` only for the matching active call.
- ICE write role must match authenticated user role.

- [ ] **Step 3: Add negative rules tests**

Add tests or contract source assertions for:

```dart
test('caller cannot write callee ICE branch', () async {});
test('callee cannot overwrite caller offer', () async {});
test('participant cannot change caller/callee after room create', () async {});
test('stale user cannot delete newer activeVoiceUsers lock', () async {});
```

- [ ] **Step 4: Run Firebase contract tests**

```powershell
dart test packages/protocol_brain/test/firebase_contract_test.dart
dart test packages/protocol_brain/test/voice_signaling_contract_test.dart
```

- [ ] **Step 5: Commit**

```powershell
git add backend/firebase/database.rules.json packages/protocol_brain/test
git commit -m "security: harden Firebase signaling role rules"
```

---

## Phase 04: ICE Candidate Batching And Cost Budget

**Purpose:** Reduce RTDB read/write pressure during ICE gathering and prevent candidate storms.

**Files:**
- Create: `packages/protocol_brain/lib/src/ice_candidate_batcher.dart`
- Create: `packages/protocol_brain/lib/src/signaling_cost_budget.dart`
- Modify: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Modify: `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Test: `packages/protocol_brain/test/voice_signaling_contract_test.dart`
- Test: `apps/rain/test/friend_flow_test.dart`

- [ ] **Step 1: Add budget constants**

```dart
final class SignalingCostBudget {
  const SignalingCostBudget._();

  static const int maxIceCandidatesPerRole = 80;
  static const int maxIceCandidateBatchSize = 12;
  static const Duration iceCandidateBatchWindow =
      Duration(milliseconds: 150);
}
```

- [ ] **Step 2: Add batcher**

```dart
final class IceCandidateBatch<T> {
  const IceCandidateBatch(this.items);
  final List<T> items;
}

final class IceCandidateBatcher<T> {
  IceCandidateBatcher({
    required this.maxBatchSize,
    required this.flushWindow,
    required this.onFlush,
  });

  final int maxBatchSize;
  final Duration flushWindow;
  final Future<void> Function(IceCandidateBatch<T> batch) onFlush;

  Future<void> add(T candidate) async {
    // Queue candidate, flush immediately at maxBatchSize,
    // otherwise flush after flushWindow.
  }

  Future<void> flush() async {
    // Flush pending candidates and clear timer.
  }
}
```

- [ ] **Step 3: Add batch write path**

In `VoiceSignalingAdapter`, add:

```dart
Future<List<String>> writeIceCandidates({
  required String callId,
  required String username,
  required VoiceCallRole role,
  required List<VoiceSignalingEnvelope> candidates,
  required int createdAt,
});
```

Keep old `writeIceCandidate` as a wrapper that calls the batch method with one item.

- [ ] **Step 4: Avoid room read for every candidate when safe**

On first candidate batch:

- Validate room exists and role matches.
- Cache a short-lived local call write token in adapter memory keyed by `callId:role`.
- For the next batches inside the same active call, avoid `_requireVoiceCall` unless a write fails.

Do not skip Firebase rules. Rules remain the real security boundary.

- [ ] **Step 5: Stop updating room `updatedAt` for every candidate**

Only update candidate child paths. Room `updatedAt` should update on offer, answer, accepted, connected, terminal, and cleanup transitions, not per ICE candidate.

- [ ] **Step 6: Add diagnostics**

Record:

- `ice_candidate_batch_flushed`
- `ice_candidate_batch_dropped_limit`
- `ice_candidate_write_failed`
- `signaling_cost_budget_exceeded`

- [ ] **Step 7: Run tests**

```powershell
dart test packages/protocol_brain/test/voice_signaling_contract_test.dart -n "ICE"
dart test apps/rain/test/friend_flow_test.dart -n "ICE"
```

- [ ] **Step 8: Commit**

```powershell
git add packages/protocol_brain apps/rain/test packages/protocol_brain/test
git commit -m "perf: batch Firebase ICE candidate writes"
```

---

## Phase 05: Call Cleanup Janitor And Stale Lock Repair

**Purpose:** Prevent orphaned rooms, stale busy locks, corrupt inboxes, and database bloat.

**Files:**
- Create: `packages/protocol_brain/lib/src/voice_call_cleanup_janitor.dart`
- Modify: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Modify: `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
- Test: `packages/protocol_brain/test/voice_signaling_contract_test.dart`
- Test: `apps/rain/test/integration_voice_signaling_emulator_test.dart`

- [ ] **Step 1: Add cleanup decision model**

```dart
enum VoiceCallCleanupAction {
  none,
  deleteExpiredRoom,
  deleteTerminalRoom,
  deleteCorruptRoom,
  deleteMatchingPairLock,
  deleteMatchingUserLock,
  deleteCorruptInbox,
}

final class VoiceCallCleanupDecision {
  const VoiceCallCleanupDecision({
    required this.action,
    required this.callId,
    required this.reason,
  });

  final VoiceCallCleanupAction action;
  final String callId;
  final String reason;
}
```

- [ ] **Step 2: Use cleanup before returning busy**

Before reporting busy from `activeVoicePairs` or `activeVoiceUsers`:

1. Read referenced room.
2. If missing, expired, terminal, or corrupt, delete only locks whose `callId` still matches.
3. Retry claim once.
4. If room is live, return real busy.
5. If callee is offline, offline wins over busy.

- [ ] **Step 3: Add opportunistic janitor hooks**

Run cleanup on:

- app start
- app resume
- before outgoing call create
- after incoming corrupt inbox detection
- after call terminal transition

Limit cleanup per run:

```dart
const int maxCallCleanupItemsPerRun = 25;
```

- [ ] **Step 4: Add tests**

Required tests:

```dart
test('missing room lock is removed and claim retries once', () async {});
test('terminal room lock is removed only when callId matches', () async {});
test('newer lock is never deleted by stale cleanup', () async {});
test('corrupt inbox is removed without closing incoming call stream', () async {});
```

- [ ] **Step 5: Commit**

```powershell
git add packages/protocol_brain apps/rain/test packages/protocol_brain/test
git commit -m "fix: repair stale voice call locks"
```

---

## Phase 06: Media Architecture Cleanup

**Purpose:** Remove duplicated media control paths and make dedicated call media the only supported call media stack.

**Files:**
- Modify: `packages/peer_core/lib/src/default_peer_core.dart`
- Modify: `packages/peer_core/lib/src/models.dart`
- Modify: `packages/protocol_brain/lib/src/protocol_brain_impl.dart`
- Test: `packages/peer_core/test/peer_core_test.dart`
- Test: `packages/peer_core/test/call_media_connection_test.dart`

- [ ] **Step 1: Mark legacy `PeerCore` media APIs internal or deprecated**

Legacy APIs must not be used by app call runtime:

- `startLocalAudio`
- `stopLocalAudio`
- `createMediaOffer`
- `applyMediaOffer`
- `applyMediaAnswer`

Add a runtime diagnostic if any app path calls them outside tests.

- [ ] **Step 2: Update protocol brain to expose only dedicated call media**

Keep:

```dart
CallMediaConnection createCallMediaConnection(...);
```

Stop routing app call flows through connected data session media renegotiation.

- [ ] **Step 3: Add regression test**

```dart
test('voice and video calls do not use PeerCore legacy media APIs', () async {
  // Start call through runtime harness.
  // Assert DefaultCallMediaConnection factory was used.
  // Assert PeerCore.createMediaOffer/applyMediaOffer were not called.
});
```

- [ ] **Step 4: Commit**

```powershell
git add packages/peer_core packages/protocol_brain
git commit -m "refactor: isolate calls to dedicated media connection"
```

---

## Phase 07: Call Media Reconnect And ICE Restart

**Purpose:** Make voice/video survive transient network loss and avoid permanent stuck connecting.

**Files:**
- Create: `apps/rain/lib/application/runtime/call_media_recovery_policy.dart`
- Modify: `packages/peer_core/lib/src/call/call_media_connection.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
- Test: `packages/peer_core/test/call_media_connection_test.dart`
- Test: `apps/rain/test/runtime_network_loss_test.dart`

- [ ] **Step 1: Add recovery policy**

```dart
enum CallMediaRecoveryDecision {
  wait,
  iceRestart,
  fullReoffer,
  terminalFailure,
}

final class CallMediaRecoveryPolicy {
  const CallMediaRecoveryPolicy({
    this.disconnectedGrace = const Duration(seconds: 8),
    this.iceRestartTimeout = const Duration(seconds: 12),
    this.fullReofferTimeout = const Duration(seconds: 20),
  });

  final Duration disconnectedGrace;
  final Duration iceRestartTimeout;
  final Duration fullReofferTimeout;
}
```

- [ ] **Step 2: Emit reconnecting on disconnected**

In `CallMediaConnection`, when ICE or peer connection becomes disconnected:

- Emit `CallMediaPhase.reconnecting`.
- Start recovery timer.
- Do not mark call failed immediately.

- [ ] **Step 3: Add ICE restart signaling**

Add typed call frame or room fields for media restart:

- `restartOffer`
- `restartAnswer`
- `restartEpoch`

Only deterministic offer owner creates restart offers.

- [ ] **Step 4: Add timeout terminal cleanup**

If media cannot reconnect:

- Write terminal room status `failed`.
- Release locks.
- Stop media.
- Show `Call could not reconnect. Try again.`

- [ ] **Step 5: Run tests**

```powershell
dart test packages/peer_core/test/call_media_connection_test.dart -n "reconnect"
dart test apps/rain/test/runtime_network_loss_test.dart
```

- [ ] **Step 6: Commit**

```powershell
git add apps/rain/lib/application/runtime packages/peer_core packages/protocol_brain apps/rain/test packages/peer_core/test
git commit -m "fix: add call media reconnect policy"
```

---

## Phase 08: TURN Availability And NAT Failure Clarity

**Purpose:** Stop hiding TURN failure behind generic call failures.

**Files:**
- Modify: `apps/rain/lib/infrastructure/services/turn_credential_service.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `packages/peer_core/lib/src/models.dart`
- Test: `apps/rain/test/friend_flow_test.dart`

- [ ] **Step 1: Add TURN readiness result**

```dart
enum TurnReadiness {
  available,
  unavailableBrokerFailed,
  unavailableNoRelayServer,
  notRequiredForCurrentPolicy,
}

final class TurnReadinessResult {
  const TurnReadinessResult({
    required this.readiness,
    required this.hasRelayServer,
    this.error,
  });

  final TurnReadiness readiness;
  final bool hasRelayServer;
  final Object? error;
}
```

- [ ] **Step 2: Gate calls when relay policy requires TURN**

If ICE policy is relay-only or runtime determines direct route failed and relay fallback is required:

- Do not continue with a fake normal call.
- Show: `Relay connection is unavailable. Check TURN configuration.`
- Record `turn_unavailable_call_blocked`.

- [ ] **Step 3: Preserve direct attempts when allowed**

If policy is `all` and STUN/direct is allowed, do not block just because broker failed. Record diagnostic:

- `turn_broker_failed_direct_allowed`

- [ ] **Step 4: Commit**

```powershell
git add apps/rain/lib/infrastructure/services apps/rain/lib/application/runtime packages/peer_core apps/rain/test
git commit -m "fix: surface TURN availability for calls"
```

---

## Phase 09: Presence And App-Close Reliability

**Purpose:** Make online/offline state fast, explicit, and consistent with connect/request/call behavior.

**Files:**
- Modify: `apps/rain/lib/application/runtime/rain_runtime_controller.dart`
- Modify: `apps/rain/lib/application/runtime/friend_runtime.dart`
- Modify: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Modify: `backend/firebase/database.rules.json`
- Test: `apps/rain/test/runtime_network_loss_test.dart`
- Test: `apps/rain/test/friend_flow_test.dart`

- [ ] **Step 1: Await and catch heartbeat errors**

Replace fire-and-forget heartbeat timer body with:

```dart
_heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
  unawaited(_sendHeartbeatSafely());
});

Future<void> _sendHeartbeatSafely() async {
  try {
    await adapter.sendHeartbeat(selfIdentity.username);
    _recordRuntimeEvent(category: 'presence', name: 'heartbeat_sent');
  } catch (error, stackTrace) {
    _recordRuntimeError(
      category: 'presence',
      name: 'heartbeat_failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
```

- [ ] **Step 2: Make lifecycle policy explicit**

Product rule:

- foreground: online
- background: best-effort, may become stale
- closed/killed: offline

On `paused`, immediately write `online: false` if the product does not support background calls. Do not wait 30 seconds.

- [ ] **Step 3: Session-owned presence**

Presence JSON must include:

- `sessionId`
- `platform`
- `state`
- `lastHeartbeat`
- `lastSeen`
- `updatedAt`

Ignore old-session heartbeats when newer `sessionId` exists.

- [ ] **Step 4: Presence expiry terminates peer UI**

When heartbeat age exceeds UI freshness:

- mark friend offline
- stop recovering state
- terminate WebRTC session UI
- allow offline request notification
- block calls

- [ ] **Step 5: Commit**

```powershell
git add apps/rain/lib/application/runtime packages/protocol_brain/lib/adapters/firebase_adapter.dart backend/firebase/database.rules.json apps/rain/test
git commit -m "fix: harden presence and app close semantics"
```

---

## Phase 10: Generic DataChannel Backpressure

**Purpose:** Prevent RTCDataChannel memory pressure outside the file-transfer path.

**Files:**
- Create: `packages/peer_core/lib/src/data_channel_backpressure.dart`
- Modify: `packages/peer_core/lib/src/default_peer_core.dart`
- Test: `packages/peer_core/test/peer_core_test.dart`

- [ ] **Step 1: Add backpressure helper**

```dart
final class DataChannelBackpressure {
  const DataChannelBackpressure({
    this.highWatermarkBytes = 1024 * 1024,
    this.lowWatermarkBytes = 256 * 1024,
    this.pollInterval = const Duration(milliseconds: 20),
    this.timeout = const Duration(seconds: 10),
  });

  final int highWatermarkBytes;
  final int lowWatermarkBytes;
  final Duration pollInterval;
  final Duration timeout;

  Future<void> waitForDrain(RTCDataChannel channel) async {
    // Poll bufferedAmount until below lowWatermarkBytes.
    // Throw TimeoutException if timeout expires.
  }
}
```

- [ ] **Step 2: Make chunk sends async**

Change `PeerCore.send` and `_sendChunkFrames` so large messages send one chunk at a time and wait when `bufferedAmount` exceeds high watermark.

- [ ] **Step 3: Keep file transfer path unchanged**

File transfer already has its own high/low watermark. Do not duplicate file logic into PeerCore.

- [ ] **Step 4: Commit**

```powershell
git add packages/peer_core
git commit -m "fix: add generic data channel backpressure"
```

---

## Phase 11: Media Interruption Event Model

**Purpose:** Handle real device events instead of leaving call state confused.

**Files:**
- Create: `packages/peer_core/lib/src/call/media_interruption.dart`
- Modify: `packages/peer_core/lib/src/call/call_media_connection.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/presentation/widgets/home/call_suite/*` if call suite files exist
- Test: `packages/peer_core/test/call_media_connection_test.dart`
- Test: `apps/rain/test/friend_flow_test.dart`

- [ ] **Step 1: Add interruption types**

```dart
enum MediaInterruptionType {
  audioFocusLost,
  audioFocusRestored,
  routeChanged,
  microphonePermissionRevoked,
  cameraPermissionRevoked,
  cameraDisconnected,
  appPaused,
  appResumed,
}

final class MediaInterruptionEvent {
  const MediaInterruptionEvent({
    required this.type,
    required this.occurredAt,
    this.detail,
  });

  final MediaInterruptionType type;
  final DateTime occurredAt;
  final String? detail;
}
```

- [ ] **Step 2: Map interruptions to call state**

Rules:

- microphone revoked: mute local mic, show permission message, keep call alive if possible.
- camera revoked/disconnected: disable local video, keep audio alive.
- audio route changed: refresh route capability and update controls.
- app paused: if background calls unsupported, write terminal state and close call.
- app resumed: refresh devices and presence.

- [ ] **Step 3: Commit**

```powershell
git add packages/peer_core apps/rain/lib/application/runtime apps/rain/test packages/peer_core/test
git commit -m "feat: add media interruption handling"
```

---

## Phase 12: Signaling Security Upgrade

**Purpose:** Reduce signaling tampering risk and document the remaining security model honestly.

**Files:**
- Modify: `packages/protocol_brain/lib/adapters/signaling_cipher.dart`
- Modify: `apps/rain/lib/core/config/app_environment.dart`
- Modify: `scripts/build_release.ps1`
- Create: `docs/security/signaling-security-model.md`
- Test: `packages/protocol_brain/test/signaling_cipher_test.dart`
- Test: `packages/protocol_brain/test/release_contract_test.dart`

- [ ] **Step 1: Remove demo-key fallback from production paths**

Production constructors must require explicit signaling key material. Demo fallback may exist only under demo/test environment.

Required release behavior:

- stable release with demo key: fail build
- stable release with missing key: fail build
- demo build with demo key: allowed and labeled as demo

- [ ] **Step 2: Bind encryption context to caller/callee**

Derive signaling keys using:

- room id
- purpose
- caller id
- callee id
- call id or attempt id

This does not create full identity verification, but it prevents cross-room envelope replay.

- [ ] **Step 3: Add security doc**

Document:

- WebRTC media encryption: DTLS-SRTP
- Firebase metadata exposure: usernames, room ids, timestamps, status, ICE structure
- Current signaling encryption limits
- What Firebase rules protect
- What malicious authenticated clients can still attempt
- Future target: per-user identity keys and SAS/fingerprint verification

- [ ] **Step 4: Commit**

```powershell
git add packages/protocol_brain apps/rain/lib/core/config scripts/build_release.ps1 docs/security
git commit -m "security: strengthen signaling encryption boundaries"
```

---

## Phase 13: Runtime Diagnostics And Cost Budget Export

**Purpose:** Make failures explainable without causing lag or high disk I/O.

**Files:**
- Modify: `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Test: `apps/rain/test`

- [ ] **Step 1: Add per-call diagnostic summary**

Each call export must include:

- `callId`
- `peerId`
- `mediaMode`
- `caller`
- `callee`
- `roomStatusTimeline`
- `iceCandidateWriteCount`
- `iceCandidateReadCount`
- `turnReadiness`
- `relayFallbackAttempted`
- `terminalWriteOutcome`
- `cleanupOutcome`
- `presenceAgeAtStartMs`
- `mediaFailureReason`

- [ ] **Step 2: Add RTDB cost counters**

Track approximate per-session:

- signaling reads
- signaling writes
- presence writes
- ICE candidate writes
- cleanup writes

Do not write each counter update to disk immediately. Keep buffered diagnostics.

- [ ] **Step 3: Add failure taxonomy**

Use stable codes:

- `presence_offline`
- `presence_unknown`
- `turn_unavailable`
- `ice_failed`
- `media_timeout`
- `terminal_write_failed`
- `stale_lock_repaired`
- `real_busy_lock`
- `firebase_permission_denied`
- `rules_rejected_write`

- [ ] **Step 4: Commit**

```powershell
git add apps/rain/lib/infrastructure/services apps/rain/lib/application/runtime packages/protocol_brain apps/rain/test
git commit -m "diag: add call reliability and cost summaries"
```

---

## Phase 14: Full Validation And Release Gate

**Purpose:** Verify the architecture hardening without hiding failures behind release builds.

**Files:**
- Modify only if needed: `.github/workflows/*`
- No product code unless tests reveal a defect.

- [ ] **Step 1: Fetch dependencies**

```powershell
dart pub get
```

Expected: success.

- [ ] **Step 2: Run focused runtime tests**

```powershell
dart test apps/rain/test/runtime_interaction_guard_test.dart
dart test apps/rain/test/runtime_network_loss_test.dart
dart test apps/rain/test/friend_flow_test.dart -n "voice"
dart test apps/rain/test/friend_flow_test.dart -n "video"
```

Expected: success.

- [ ] **Step 3: Run protocol and peer tests**

```powershell
dart test packages/protocol_brain/test/voice_signaling_contract_test.dart
dart test packages/protocol_brain/test/firebase_contract_test.dart
dart test packages/peer_core/test/call_media_connection_test.dart
dart test packages/peer_core/test/peer_core_test.dart
```

Expected: success.

- [ ] **Step 4: Run repo validation**

```powershell
dart run melos run analyze
dart run melos run test
```

Expected: success.

- [ ] **Step 5: Deploy Firebase rules only after tests pass**

```powershell
firebase deploy --only database
```

Expected: deploy success against the intended Firebase project.

- [ ] **Step 6: Push `dev`**

```powershell
git status --short
git push origin dev
```

Expected: clean or only intentional untracked local files remain.

- [ ] **Step 7: Trigger cloud release workflow**

Use the existing release workflow from GitHub Actions after `dev` is pushed. Verify produced artifacts are from the latest commit:

- Android ARMv7 APK
- Android ARM64 APK
- Windows build
- release notes include commit SHA, version, channel, and build profile

- [ ] **Step 8: Commit workflow fixes if needed**

Only if validation exposes workflow issues:

```powershell
git add .github/workflows
git commit -m "ci: update release validation for signaling hardening"
git push origin dev
```

---

## Acceptance Checklist

- [ ] Voice hangup on either peer closes the other peer through Firebase terminal room state.
- [ ] Voice/video cannot start unless fresh presence preflight allows it.
- [ ] Offline and presence-unknown calls create no room, inbox, pair lock, user lock, or media capture.
- [ ] Stale busy locks are repaired once before showing busy.
- [ ] Real busy locks still show peer-specific busy.
- [ ] ICE candidate writes are batched and capped.
- [ ] TURN broker failure is visible in diagnostics and user messaging when it affects calls.
- [ ] Media disconnected states attempt recovery before terminal failure.
- [ ] Closed/killed app semantics are clear: closed app is offline.
- [ ] Generic RTCDataChannel chunking has backpressure.
- [ ] Firebase rules enforce role-specific signaling writes.
- [ ] Diagnostics explain call start, media setup, busy, timeout, cleanup, and terminal write outcomes.
- [ ] No release build uses demo signaling encryption key.

## Deferred Work

- Closed-app ringing through FCM or a foreground service.
- Full per-user identity key system with user-verifiable safety numbers.
- Production backend cleanup through Cloud Functions, if the project moves off Spark.
- True multi-call support. Current policy remains one global active voice/video call.

