# Rain Call Signaling, ARMv7 Stability, And Premium Call UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Rain calls reliable from PC to phone and phone to PC, eliminate false `peer busy` states, stabilize ARMv7, and replace the current voice/video call UI with a professional adaptive call experience.

**Architecture:** Fix lower-level correctness first: Firebase call clocks, stale lock cleanup, runtime retry semantics, and diagnostic evidence. After the call state machine is trustworthy, rebuild the call surfaces around one shared control model, one shared layout contract, and hardware-aware controls. Keep chat, files, friendships, login, and the working WebRTC protocol untouched unless a phase explicitly lists a file.

**Tech Stack:** Flutter, Dart, Riverpod, Melos, Firebase Realtime Database, `flutter_webrtc`, `audioplayers`, existing Rain runtime diagnostics, existing `peer_core` media abstractions, existing `protocol_brain` voice signaling.

---

## Current Evidence

The supplied diagnostics file `C:/Users/eslam/OneDrive/Desktop/rain-diagnostics-2026-05-26T043505-436477Z.json` shows:

- Windows caller/callee path reached direct WebRTC connectivity: `direct host->host udp`.
- A video call became active and had both local and remote video streams.
- The last recorded signaling failure is:

```text
Bad state: Voice call signaling ignored: failed to send hangup: FormatException: Voice call timestamps are invalid.
```

Relevant stack:

```text
VoiceCallRuntime._createVoiceCallSession.<anonymous closure>
VoiceCallSession._send
VoiceCallSession.hangUp
VoiceCallRuntime._endVoiceCallForPeer
VoiceCallRuntime.hangUpVoiceCall
```

This points to a concrete backend/runtime problem: terminal call cleanup can fail because Firebase room validation rejects invalid timestamp ordering. When cleanup fails, `activeVoiceUsers/{username}` or `activeVoicePairs/{pairId}` can remain and the next call can report false `peer busy`.

UI direction uses proven patterns from mature call apps:

- Signal: switch camera, microphone, and call view controls: https://support.signal.org/hc/en-us/articles/5369785769370-Calling-options-Switch-camera-microphone-or-view
- Zoom: stable meeting controls toolbar and visible participant controls: https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0062674
- Google Meet: consistent call control layout across platforms: https://support.google.com/meet/answer/15967960

---

## File Structure

### New Files

- `packages/protocol_brain/lib/src/voice_call_clock.dart`
  - Central monotonic timestamp helper for voice signaling writes.
  - Prevents `updatedAt < createdAt` when device clocks differ.

- `apps/rain/lib/application/runtime/call_retry_policy.dart`
  - Converts signaling/runtime failures into retry cleanup behavior and user messages.
  - Keeps retry policy out of widgets.

- `apps/rain/lib/presentation/widgets/calls/rain_call_layout_contract.dart`
  - Defines call layout modes, safe-area rules, video role rules, and control placement rules.
  - Shared by popup, fullscreen, minimized, voice-only, and video calls.

- `apps/rain/lib/presentation/widgets/calls/rain_call_stage.dart`
  - Owns video/voice stage composition.
  - Remote video is primary by default; local preview is secondary; tap preview swaps.

- `apps/rain/lib/presentation/widgets/calls/rain_call_status_strip.dart`
  - Top peer/status/duration/quality strip.
  - Used in popup and fullscreen layouts.

- `apps/rain/lib/presentation/widgets/calls/rain_call_workspace.dart`
  - Fullscreen desktop/mobile workspace.
  - Desktop side panel is optional and collapsible; mobile uses compact call-only mode.

- `apps/rain/test/call_retry_policy_test.dart`
  - Unit tests for false busy, cleanup retry, stale room, and user-facing messages.

- `apps/rain/test/rain_call_stage_test.dart`
  - Widget tests for remote-primary/local-preview layout and swap behavior.

- `apps/rain/test/rain_call_workspace_test.dart`
  - Widget tests for safe-area, fullscreen controls, desktop panel collapse, and mobile layout.

### Modified Files

- `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
  - Add timestamp normalization/repair entry points.
  - Keep strict validation for new clean writes.
  - Allow controlled parsing of corrupt existing rooms for terminal cleanup only.

- `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
  - Use monotonic timestamps for accept/connect/end/mute/camera/offer/answer/ICE.
  - Make user lock claims transactional.
  - Reclaim stale or corrupt terminal rooms safely.

- `packages/protocol_brain/lib/src/testing/fake_voice_signaling_adapter.dart`
  - Mirror Firebase behavior for unit and runtime tests.

- `packages/protocol_brain/test/voice_signaling_contract_test.dart`
  - Add timestamp skew and corrupt room cleanup tests.

- `packages/protocol_brain/test/firebase_contract_test.dart`
  - Lock Firebase rules/functions expectations for user locks and cleanup paths.

- `apps/rain/test/utils/firebase_emulator_signaling_adapter.dart`
  - Mirror production Firebase adapter behavior for emulator tests.

- `apps/rain/lib/application/runtime/voice_call_runtime.dart`
  - Route call failures through cleanup-first retry policy.
  - Stop treating stale/corrupt lock cleanup as a normal call failure.
  - Ensure terminal cleanup is idempotent.

- `apps/rain/lib/application/runtime/runtime_interaction_guard.dart`
  - Add typed call decisions for stale cleanup, false busy, active call, active file transfer, and offline peer.

- `apps/rain/lib/application/runtime/voice_call_state.dart`
  - Add state fields needed for improved UX: `cleanupInProgress`, `retryableAfterCleanup`, `remoteDisplayState`, and stable `callStartedAt`.

- `apps/rain/lib/application/runtime/voice_call_diagnostics.dart`
  - Record lock claim result, stale lock cleanup result, room timestamp repair, route, media mode, and peer direction.

- `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
  - Keep one source of truth for icons, labels, disabled states, and actions.

- `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
  - Replace loose overlay composition with the new stage/status/control contract.

- `apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart`
  - Only appears when popup/fullscreen is minimized.
  - Hidden when expanded popup or fullscreen workspace is visible.

- `apps/rain/lib/presentation/screens/home_screen.dart`
  - Wire call surface mode transitions and top-level call errors.

- `apps/rain/lib/presentation/performance/rain_performance.dart`
  - Ensure ARMv7 uses low-power call visuals and static expensive effects.

- `apps/rain/test/runtime_interaction_guard_test.dart`
  - Add false busy, cleanup, and global call/file conflict tests.

- `apps/rain/test/friend_flow_test.dart`
  - Add PC-phone style runtime scenarios using fake adapters.

- `apps/rain/test/integration_voice_signaling_emulator_test.dart`
  - Add emulator coverage for call locks and cleanup where possible.

- `apps/rain/test/rain_call_manager_bar_test.dart`
  - Add no-duplication and minimized-only behavior tests.

- `apps/rain/test/rain_performance_test.dart`
  - Add ARMv7 low-power call-surface tests.

- `backend/firebase/database.rules.json`
  - Keep user/pair lock rules aligned with transactional lock claims.

- `backend/firebase/functions/index.js`
  - Clean expired/corrupt terminal calls and matching active user/pair locks.

---

## Global Acceptance Rules

- PC to phone voice call does not report `peer busy` unless the phone is truly in another active/ringing call.
- Phone to PC call succeeds first try after both peers are online and accepted friends.
- A finished, rejected, timed out, or failed call removes matching pair and user locks.
- A corrupt old call room can be cleaned without app restart.
- ARMv7 keeps the same behavior but uses low-power visuals and does not freeze during call UI, scroll, or refresh.
- Voice/video call UI has one control language across mobile and desktop.
- Remote video is primary by default; local preview is small; tapping preview swaps.
- Fullscreen is a real call workspace, not raw stretched camera footage.
- No duplicated top call bar while popup/fullscreen is open.
- Output/speaker/camera controls only appear when the device actually supports them.
- No phase changes chat message delivery, file transfer protocol, login, friend state, or Firebase auth.

---

## Phase 00: Evidence Lock And Failure Taxonomy

**Why First:** The current failures cross Firebase, runtime, and UI. Lock evidence before changing behavior so later fixes can be proven.

**Execution note:** Implemented as skipped regression tests with explicit failure messages so `dev` remains CI-safe. Later implementation phases must replace each skipped failure body with the real assertion and remove the matching `skip`.

**Files:**
- Modify: `apps/rain/test/call_retry_policy_test.dart`
- Modify: `apps/rain/test/runtime_interaction_guard_test.dart`
- Modify: `apps/rain/test/friend_flow_test.dart`
- Modify: `packages/protocol_brain/test/voice_signaling_contract_test.dart`
- Modify: `packages/protocol_brain/test/firebase_contract_test.dart`

- [x] **Step 1: Create the retry policy test file**

Create `apps/rain/test/call_retry_policy_test.dart` with these first red tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/call_retry_policy.dart';

void main() {
  group('CallRetryPolicy', () {
    test('maps active user lock conflict to peer busy only when lock is live', () {
      final decision = CallRetryPolicy.classifySignalingFailure(
        const CallSignalingFailureSnapshot(
          message: 'Active voice call already exists for user eslam.',
          lockWasReclaimed: false,
          terminalRoomWasCleaned: false,
          corruptRoomWasRepaired: false,
        ),
      );

      expect(decision.kind, CallRetryDecisionKind.peerBusy);
      expect(decision.userMessage, '@eslam is busy in another call.');
    });

    test('maps corrupt terminal room cleanup to retryable cleanup message', () {
      final decision = CallRetryPolicy.classifySignalingFailure(
        const CallSignalingFailureSnapshot(
          message: 'Voice call timestamps are invalid.',
          lockWasReclaimed: true,
          terminalRoomWasCleaned: true,
          corruptRoomWasRepaired: true,
        ),
      );

      expect(decision.kind, CallRetryDecisionKind.cleanedStaleState);
      expect(decision.userMessage, 'Old call state was cleaned. Try again.');
    });
  });
}
```

- [x] **Step 2: Add protocol timestamp regression tests**

In `packages/protocol_brain/test/voice_signaling_contract_test.dart`, add:

```dart
test('normalizes terminal updatedAt when device clock is behind createdAt', () {
  final room = _room(
    status: VoiceCallSignalingStatus.connected,
    caller: 'alice',
    callee: 'bob',
  );

  final endedAt = room.createdAt - 1000;
  final normalized = VoiceCallTimestampClock.nextRoomTimestamp(
    requestedAt: endedAt,
    roomCreatedAt: room.createdAt,
    roomUpdatedAt: room.updatedAt,
  );

  expect(normalized, room.updatedAt + 1);
});

test('parses corrupt room for cleanup without treating it as a valid live room', () {
  final corrupt = <Object?, Object?>{
    'v': VoiceCallRoom.version,
    'pairId': 'alice:bob',
    'caller': 'alice',
    'callee': 'bob',
    'status': VoiceCallSignalingStatus.ended.name,
    'mediaMode': CallMediaMode.audio.name,
    'createdAt': 2000,
    'updatedAt': 1000,
    'expiresAt': 3000,
    'endedAt': 1000,
    'endedBy': 'alice',
  };

  final parsed = VoiceCallRoom.tryParseForCleanup(
    callId: 'call-1',
    json: corrupt,
  );

  expect(parsed, isNotNull);
  expect(parsed!.status, VoiceCallSignalingStatus.ended);
  expect(parsed.updatedAt, greaterThanOrEqualTo(parsed.createdAt));
});
```

- [x] **Step 3: Add runtime false-busy scenario names**

In `apps/rain/test/friend_flow_test.dart`, add failing test names that model the reported behavior:

```dart
test('pc caller can call phone after previous phone ended call without false busy', () async {});
test('phone caller retry succeeds after stale pc outgoing room is cleaned', () async {});
test('hangup cleanup is idempotent when signaling frame send fails', () async {});
```

- [x] **Step 4: Run targeted red tests**

Run:

```powershell
dart run melos exec --scope protocol_brain -- flutter test test/voice_signaling_contract_test.dart
dart run melos exec --scope rain -- flutter test test/call_retry_policy_test.dart test/runtime_interaction_guard_test.dart test/friend_flow_test.dart
```

Expected:

```text
Undefined name 'VoiceCallTimestampClock'
The method 'tryParseForCleanup' is not defined
Target of URI does not exist: call_retry_policy.dart
```

- [x] **Step 5: Commit evidence tests**

```powershell
git add apps/rain/test/call_retry_policy_test.dart apps/rain/test/runtime_interaction_guard_test.dart apps/rain/test/friend_flow_test.dart packages/protocol_brain/test/voice_signaling_contract_test.dart packages/protocol_brain/test/firebase_contract_test.dart
git commit -m "test: lock call false busy and timestamp failures"
```

---

## Phase 01: Voice Call Clock And Corrupt Room Repair

**Why Here:** False `peer busy` cannot be fixed reliably while hangup/end cleanup can fail on timestamp validation.

**Execution note:** The existing public `VoiceCallClock` typedef is used by `VoiceCallSession`, so the timestamp helper is named `VoiceCallTimestampClock` to avoid a breaking API collision.

**Files:**
- Create: `packages/protocol_brain/lib/src/voice_call_clock.dart`
- Modify: `packages/protocol_brain/lib/src/voice_signaling_contract.dart`
- Modify: `packages/protocol_brain/test/voice_signaling_contract_test.dart`

- [x] **Step 1: Add the monotonic clock helper**

Create `packages/protocol_brain/lib/src/voice_call_clock.dart`:

```dart
final class VoiceCallTimestampClock {
  const VoiceCallTimestampClock._();

  static int nextRoomTimestamp({
    required int requestedAt,
    required int roomCreatedAt,
    required int roomUpdatedAt,
  }) {
    final floor = roomUpdatedAt >= roomCreatedAt
        ? roomUpdatedAt
        : roomCreatedAt;
    if (requestedAt > floor) {
      return requestedAt;
    }
    return floor + 1;
  }

  static int nextInitialTimestamp(int requestedAt) {
    if (requestedAt > 0) {
      return requestedAt;
    }
    return 1;
  }

  static int nextExpiry({
    required int createdAt,
    required int requestedExpiresAt,
  }) {
    if (requestedExpiresAt > createdAt) {
      return requestedExpiresAt;
    }
    return createdAt + const Duration(minutes: 15).inMilliseconds;
  }
}
```

- [x] **Step 2: Export/import clock where the protocol package exposes internals**

If `packages/protocol_brain/lib/protocol_brain.dart` exports selected source files, add:

```dart
export 'src/voice_call_clock.dart';
```

If the package uses `src` imports only, import `voice_call_clock.dart` directly in files that need it.

- [x] **Step 3: Add cleanup-safe parser to VoiceCallRoom**

In `packages/protocol_brain/lib/src/voice_signaling_contract.dart`, add a factory next to `VoiceCallRoom.fromJson`:

```dart
factory VoiceCallRoom.forCleanupFromJson({
  required String callId,
  required Map<Object?, Object?> json,
}) {
  final createdAt = _requiredInt(json, 'createdAt');
  final rawUpdatedAt = _requiredInt(json, 'updatedAt');
  final rawExpiresAt = _requiredInt(json, 'expiresAt');
  final updatedAt = VoiceCallTimestampClock.nextRoomTimestamp(
    requestedAt: rawUpdatedAt,
    roomCreatedAt: createdAt,
    roomUpdatedAt: createdAt,
  );
  final expiresAt = VoiceCallTimestampClock.nextExpiry(
    createdAt: createdAt,
    requestedExpiresAt: rawExpiresAt,
  );
  final rawEndedAt = _optionalInt(json, 'endedAt');
  final endedAt = rawEndedAt == null
      ? null
      : VoiceCallTimestampClock.nextRoomTimestamp(
          requestedAt: rawEndedAt,
          roomCreatedAt: createdAt,
          roomUpdatedAt: updatedAt,
        );

  return VoiceCallRoom(
    v: _requiredInt(json, 'v'),
    callId: callId,
    pairId: _requiredString(
      json,
      'pairId',
      max: (_maxUsernameLength * 2) + 1,
    ),
    caller: _requiredString(json, 'caller', max: _maxUsernameLength),
    callee: _requiredString(json, 'callee', max: _maxUsernameLength),
    status: voiceCallSignalingStatusFromName(
      _requiredString(json, 'status', max: 32),
    ),
    mediaMode: _optionalCallMediaMode(json, 'mediaMode'),
    createdAt: createdAt,
    updatedAt: updatedAt,
    expiresAt: expiresAt,
    acceptedAt: _optionalInt(json, 'acceptedAt'),
    connectedAt: _optionalInt(json, 'connectedAt'),
    endedAt: endedAt,
    endedBy: _optionalString(json, 'endedBy', max: _maxUsernameLength),
    reasonCode: _optionalString(
      json,
      'reasonCode',
      max: VoiceCallRoom.maxReasonCodeLength,
    ),
    reason: _optionalString(
      json,
      'reason',
      max: VoiceCallRoom.maxReasonLength,
    ),
    muted: Map<String, bool>.unmodifiable(_optionalBoolMap(json, 'muted')),
    cameraMuted: Map<String, bool>.unmodifiable(
      _optionalBoolMap(json, 'cameraMuted'),
    ),
  );
}

static VoiceCallRoom? tryParseForCleanup({
  required String callId,
  required Map<Object?, Object?> json,
}) {
  try {
    return VoiceCallRoom.fromJson(callId: callId, json: json);
  } on FormatException {
    try {
      final repaired = VoiceCallRoom.forCleanupFromJson(
        callId: callId,
        json: json,
      );
      if (!repaired.status.isTerminal &&
          repaired.expiresAt >
              VoiceCallTimestampClock.nextInitialTimestamp(
                DateTime.now().millisecondsSinceEpoch,
              )) {
        return null;
      }
      return repaired;
    } catch (_) {
      return null;
    }
  }
}
```

Then import:

```dart
import 'voice_call_clock.dart';
```

- [x] **Step 4: Keep normal parser strict**

Do not weaken `VoiceCallRoom.fromJson` or `VoiceCallRoom.validate`. New clean rooms must still throw when:

```dart
updatedAt < createdAt
expiresAt <= createdAt
endedAt < createdAt
```

- [x] **Step 5: Run protocol tests**

```powershell
dart run melos exec --scope protocol_brain -- flutter test test/voice_signaling_contract_test.dart
```

Expected:

```text
All tests passed
```

- [x] **Step 6: Commit**

```powershell
git add packages/protocol_brain/lib/src/voice_call_clock.dart packages/protocol_brain/lib/src/voice_signaling_contract.dart packages/protocol_brain/test/voice_signaling_contract_test.dart
git commit -m "fix: add monotonic voice call clock"
```

---

## Phase 02: Firebase User And Pair Lock Hygiene

**Why Here:** `peer busy` comes from locks. Fix lock claim/release before changing app retry behavior.

**Files:**
- Modify: `packages/protocol_brain/lib/adapters/firebase_adapter.dart`
- Modify: `packages/protocol_brain/lib/src/testing/fake_voice_signaling_adapter.dart`
- Modify: `apps/rain/test/utils/firebase_emulator_signaling_adapter.dart`
- Modify: `packages/protocol_brain/test/voice_signaling_contract_test.dart`
- Modify: `apps/rain/test/integration_voice_signaling_emulator_test.dart`
- Modify: `backend/firebase/database.rules.json`
- Modify: `backend/firebase/functions/index.js`
- Modify: `packages/protocol_brain/test/firebase_contract_test.dart`

- [x] **Step 1: Make user lock claim transactional in Firebase adapter**

Replace blind user lock writes in `packages/protocol_brain/lib/adapters/firebase_adapter.dart`:

```dart
Future<bool> _claimActiveVoiceUserLock({
  required DatabaseReference lockRef,
  required VoiceActiveUserLock lock,
  required int createdAt,
}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final transaction = await lockRef.runTransaction((Object? current) {
    if (current is Map) {
      try {
        final existing = VoiceActiveUserLock.fromJson(
          username: lock.username,
          json: _asObjectMap(current),
        );
        if (existing.expiresAt > createdAt && existing.expiresAt > now) {
          return Transaction.abort();
        }
      } catch (_) {
        return Transaction.abort();
      }
    }
    return Transaction.success(lock.toJson());
  }, applyLocally: false);
  return transaction.committed;
}
```

Update all calls:

```dart
claimed = await _claimActiveVoiceUserLock(
  lockRef: lockRef,
  lock: lock,
  createdAt: createdAt,
);
```

- [x] **Step 2: Normalize all room update timestamps**

In `acceptCall`, `markConnected`, `endCall`, `setMuted`, `setCameraMuted`, `writeVoiceOffer`, `writeVoiceAnswer`, and `writeIceCandidate`, compute:

```dart
final safeUpdatedAt = VoiceCallTimestampClock.nextRoomTimestamp(
  requestedAt: requestedTimestamp,
  roomCreatedAt: room.createdAt,
  roomUpdatedAt: room.updatedAt,
);
```

Use `safeUpdatedAt` for room and inbox `updatedAt`. For terminal operations also use it for `endedAt`.

- [x] **Step 3: Make cleanup tolerate corrupt rooms**

Change `_voiceCallRoomFromSnapshot`:

```dart
VoiceCallRoom? _voiceCallRoomFromSnapshot(String callId, Object? value) {
  if (value is! Map) {
    return null;
  }
  final json = _asObjectMap(value);
  try {
    return VoiceCallRoom.fromJson(callId: callId, json: json);
  } on FormatException {
    return VoiceCallRoom.tryParseForCleanup(callId: callId, json: json);
  }
}
```

Change `_requireVoiceCall` so it still throws if cleanup parser returns null:

```dart
Future<VoiceCallRoom> _requireVoiceCall(String callId) async {
  final room = await fetchCall(callId);
  if (room == null) {
    throw VoiceSignalingException('Unknown voice call: ${callId.trim()}');
  }
  return room;
}
```

- [x] **Step 4: Ensure terminal cleanup removes all matching locks**

In `endCall`, after updating terminal room state, always call:

```dart
await _removeActiveVoiceLocksForRoomIfCurrent(room);
```

If the room was already terminal, still call the same cleanup helper and return.

- [x] **Step 5: Mirror behavior in fake adapters**

Update:

```text
packages/protocol_brain/lib/src/testing/fake_voice_signaling_adapter.dart
apps/rain/test/utils/firebase_emulator_signaling_adapter.dart
```

The fake behavior must:

- reject live user locks,
- reclaim expired terminal locks,
- use monotonic timestamps,
- clean pair and both user locks on terminal state.

- [x] **Step 6: Add lock tests**

In `packages/protocol_brain/test/voice_signaling_contract_test.dart`, add:

```dart
test('user locks prevent two callers from ringing the same callee', () async {
  final adapter = FakeVoiceSignalingAdapter();
  await adapter.createOutgoingCall(
    callId: 'alice-bob-1',
    caller: 'alice',
    callee: 'bob',
    createdAt: 1000,
    expiresAt: 10000,
  );

  expect(
    () => adapter.createOutgoingCall(
      callId: 'cara-bob-1',
      caller: 'cara',
      callee: 'bob',
      createdAt: 2000,
      expiresAt: 11000,
    ),
    throwsA(isA<VoiceSignalingException>()),
  );
});

test('terminal call removes caller callee and pair locks', () async {
  final adapter = FakeVoiceSignalingAdapter();
  await adapter.createOutgoingCall(
    callId: 'alice-bob-1',
    caller: 'alice',
    callee: 'bob',
    createdAt: 1000,
    expiresAt: 10000,
  );
  await adapter.endCall(
    callId: 'alice-bob-1',
    username: 'alice',
    status: VoiceCallSignalingStatus.ended,
    endedAt: 2000,
  );

  await adapter.createOutgoingCall(
    callId: 'alice-bob-2',
    caller: 'alice',
    callee: 'bob',
    createdAt: 3000,
    expiresAt: 12000,
  );
  final room = await adapter.fetchCall('alice-bob-2');
  expect(room?.status, VoiceCallSignalingStatus.ringing);
});
```

- [x] **Step 7: Run tests**

```powershell
dart run melos exec --scope protocol_brain -- flutter test test/voice_signaling_contract_test.dart test/firebase_contract_test.dart
dart run melos exec --scope rain -- flutter test test/integration_voice_signaling_emulator_test.dart
```

- [x] **Step 8: Commit**

```powershell
git add packages/protocol_brain/lib/adapters/firebase_adapter.dart packages/protocol_brain/lib/src/testing/fake_voice_signaling_adapter.dart apps/rain/test/utils/firebase_emulator_signaling_adapter.dart packages/protocol_brain/test/voice_signaling_contract_test.dart apps/rain/test/integration_voice_signaling_emulator_test.dart backend/firebase/database.rules.json backend/firebase/functions/index.js packages/protocol_brain/test/firebase_contract_test.dart
git commit -m "fix: harden voice call locks and cleanup"
```

---

## Phase 03: Call Runtime Retry And False Busy Semantics

**Why Here:** Once locks can be cleaned safely, the app must stop turning stale cleanup failures into confusing call failures.

**Files:**
- Create: `apps/rain/lib/application/runtime/call_retry_policy.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/application/runtime/runtime_interaction_guard.dart`
- Modify: `apps/rain/test/call_retry_policy_test.dart`
- Modify: `apps/rain/test/runtime_interaction_guard_test.dart`
- Modify: `apps/rain/test/friend_flow_test.dart`

- [x] **Step 1: Implement retry policy model**

Create `apps/rain/lib/application/runtime/call_retry_policy.dart`:

```dart
enum CallRetryDecisionKind {
  proceed,
  peerBusy,
  cleanedStaleState,
  cleanupInProgress,
  signalingFailed,
}

final class CallSignalingFailureSnapshot {
  const CallSignalingFailureSnapshot({
    required this.message,
    required this.lockWasReclaimed,
    required this.terminalRoomWasCleaned,
    required this.corruptRoomWasRepaired,
    this.peerId,
  });

  final String message;
  final bool lockWasReclaimed;
  final bool terminalRoomWasCleaned;
  final bool corruptRoomWasRepaired;
  final String? peerId;
}

final class CallRetryDecision {
  const CallRetryDecision({
    required this.kind,
    required this.userMessage,
    this.canRetryImmediately = false,
  });

  final CallRetryDecisionKind kind;
  final String userMessage;
  final bool canRetryImmediately;
}

final class CallRetryPolicy {
  const CallRetryPolicy._();

  static CallRetryDecision classifySignalingFailure(
    CallSignalingFailureSnapshot failure,
  ) {
    final message = failure.message.toLowerCase();
    final peer = failure.peerId == null ? 'Peer' : '@${failure.peerId}';
    if (failure.lockWasReclaimed ||
        failure.terminalRoomWasCleaned ||
        failure.corruptRoomWasRepaired ||
        message.contains('timestamps are invalid')) {
      return const CallRetryDecision(
        kind: CallRetryDecisionKind.cleanedStaleState,
        userMessage: 'Old call state was cleaned. Try again.',
        canRetryImmediately: true,
      );
    }
    if (message.contains('active voice call already exists')) {
      return CallRetryDecision(
        kind: CallRetryDecisionKind.peerBusy,
        userMessage: '$peer is busy in another call.',
      );
    }
    return const CallRetryDecision(
      kind: CallRetryDecisionKind.signalingFailed,
      userMessage: 'Call signaling failed. Try again.',
    );
  }
}
```

- [x] **Step 2: Route outgoing create failures through cleanup policy**

In `VoiceCallRuntime.startVoiceCall`, when `session.startOutgoing()` or `_sendVoiceFrameObject(invite)` fails:

```dart
final decision = CallRetryPolicy.classifySignalingFailure(
  CallSignalingFailureSnapshot(
    message: error.toString(),
    lockWasReclaimed: _lastVoiceLockCleanup?.lockWasReclaimed ?? false,
    terminalRoomWasCleaned:
        _lastVoiceLockCleanup?.terminalRoomWasCleaned ?? false,
    corruptRoomWasRepaired:
        _lastVoiceLockCleanup?.corruptRoomWasRepaired ?? false,
    peerId: peerId,
  ),
);
```

Then:

```dart
await _disposeCurrentVoiceCallSession();
_setVoiceCallState(
  VoiceCallState.failed(
    peerId: peerId,
    callId: callId,
    sessionEpoch: sessionEpoch,
    mediaMode: mediaMode,
    failureReason: decision.kind == CallRetryDecisionKind.peerBusy
        ? VoiceCallFailureReason.peerBusy
        : VoiceCallFailureReason.signalingFailed,
    detail: decision.userMessage,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  ),
);
```

- [x] **Step 3: Make hangup cleanup idempotent**

In `_endVoiceCallForPeer`, keep session disposal and UI terminal state even if signaling send fails:

```dart
try {
  await session.hangUp(reason: detail);
} catch (error, stackTrace) {
  _recordVoiceSignalingError(error, stackTrace);
  await _endVoiceCallInSignaling(
    peerId: peerId,
    callId: session.callId,
    status: failureReason == null
        ? VoiceCallSignalingStatus.ended
        : VoiceCallSignalingStatus.failed,
    reasonCode: failureReason?.name,
    reason: detail,
  );
} finally {
  await _disposeVoiceCallSession(session);
}
```

The key rule: local call must not remain active because best-effort signaling failed.

- [x] **Step 4: Runtime guard messages**

In `runtime_interaction_guard.dart`, lock these messages:

```dart
const peerBusyMessage = '@{peer} is busy in another call.';
const staleCallCleanedMessage = 'Old call state was cleaned. Try again.';
const cleanupInProgressMessage = 'Call state is cleaning up. Try again in a moment.';
```

Expose structured reasons:

```dart
enum RuntimeBlockReason {
  peerOffline,
  activeCall,
  activeFileTransfer,
  peerBusy,
  staleCallCleanup,
  callCleanupInProgress,
}
```

- [x] **Step 5: Add runtime tests**

In `apps/rain/test/friend_flow_test.dart`, implement:

```dart
test('pc caller can call phone after previous phone ended call without false busy', () async {
  final harness = await RainRuntimeHarness.createUsers(['pc', 'phone']);
  await harness.acceptFriends('pc', 'phone');
  await harness.startAndConnectCall(caller: 'phone', callee: 'pc');
  await harness.hangUp(caller: 'phone');

  final result = await harness.startCall(caller: 'pc', callee: 'phone');

  expect(result.phase, VoiceCallPhase.outgoingRinging);
  expect(result.failureReason, isNull);
});
```

If `RainRuntimeHarness` does not exist, add equivalent helper methods inside the test file using existing fake runtime setup. Do not introduce a new external test dependency.

- [x] **Step 6: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/call_retry_policy_test.dart test/runtime_interaction_guard_test.dart test/friend_flow_test.dart
```

- [x] **Step 7: Commit**

```powershell
git add apps/rain/lib/application/runtime/call_retry_policy.dart apps/rain/lib/application/runtime/rain_runtime_controller.dart apps/rain/lib/application/runtime/voice_call_runtime.dart apps/rain/lib/application/runtime/runtime_interaction_guard.dart apps/rain/test/call_retry_policy_test.dart apps/rain/test/runtime_interaction_guard_test.dart apps/rain/test/friend_flow_test.dart docs/superpowers/plans/2026-05-26-rain-call-signaling-v7-premium-ux.md
git commit -m "fix: clean stale call state before retry"
```

---

## Phase 04: Diagnostics That Explain Busy And Retry

**Why Here:** If this fails again on a device, diagnostics must tell whether it is real busy, stale lock, corrupt timestamp, permissions, or media failure.

**Files:**
- Modify: `apps/rain/lib/application/runtime/voice_call_diagnostics.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart`
- Modify: `apps/rain/test/crash_diagnostics_service_test.dart`

- [x] **Step 1: Add structured lock diagnostics**

Add fields to the call diagnostic event context:

```dart
'lockClaimResult': result.name,
'lockPath': lockPath,
'pairId': pairId,
'callerUserLock': caller,
'calleeUserLock': callee,
'lockCallId': lockCallId,
'lockExpiresAt': lockExpiresAt,
'lockWasReclaimed': lockWasReclaimed,
'terminalRoomWasCleaned': terminalRoomWasCleaned,
'corruptRoomWasRepaired': corruptRoomWasRepaired,
'timestampRepair': timestampRepair,
```

- [x] **Step 2: Add event names**

Record these names from runtime/Firebase adapter boundaries:

```text
voice_lock_claim_started
voice_lock_claim_blocked
voice_lock_reclaim_started
voice_lock_reclaim_completed
voice_room_timestamp_repaired
voice_terminal_cleanup_started
voice_terminal_cleanup_completed
voice_terminal_cleanup_failed
```

- [x] **Step 3: Make diagnostics export compact**

In `crash_diagnostics_service.dart`, coalesce repeated lock events by:

```text
category + name + peerId + callId + pairId
```

Keep the newest payload and increment a `count`.

- [x] **Step 4: Add diagnostics tests**

In `apps/rain/test/crash_diagnostics_service_test.dart`, add:

```dart
test('coalesces repeated voice lock events without losing newest context', () async {
  final service = CrashDiagnosticsService.inMemory();
  await service.recordEvent(
    category: 'call',
    name: 'voice_lock_claim_blocked',
    context: {'peerId': 'bob', 'callId': 'old', 'lockExpiresAt': 1},
  );
  await service.recordEvent(
    category: 'call',
    name: 'voice_lock_claim_blocked',
    context: {'peerId': 'bob', 'callId': 'old', 'lockExpiresAt': 2},
  );

  final exported = await service.exportDiagnostics();
  final events = exported['events'] as List<Object?>;
  expect(events.length, 1);
  expect(events.single.toString(), contains('lockExpiresAt: 2'));
  expect(events.single.toString(), contains('count'));
});
```

- [x] **Step 5: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/crash_diagnostics_service_test.dart
```

- [x] **Step 6: Commit**

```powershell
git add apps/rain/lib/application/runtime/voice_call_diagnostics.dart apps/rain/lib/application/runtime/voice_call_runtime.dart apps/rain/lib/infrastructure/services/crash_diagnostics_service.dart apps/rain/test/crash_diagnostics_service_test.dart docs/superpowers/plans/2026-05-26-rain-call-signaling-v7-premium-ux.md
git commit -m "chore: explain call busy and cleanup diagnostics"
```

---

## Phase 05: ARMv7 Stability Gate

**Why Here:** The user specifically reports v7 is still buggy. Keep behavior the same, reduce low-end rendering and isolate pressure.

**Files:**
- Modify: `apps/rain/lib/presentation/performance/rain_performance.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart`
- Modify: `apps/rain/lib/presentation/branding/rain_ripple_halo_surface.dart`
- Modify: `apps/rain/test/rain_performance_test.dart`
- Modify: `apps/rain/test/rain_call_manager_bar_test.dart`

- [x] **Step 1: Lock ARMv7 low-power profile**

In `rain_performance.dart`, ensure:

```dart
bool get isLowPowerCallSurface {
  return tier == RainPerformanceTier.lowPower;
}

bool get allowContinuousCallAnimation {
  return tier != RainPerformanceTier.lowPower && !disableMotion;
}

bool get allowExpensiveCallEffects {
  return tier != RainPerformanceTier.lowPower;
}
```

- [x] **Step 2: Replace expensive effects on low-power**

For call surfaces on low power:

- no blur masks,
- no large shadows,
- no continuously animated ripple,
- no constantly repainting visualizer,
- no opacity layers inside scrollable call/chat lists.

Implementation guard:

```dart
if (performance.isLowPowerCallSurface) {
  return const StaticCallHalo();
}
return AnimatedCallHalo(level: audioLevel);
```

- [x] **Step 3: Add tests**

In `apps/rain/test/rain_performance_test.dart`, add:

```dart
test('armeabi-v7a uses low power call surfaces', () {
  final profile = RainPerformanceProfile.detectForTest(abiName: 'armeabi-v7a');

  expect(profile.tier, RainPerformanceTier.lowPower);
  expect(profile.allowContinuousCallAnimation, isFalse);
  expect(profile.allowExpensiveCallEffects, isFalse);
});
```

- [x] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/rain_performance_test.dart test/rain_call_manager_bar_test.dart
```

- [x] **Step 5: Commit**

```powershell
git add apps/rain/lib/presentation/performance/rain_performance.dart apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/lib/presentation/widgets/calls/rain_call_manager_bar.dart apps/rain/lib/presentation/branding/rain_ripple_halo_surface.dart apps/rain/test/rain_performance_test.dart apps/rain/test/rain_call_manager_bar_test.dart docs/superpowers/plans/2026-05-26-rain-call-signaling-v7-premium-ux.md
git commit -m "perf: simplify call surfaces on armv7"
```

---

## Phase 06: Premium Call Surface Contract

**Why Here:** After backend/runtimes are stable, replace loose UI with a strict call workspace model.

**Files:**
- Create: `apps/rain/lib/presentation/widgets/calls/rain_call_layout_contract.dart`
- Create: `apps/rain/lib/presentation/widgets/calls/rain_call_status_strip.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: `apps/rain/test/rain_call_manager_bar_test.dart`

- [x] **Step 1: Define call surface modes**

Create `rain_call_layout_contract.dart`:

```dart
enum RainCallSurfaceMode {
  minimized,
  popup,
  fullscreen,
}

enum RainVideoRole {
  remotePrimary,
  localPrimary,
}

final class RainCallLayoutContract {
  const RainCallLayoutContract({
    required this.surfaceMode,
    required this.videoRole,
    required this.showTopManagerBar,
    required this.showExpandedControls,
    required this.showDesktopSidePanel,
  });

  final RainCallSurfaceMode surfaceMode;
  final RainVideoRole videoRole;
  final bool showTopManagerBar;
  final bool showExpandedControls;
  final bool showDesktopSidePanel;

  factory RainCallLayoutContract.forMode({
    required RainCallSurfaceMode mode,
    required RainVideoRole videoRole,
    required bool isDesktop,
  }) {
    return RainCallLayoutContract(
      surfaceMode: mode,
      videoRole: videoRole,
      showTopManagerBar: mode == RainCallSurfaceMode.minimized,
      showExpandedControls: mode != RainCallSurfaceMode.minimized,
      showDesktopSidePanel: mode == RainCallSurfaceMode.fullscreen && isDesktop,
    );
  }
}
```

- [x] **Step 2: Define top status strip**

Create `rain_call_status_strip.dart`:

```dart
class RainCallStatusStrip extends StatelessWidget {
  const RainCallStatusStrip({
    super.key,
    required this.peerLabel,
    required this.statusText,
    required this.durationText,
    required this.qualityText,
  });

  final String peerLabel;
  final String statusText;
  final String durationText;
  final String qualityText;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(peerLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('$statusText · $durationText · $qualityText'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [x] **Step 3: Add duplication tests**

In `apps/rain/test/rain_call_manager_bar_test.dart`:

```dart
testWidgets('top call manager is hidden while popup is expanded', (tester) async {
  await pumpCallSurface(tester, surfaceMode: RainCallSurfaceMode.popup);

  expect(find.byKey(const Key('rain-call-manager-bar')), findsNothing);
  expect(find.byKey(const Key('rain-call-popup')), findsOneWidget);
});

testWidgets('top call manager appears only when call is minimized', (tester) async {
  await pumpCallSurface(tester, surfaceMode: RainCallSurfaceMode.minimized);

  expect(find.byKey(const Key('rain-call-manager-bar')), findsOneWidget);
  expect(find.byKey(const Key('rain-call-popup')), findsNothing);
});
```

- [x] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/rain_call_manager_bar_test.dart
```

- [x] **Step 5: Commit**

```powershell
git add apps/rain/lib/presentation/widgets/calls/rain_call_layout_contract.dart apps/rain/lib/presentation/widgets/calls/rain_call_status_strip.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/test/rain_call_manager_bar_test.dart
git commit -m "feat: define shared call surface contract"
```

---

## Phase 07: Video Stage And Fullscreen Workspace

**Why Here:** The current fullscreen/video UI feels like raw camera footage. This phase creates a real call workspace.

**Files:**
- Create: `apps/rain/lib/presentation/widgets/calls/rain_call_stage.dart`
- Create: `apps/rain/lib/presentation/widgets/calls/rain_call_workspace.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Modify: `apps/rain/lib/presentation/screens/home_screen.dart`
- Create: `apps/rain/test/rain_call_stage_test.dart`
- Create: `apps/rain/test/rain_call_workspace_test.dart`

- [x] **Step 1: Create call stage**

Create `rain_call_stage.dart` with these widget keys:

```dart
const rainRemotePrimaryVideoKey = Key('rain-remote-primary-video');
const rainLocalPreviewVideoKey = Key('rain-local-preview-video');
const rainVoiceOnlyStageKey = Key('rain-voice-only-stage');
```

Stage rules:

- If `mediaMode == video` and remote stream exists, remote is primary.
- If local preview exists, render it as small preview.
- Tapping preview swaps role.
- If remote video is missing, show waiting state, not blank black/white space.
- If voice-only, show Peer Core mark audio visualizer.

- [x] **Step 2: Create fullscreen workspace**

Create `rain_call_workspace.dart` with:

```dart
class RainCallWorkspace extends StatelessWidget {
  const RainCallWorkspace({
    super.key,
    required this.callState,
    required this.controls,
    required this.stage,
    required this.showDesktopSidePanel,
    required this.onExitFullscreen,
  });
}
```

Layout rules:

- `Positioned.fill` over the whole app.
- `SafeArea` around status strip and control dock.
- Top: `RainCallStatusStrip`.
- Center: `RainCallStage`.
- Bottom: `RainCallControlDock`.
- Desktop side panel width: default `280`, min `220`, max `380`, collapsed `56`.
- Mobile: no side panel.

- [x] **Step 3: Add stage tests**

In `apps/rain/test/rain_call_stage_test.dart`:

```dart
testWidgets('video call renders remote as primary and local as preview', (tester) async {
  await pumpVideoCallStage(
    tester,
    hasRemoteVideo: true,
    hasLocalVideo: true,
  );

  expect(find.byKey(rainRemotePrimaryVideoKey), findsOneWidget);
  expect(find.byKey(rainLocalPreviewVideoKey), findsOneWidget);
});

testWidgets('tapping local preview swaps primary role', (tester) async {
  await pumpVideoCallStage(
    tester,
    hasRemoteVideo: true,
    hasLocalVideo: true,
  );

  await tester.tap(find.byKey(rainLocalPreviewVideoKey));
  await tester.pumpAndSettle();

  expect(find.byKey(const Key('rain-local-primary-video')), findsOneWidget);
  expect(find.byKey(const Key('rain-remote-preview-video')), findsOneWidget);
});
```

- [x] **Step 4: Add workspace tests**

In `apps/rain/test/rain_call_workspace_test.dart`:

```dart
testWidgets('fullscreen workspace keeps controls visible inside safe area', (tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 780));
  await pumpFullscreenWorkspace(tester);

  expect(find.byKey(const Key('rain-call-status-strip')), findsOneWidget);
  expect(find.byKey(const Key('rain-call-control-dock')), findsOneWidget);
});

testWidgets('desktop workspace shows collapsible side panel', (tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 800));
  await pumpFullscreenWorkspace(tester, isDesktop: true);

  expect(find.byKey(const Key('rain-call-desktop-side-panel')), findsOneWidget);
  await tester.tap(find.byKey(const Key('rain-call-side-panel-collapse')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('rain-call-side-panel-collapsed')), findsOneWidget);
});
```

- [x] **Step 5: Wire overlay and home screen**

In `rain_call_overlay.dart`:

- expanded popup uses `RainCallStage`,
- fullscreen uses `RainCallWorkspace`,
- minimized mode hides popup and shows manager bar through existing home shell.

In `home_screen.dart`:

- prevent manager bar when fullscreen/popup is active,
- `exit fullscreen` returns to popup or minimized based on previous mode,
- video call button cannot create duplicate fullscreen state.

- [x] **Step 6: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/rain_call_stage_test.dart test/rain_call_workspace_test.dart test/rain_call_manager_bar_test.dart
```

- [x] **Step 7: Commit**

```powershell
git add apps/rain/lib/presentation/widgets/calls/rain_call_stage.dart apps/rain/lib/presentation/widgets/calls/rain_call_workspace.dart apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/lib/presentation/screens/home_screen.dart apps/rain/test/rain_call_stage_test.dart apps/rain/test/rain_call_workspace_test.dart apps/rain/test/rain_call_manager_bar_test.dart
git commit -m "feat: add premium fullscreen call workspace"
```

---

## Phase 08: Device-Aware Controls And Icon Audit

**Why Here:** Speaker, Bluetooth, microphone, and camera controls must match actual device capabilities.

**Files:**
- Modify: `apps/rain/lib/application/runtime/media_device_settings.dart`
- Modify: `apps/rain/lib/application/runtime/voice_call_state.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: `apps/rain/lib/presentation/screens/settings_screen.dart`
- Modify: `apps/rain/test/media_device_settings_test.dart`
- Modify: `apps/rain/test/rain_chat_widgets_test.dart`

- [x] **Step 1: Lock output route visibility rules**

Rules:

- Windows with one output: hide output route control.
- Windows with multiple outputs: show dropdown with real labels.
- Android no Bluetooth/wired: show phone audio and speakerphone only.
- Android Bluetooth connected: show Bluetooth route.
- Android wired/headset connected: show wired/headset route.
- Unsupported route switching: hide route button instead of showing a broken button.

- [x] **Step 2: Lock camera control visibility rules**

Rules:

- One camera: hide flip camera.
- Two or more cameras: show flip camera.
- Video muted is always visible during video call.
- Voice call does not show camera controls except upgrade-to-video if that feature remains supported.

- [x] **Step 3: Fix semantic icons**

In `rain_call_controls.dart`:

```text
mic mute: mic / mic_off
camera: video / video_off
deafen: hearing / hearing_disabled or volume_x
output route: speaker / headphones / bluetooth
hangup: phone_off in danger color
fullscreen: maximize / minimize
```

No speaker route button may use the mute icon.

- [x] **Step 4: Add tests**

In `apps/rain/test/media_device_settings_test.dart`:

```dart
test('windows single output hides route selector', () {
  final snapshot = AdaptiveMediaCapabilitySnapshot(
    audioOutputDevices: const [MediaDeviceInfo(deviceId: 'default', label: 'Default')],
    platform: AdaptivePlatform.windows,
  );

  expect(snapshot.shouldShowOutputSelector, isFalse);
});

test('windows multiple outputs exposes desktop output devices', () {
  final snapshot = AdaptiveMediaCapabilitySnapshot(
    audioOutputDevices: const [
      MediaDeviceInfo(deviceId: 'default', label: 'Default'),
      MediaDeviceInfo(deviceId: 'headset', label: 'USB Headset'),
    ],
    platform: AdaptivePlatform.windows,
  );

  expect(snapshot.shouldShowOutputSelector, isTrue);
  expect(snapshot.outputTargets.map((target) => target.label), contains('USB Headset'));
});
```

- [x] **Step 5: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/media_device_settings_test.dart test/rain_chat_widgets_test.dart
```

- [x] **Step 6: Commit**

```powershell
git add apps/rain/lib/application/runtime/media_device_settings.dart apps/rain/lib/application/runtime/voice_call_state.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/lib/presentation/screens/settings_screen.dart apps/rain/test/media_device_settings_test.dart apps/rain/test/rain_chat_widgets_test.dart
git commit -m "fix: adapt call controls to real device capabilities"
```

---

## Phase 09: Voice-Only Visualizer And Mobile Answer UI

**Why Here:** Voice calls need a polished surface, not generic waves. Incoming answer/decline must be perfect on small screens.

**Files:**
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_stage.dart`
- Modify: `apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart`
- Modify: `apps/rain/test/rain_call_stage_test.dart`
- Modify: `apps/rain/test/rain_chat_widgets_test.dart`

- [x] **Step 1: Build Peer Core emitting visualizer**

Rules:

- Center source is the Peer Core mark/dots.
- Waves emit outward from the mark, not detached bars above/below.
- Real audio level drives intensity.
- Reduced motion and ARMv7 show static halo only.
- Visualizer is never inside scrollable chat content.

Widget key:

```dart
const rainCallAudioEmitterKey = Key('rain-call-audio-emitter');
```

- [x] **Step 2: Fix incoming answer/decline layout**

Mobile incoming call UI:

- full width within safe area,
- avatar/mark top,
- peer label,
- media mode label,
- decline button left in danger style,
- accept button right in success style,
- buttons at least 56 px high,
- button labels do not wrap awkwardly,
- portrait and narrow widths supported.

Desktop incoming call UI:

- compact centered popup,
- same labels/icons/actions,
- keyboard focus order: Decline, Accept.

- [x] **Step 3: Add tests**

```dart
testWidgets('voice stage emits waves from Peer Core mark', (tester) async {
  await pumpVoiceCallStage(tester, audioLevel: 0.8);

  expect(find.byKey(rainCallAudioEmitterKey), findsOneWidget);
  expect(find.byKey(const Key('rain-detached-equalizer-bars')), findsNothing);
});

testWidgets('incoming call actions fit on compact mobile screen', (tester) async {
  await tester.binding.setSurfaceSize(const Size(320, 640));
  await pumpIncomingCallOverlay(tester);

  expect(find.byKey(const Key('rain-call-decline-button')), findsOneWidget);
  expect(find.byKey(const Key('rain-call-accept-button')), findsOneWidget);
  expect(tester.getBottomLeft(find.byKey(const Key('rain-call-accept-button'))).dy, lessThan(640));
});
```

- [x] **Step 4: Run tests**

```powershell
dart run melos exec --scope rain -- flutter test test/rain_call_stage_test.dart test/rain_chat_widgets_test.dart
```

- [x] **Step 5: Commit**

```powershell
git add apps/rain/lib/presentation/widgets/calls/rain_call_overlay.dart apps/rain/lib/presentation/widgets/calls/rain_call_stage.dart apps/rain/lib/presentation/widgets/calls/rain_call_controls.dart apps/rain/test/rain_call_stage_test.dart apps/rain/test/rain_chat_widgets_test.dart
git commit -m "feat: polish voice call stage and incoming actions"
```

---

## Phase 10: Integrated Voice/Video Runtime Gate

**Why Here:** The backend and UI can pass separately but still fail together. This phase tests real app-level sequences.

**Files:**
- Modify: `apps/rain/lib/application/runtime/voice_call_runtime.dart`
- Modify: `apps/rain/test/friend_flow_test.dart`
- Modify: `apps/rain/test/integration_voice_signaling_emulator_test.dart`
- Modify: `apps/rain/test/runtime_network_loss_test.dart`

- [x] **Step 1: Add PC-phone direction tests**

Required scenarios:

```text
Windows-like user starts voice call to Android-like user.
Android-like user starts voice call to Windows-like user.
Windows-like user starts video call to Android-like user.
Android-like user starts video call to Windows-like user.
Previous call ended by callee then caller can immediately call back.
Previous call ended by caller then callee can immediately call back.
```

Use existing fake runtime/platform hooks. If the tests cannot truly simulate OS, name variables `pcUser` and `phoneUser` and simulate capability snapshots.

- [x] **Step 2: Add app-close cleanup tests**

```dart
test('closing app during ringing ends call and removes locks', () async {});
test('closing app during active video call ends call and removes locks', () async {});
test('remote app close shows connection ended instead of reconnecting forever', () async {});
```

- [x] **Step 3: Add weak transport grace tests**

```dart
test('temporary transport loss shows reconnecting grace before failing call', () async {});
test('recovered transport clears reconnecting state and keeps call active', () async {});
```

- [x] **Step 4: Run integration tests**

```powershell
dart run melos exec --scope rain -- flutter test test/friend_flow_test.dart test/integration_voice_signaling_emulator_test.dart test/runtime_network_loss_test.dart
```

- [x] **Step 5: Commit**

```powershell
git add apps/rain/test/friend_flow_test.dart apps/rain/test/integration_voice_signaling_emulator_test.dart apps/rain/test/runtime_network_loss_test.dart
git commit -m "test: cover cross-device call runtime flows"
```

---

## Phase 11: Full Automated Validation Gate

**Why Here:** This touches Firebase, runtime, and UI. Run the full gate before any build.

**Files:**
- No source changes expected unless a validation failure identifies a real bug.

- [x] **Step 1: Restore dependencies**

```powershell
dart pub get
```

Expected:

```text
Got dependencies
```

- [x] **Step 2: Analyze**

```powershell
dart run melos run analyze
```

Expected:

```text
No issues found
```

- [x] **Step 3: Test**

```powershell
dart run melos run test
```

Expected:

```text
All tests passed
```

- [x] **Step 4: Commit validation-only fixes if needed**

If validation required code or test fixes:

```powershell
git add <changed-files>
git commit -m "fix: resolve call stability validation issues"
```

If no files changed:

```powershell
git status --short
```

Expected:

```text
no output
```

---

## Phase 12: Manual Device Gate

**Why Here:** WebRTC call reliability cannot be proven only with unit tests. Do this before release builds.

**Devices:**

- Windows PC signed in as user A.
- Android ARM64 phone signed in as user B.
- Android ARMv7 phone signed in as user C, if available.

**Manual Script:**

- [ ] **Step 1: PC to phone voice**

Run 10 times:

```text
PC starts voice call to Android.
Android accepts.
Talk for 15 seconds.
Mute/unmute once.
Hang up from PC on odd runs.
Hang up from Android on even runs.
Immediately start a new call in the opposite direction.
```

Pass:

```text
No false peer busy.
No stuck ringing.
No failed hangup.
Firebase activeVoiceUsers and activeVoicePairs are clean after each terminal call.
```

- [ ] **Step 2: Phone to PC voice**

Run 10 times with caller/callee reversed.

Pass:

```text
First attempt succeeds when both apps are open and online.
Retry is not needed for normal path.
If a failure occurs, diagnostics state exact cause.
```

- [ ] **Step 3: PC to phone video**

Run 5 times:

```text
PC starts video call to Android.
Android accepts.
Remote video is primary.
Local preview is small.
Tap preview swaps.
Fullscreen shows status strip and controls.
Exit fullscreen restores popup/minimized correctly.
```

- [ ] **Step 4: Phone to PC video**

Run 5 times with caller/callee reversed.

Pass:

```text
No crash.
No duplicate manager bar.
No raw stretched video-only fullscreen.
No flip camera on single-camera PC.
```

- [ ] **Step 5: ARMv7 smoke**

On ARMv7:

```text
Open app.
Scroll friends.
Open chat.
Pull refresh.
Connect peer.
Open voice call UI.
Open video call UI if hardware supports it.
Hang up.
```

Pass:

```text
No visible freeze longer than 500 ms.
No repeated dropped-frame bursts during simple scroll.
No stuck call controls.
```

- [ ] **Step 6: Export diagnostics after failures only**

If any step fails, export diagnostics from both peers and record:

```text
caller username
callee username
device model
platform
APK/EXE build name
call direction
media mode
error message
time in local timezone
```

Do not release until failures have a root cause or are explicitly accepted.

---

## Phase 13: Final Build And Cloud Release Gate

**Why Last:** Builds consume time and user bandwidth. Build only after tests and manual gate pass.

**Files:**
- No source changes expected.

- [ ] **Step 1: Confirm clean branch**

```powershell
git status --short --branch
```

Expected:

```text
## dev...origin/dev
```

or a known `ahead` count that will be pushed before cloud build.

- [ ] **Step 2: Push dev**

```powershell
git push origin dev
```

If HTTPS push is blocked by local network but GitHub API is reachable, use the repo's established GitHub API fast-forward fallback only after confirming remote `dev` still equals local `origin/dev`.

- [ ] **Step 3: Trigger cloud artifact workflow**

```powershell
gh workflow run build-artifacts.yml --ref dev -f platform=all -f build_profile=demo -f publish_test_release=true
```

Expected:

```text
https://github.com/EslamNabawy/Rain/actions/runs/<run-id>
```

- [ ] **Step 4: Verify artifacts**

Expected artifact/release assets:

```text
Rain-Demo-Android-v7a.apk
Rain-Demo-Android-v8-v9.apk
Rain-Demo-Windows-x64.zip
```

- [ ] **Step 5: Final commit status**

```powershell
git log --oneline --max-count=10
git status --short --branch
```

Record latest commit SHA in the final response.

---

## Implementation Order Summary

1. Evidence tests.
2. Protocol monotonic clock.
3. Firebase/fake lock cleanup.
4. Runtime retry semantics.
5. Diagnostics.
6. ARMv7 low-power call surfaces.
7. Shared call UI contract.
8. Fullscreen video workspace.
9. Device-aware controls.
10. Voice-only visualizer and incoming action polish.
11. Integrated runtime tests.
12. Full validation.
13. Manual gate.
14. Cloud build.

---

## Risk Controls

- Do not change Firebase auth, identity, friend schema, chat messages, or file transfer protocol.
- Do not remove existing call locks; make them correct and observable.
- Do not weaken normal voice room validation; only add cleanup-safe parsing for stale/corrupt existing records.
- Do not add new native DSP, ML, or media dependencies.
- Do not make video calls renegotiate for UI-only changes.
- Do not run release builds before validation and manual gate.
- Commit after each phase.

---

## Self-Review Checklist

- [ ] False PC-to-phone `peer busy` has backend lock, runtime, and diagnostics coverage.
- [ ] Phone-to-PC retry failures have timestamp, stale room, and cleanup coverage.
- [ ] Hangup cleanup cannot leave local runtime stuck active.
- [ ] ARMv7 gets explicit low-power rendering behavior.
- [ ] Fullscreen call UI is a workspace with status and controls.
- [ ] Video primary/preview roles are defined and tested.
- [ ] Incoming answer/decline controls are tested on compact mobile.
- [ ] Device controls are capability-gated.
- [ ] Manual device gate includes Windows, Android ARM64, and ARMv7.
- [ ] Cloud build is last.
