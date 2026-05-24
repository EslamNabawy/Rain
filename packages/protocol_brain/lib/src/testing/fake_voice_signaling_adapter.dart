import 'dart:async';

import '../voice_call_frame.dart';
import '../voice_signaling_contract.dart';

final class FakeVoiceSignalingAdapter implements VoiceSignalingAdapter {
  static const int _orphanVoiceLockGraceMs = 15000;

  final Map<String, VoiceCallRoom> _rooms = <String, VoiceCallRoom>{};
  final Map<String, VoiceActivePairLock> _pairLocks =
      <String, VoiceActivePairLock>{};
  final Map<String, Map<String, VoiceCallInboxEntry>> _inboxes =
      <String, Map<String, VoiceCallInboxEntry>>{};
  final Map<String, List<VoiceCallIceCandidateRecord>> _iceCandidates =
      <String, List<VoiceCallIceCandidateRecord>>{};
  final Map<String, StreamController<VoiceCallRoom?>> _callControllers =
      <String, StreamController<VoiceCallRoom?>>{};
  final Map<String, StreamController<VoiceCallInboxEntry>> _inboxControllers =
      <String, StreamController<VoiceCallInboxEntry>>{};
  final Map<String, StreamController<VoiceSignalingEnvelope>>
  _offerControllers = <String, StreamController<VoiceSignalingEnvelope>>{};
  final Map<String, StreamController<VoiceSignalingEnvelope>>
  _answerControllers = <String, StreamController<VoiceSignalingEnvelope>>{};
  final Map<String, StreamController<VoiceCallIceCandidateRecord>>
  _iceControllers = <String, StreamController<VoiceCallIceCandidateRecord>>{};

  int _nextIceId = 0;
  bool _disposed = false;

  Map<String, VoiceCallRoom> get rooms =>
      Map<String, VoiceCallRoom>.unmodifiable(_rooms);

  Map<String, VoiceActivePairLock> get activePairLocks =>
      Map<String, VoiceActivePairLock>.unmodifiable(_pairLocks);

  void seedActivePairLockForTest(VoiceActivePairLock lock) {
    _ensureOpen();
    lock.toJson();
    _pairLocks[lock.pairId] = lock;
  }

  void reemitCallForTest(String callId) {
    _ensureOpen();
    _emitCall(callId.trim());
  }

  List<VoiceCallInboxEntry> inboxFor(String username) {
    final inbox = _inboxes[normalizeVoiceCallUsername(username)];
    return List<VoiceCallInboxEntry>.unmodifiable(
      inbox?.values ?? const <VoiceCallInboxEntry>[],
    );
  }

  @override
  Future<VoiceCallRoom> createOutgoingCall({
    required String callId,
    required String caller,
    required String callee,
    required int createdAt,
    required int expiresAt,
    CallMediaMode mediaMode = CallMediaMode.audio,
  }) async {
    _ensureOpen();
    final normalizedCallId = callId.trim();
    final normalizedCaller = normalizeVoiceCallUsername(caller);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    final pairId = voiceCallPairId(normalizedCaller, normalizedCallee);
    if (_rooms.containsKey(normalizedCallId)) {
      throw VoiceSignalingException('Voice call already exists: $callId');
    }
    final existingLock = _pairLocks[pairId];
    if (existingLock != null &&
        !_reclaimActivePairLockIfStale(
          existingLock,
          createdAt,
          caller: normalizedCaller,
        )) {
      throw VoiceSignalingException(
        'Active voice call already exists for pair $pairId.',
      );
    }

    final room = VoiceCallRoom(
      v: VoiceCallRoom.version,
      callId: normalizedCallId,
      pairId: pairId,
      caller: normalizedCaller,
      callee: normalizedCallee,
      status: VoiceCallSignalingStatus.ringing,
      mediaMode: mediaMode,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
      muted: Map<String, bool>.unmodifiable(<String, bool>{
        normalizedCaller: false,
        normalizedCallee: false,
      }),
      cameraMuted: mediaMode == CallMediaMode.video
          ? Map<String, bool>.unmodifiable(<String, bool>{
              normalizedCaller: false,
              normalizedCallee: false,
            })
          : const <String, bool>{},
    );
    room.validate();
    final lock = VoiceActivePairLock(
      pairId: pairId,
      callId: normalizedCallId,
      caller: normalizedCaller,
      callee: normalizedCallee,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
    );
    lock.toJson();
    final inboxEntry = VoiceCallInboxEntry(
      callId: normalizedCallId,
      from: normalizedCaller,
      to: normalizedCallee,
      pairId: pairId,
      status: VoiceCallSignalingStatus.ringing,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
    );
    inboxEntry.toJson();

    _rooms[normalizedCallId] = room;
    _pairLocks[pairId] = lock;
    _inboxes.putIfAbsent(
      normalizedCallee,
      () => <String, VoiceCallInboxEntry>{},
    )[normalizedCallId] = inboxEntry;
    _emitCall(normalizedCallId);
    _emitInbox(normalizedCallee, inboxEntry);
    return room;
  }

  @override
  Future<VoiceCallRoom?> fetchCall(String callId) async {
    _ensureOpen();
    return _rooms[callId.trim()];
  }

  @override
  Stream<VoiceCallRoom?> watchCall(String callId) async* {
    _ensureOpen();
    final normalizedCallId = callId.trim();
    yield _rooms[normalizedCallId];
    yield* _callController(normalizedCallId).stream;
  }

  @override
  Stream<VoiceCallInboxEntry> watchIncomingCalls(String username) async* {
    _ensureOpen();
    final normalizedUsername = normalizeVoiceCallUsername(username);
    for (final entry
        in _inboxes[normalizedUsername]?.values ??
            const Iterable<VoiceCallInboxEntry>.empty()) {
      if (!entry.status.isTerminal) {
        yield entry;
      }
    }
    yield* _inboxController(normalizedUsername).stream;
  }

  @override
  Future<void> acceptCall({
    required String callId,
    required String callee,
    required int acceptedAt,
  }) async {
    _ensureOpen();
    final room = _requireRoom(callId);
    _ensureStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.ringing,
    });
    _ensureRole(room, callee, VoiceCallRole.callee);
    _putRoom(
      room.copyWith(
        status: VoiceCallSignalingStatus.accepted,
        updatedAt: acceptedAt,
        acceptedAt: acceptedAt,
      ),
    );
  }

  @override
  Future<void> markConnected({
    required String callId,
    required String username,
    required int connectedAt,
  }) async {
    _ensureOpen();
    final room = _requireRoom(callId);
    _ensureParticipant(room, username);
    _ensureStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.accepted,
      VoiceCallSignalingStatus.negotiating,
      VoiceCallSignalingStatus.connected,
    });
    _putRoom(
      room.copyWith(
        status: VoiceCallSignalingStatus.connected,
        updatedAt: connectedAt,
        connectedAt: connectedAt,
      ),
    );
  }

  @override
  Future<void> endCall({
    required String callId,
    required String username,
    required VoiceCallSignalingStatus status,
    required int endedAt,
    String? reasonCode,
    String? reason,
  }) async {
    _ensureOpen();
    if (!status.isTerminal) {
      throw const VoiceSignalingException(
        'Voice call end status must be terminal.',
      );
    }
    final room = _requireRoom(callId);
    _ensureParticipant(room, username);
    if (room.status.isTerminal) {
      _removeActivePairLockForRoomIfCurrent(room);
      return;
    }
    final normalizedUsername = normalizeVoiceCallUsername(username);
    _putRoom(
      room.copyWith(
        status: status,
        updatedAt: endedAt,
        endedAt: endedAt,
        endedBy: normalizedUsername,
        reasonCode: reasonCode,
        reason: reason,
      ),
    );
    _pairLocks.remove(room.pairId);
  }

  @override
  Future<void> setMuted({
    required String callId,
    required String username,
    required bool muted,
    required int updatedAt,
  }) async {
    _ensureOpen();
    final room = _requireRoom(callId);
    _ensureParticipant(room, username);
    _ensureNonTerminal(room);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    _putRoom(
      room.copyWith(
        updatedAt: updatedAt,
        muted: <String, bool>{...room.muted, normalizedUsername: muted},
      ),
    );
  }

  @override
  Future<void> setCameraMuted({
    required String callId,
    required String username,
    required bool cameraMuted,
    required int updatedAt,
  }) async {
    _ensureOpen();
    final room = _requireRoom(callId);
    _ensureParticipant(room, username);
    _ensureNonTerminal(room);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    _putRoom(
      room.copyWith(
        updatedAt: updatedAt,
        cameraMuted: <String, bool>{
          ...room.cameraMuted,
          normalizedUsername: cameraMuted,
        },
      ),
    );
  }

  @override
  Future<void> writeVoiceOffer({
    required String callId,
    required String caller,
    required VoiceSignalingEnvelope offer,
    required int updatedAt,
  }) async {
    _ensureOpen();
    offer.validate(
      maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
    );
    final room = _requireRoom(callId);
    _ensureRole(room, caller, VoiceCallRole.caller);
    _ensureStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.accepted,
      VoiceCallSignalingStatus.negotiating,
    });
    _putRoom(
      room.copyWith(
        status: VoiceCallSignalingStatus.negotiating,
        updatedAt: updatedAt,
        offer: offer,
      ),
    );
    _offerController(room.callId).add(offer);
  }

  @override
  Future<void> writeVoiceAnswer({
    required String callId,
    required String callee,
    required VoiceSignalingEnvelope answer,
    required int updatedAt,
  }) async {
    _ensureOpen();
    answer.validate(
      maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
    );
    final room = _requireRoom(callId);
    _ensureRole(room, callee, VoiceCallRole.callee);
    _ensureStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.negotiating,
    });
    if (room.offer == null) {
      throw const VoiceSignalingException(
        'Cannot write voice answer before offer.',
      );
    }
    _putRoom(
      room.copyWith(
        status: VoiceCallSignalingStatus.negotiating,
        updatedAt: updatedAt,
        answer: answer,
      ),
    );
    _answerController(room.callId).add(answer);
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceOffer(String callId) async* {
    _ensureOpen();
    final normalizedCallId = callId.trim();
    final offer = _rooms[normalizedCallId]?.offer;
    if (offer != null) {
      yield offer;
    }
    yield* _offerController(normalizedCallId).stream;
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceAnswer(String callId) async* {
    _ensureOpen();
    final normalizedCallId = callId.trim();
    final answer = _rooms[normalizedCallId]?.answer;
    if (answer != null) {
      yield answer;
    }
    yield* _answerController(normalizedCallId).stream;
  }

  @override
  Future<String> writeIceCandidate({
    required String callId,
    required String username,
    required VoiceCallRole role,
    required VoiceSignalingEnvelope candidate,
    required int createdAt,
  }) async {
    _ensureOpen();
    candidate.validate(
      maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength,
    );
    final room = _requireRoom(callId);
    _ensureRole(room, username, role);
    _ensureStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.accepted,
      VoiceCallSignalingStatus.negotiating,
      VoiceCallSignalingStatus.connected,
    });
    final candidateId = 'ice-${++_nextIceId}';
    final record = VoiceCallIceCandidateRecord(
      callId: room.callId,
      candidateId: candidateId,
      role: role,
      envelope: candidate,
      createdAt: createdAt,
    );
    record.toJson();
    final key = _iceKey(room.callId, role);
    _iceCandidates
        .putIfAbsent(key, () => <VoiceCallIceCandidateRecord>[])
        .add(record);
    _iceController(key).add(record);
    return candidateId;
  }

  @override
  Stream<VoiceCallIceCandidateRecord> watchIceCandidates({
    required String callId,
    required VoiceCallRole role,
  }) async* {
    _ensureOpen();
    final key = _iceKey(callId.trim(), role);
    for (final record
        in _iceCandidates[key] ??
            const Iterable<VoiceCallIceCandidateRecord>.empty()) {
      yield record;
    }
    yield* _iceController(key).stream;
  }

  @override
  Future<void> deleteCall(String callId) async {
    _ensureOpen();
    final normalizedCallId = callId.trim();
    final room = _rooms.remove(normalizedCallId);
    if (room == null) {
      return;
    }
    _removeActivePairLockForRoomIfCurrent(room);
    _inboxes[room.callee]?.remove(room.callId);
    _iceCandidates.remove(_iceKey(room.callId, VoiceCallRole.caller));
    _iceCandidates.remove(_iceKey(room.callId, VoiceCallRole.callee));
    _emitCall(normalizedCallId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final controllers = <StreamController<Object?>>[
      ..._callControllers.values,
      ..._inboxControllers.values,
      ..._offerControllers.values,
      ..._answerControllers.values,
      ..._iceControllers.values,
    ];
    for (final controller in controllers) {
      await controller.close();
    }
  }

  VoiceCallRoom _requireRoom(String callId) {
    final room = _rooms[callId.trim()];
    if (room == null) {
      throw VoiceSignalingException('Unknown voice call: $callId');
    }
    return room;
  }

  void _putRoom(VoiceCallRoom room) {
    room.validate();
    _rooms[room.callId] = room;
    _updateInbox(room);
    _emitCall(room.callId);
  }

  bool _reclaimActivePairLockIfStale(
    VoiceActivePairLock lock,
    int createdAt, {
    required String caller,
  }) {
    final room = _rooms[lock.callId];
    if (lock.expiresAt <= createdAt) {
      if (room != null && _shouldDeleteReclaimedVoiceRoom(room, createdAt)) {
        _removeCallArtifacts(lock.callId);
      }
      _pairLocks.remove(lock.pairId);
      return true;
    }

    if (room == null) {
      if (lock.caller == normalizeVoiceCallUsername(caller)) {
        _pairLocks.remove(lock.pairId);
        return true;
      }
      if (createdAt - lock.updatedAt < _orphanVoiceLockGraceMs) {
        return false;
      }
      _pairLocks.remove(lock.pairId);
      return true;
    }

    final setupExpired =
        room.status != VoiceCallSignalingStatus.connected &&
        room.expiresAt <= createdAt;
    if (!room.isTerminal && !setupExpired) {
      return false;
    }

    _removeCallArtifacts(room.callId);
    _pairLocks.remove(lock.pairId);
    return true;
  }

  void _removeActivePairLockForRoomIfCurrent(VoiceCallRoom room) {
    if (_pairLocks[room.pairId]?.callId == room.callId) {
      _pairLocks.remove(room.pairId);
    }
  }

  bool _shouldDeleteReclaimedVoiceRoom(VoiceCallRoom room, int createdAt) {
    if (room.isTerminal) {
      return true;
    }
    return room.status != VoiceCallSignalingStatus.connected &&
        room.expiresAt <= createdAt;
  }

  void _removeCallArtifacts(String callId) {
    final room = _rooms.remove(callId.trim());
    if (room == null) {
      return;
    }
    _inboxes[room.callee]?.remove(room.callId);
    _iceCandidates.remove(_iceKey(room.callId, VoiceCallRole.caller));
    _iceCandidates.remove(_iceKey(room.callId, VoiceCallRole.callee));
    _emitCall(room.callId);
  }

  void _updateInbox(VoiceCallRoom room) {
    final inboxEntry = VoiceCallInboxEntry(
      callId: room.callId,
      from: room.caller,
      to: room.callee,
      pairId: room.pairId,
      status: room.status,
      createdAt: room.createdAt,
      updatedAt: room.updatedAt,
      expiresAt: room.expiresAt,
    );
    inboxEntry.toJson();
    _inboxes.putIfAbsent(
      room.callee,
      () => <String, VoiceCallInboxEntry>{},
    )[room.callId] = inboxEntry;
    _emitInbox(room.callee, inboxEntry);
  }

  void _ensureParticipant(VoiceCallRoom room, String username) {
    final normalized = normalizeVoiceCallUsername(username);
    if (normalized != room.caller && normalized != room.callee) {
      throw VoiceSignalingException(
        '@$normalized is not a participant in ${room.callId}.',
      );
    }
  }

  void _ensureRole(VoiceCallRoom room, String username, VoiceCallRole role) {
    final normalized = normalizeVoiceCallUsername(username);
    final expected = voiceCallRoleUsername(room, role);
    if (normalized != expected) {
      throw VoiceSignalingException(
        '@$normalized cannot write ${role.name} signaling for ${room.callId}.',
      );
    }
  }

  void _ensureStatus(
    VoiceCallRoom room,
    Set<VoiceCallSignalingStatus> allowed,
  ) {
    if (!allowed.contains(room.status)) {
      throw VoiceSignalingException(
        'Voice call ${room.callId} is ${room.status.name}.',
      );
    }
  }

  void _ensureNonTerminal(VoiceCallRoom room) {
    if (room.status.isTerminal) {
      throw VoiceSignalingException('Voice call ${room.callId} already ended.');
    }
  }

  StreamController<VoiceCallRoom?> _callController(String callId) {
    return _callControllers.putIfAbsent(
      callId,
      () => StreamController<VoiceCallRoom?>.broadcast(sync: true),
    );
  }

  StreamController<VoiceCallInboxEntry> _inboxController(String username) {
    return _inboxControllers.putIfAbsent(
      username,
      () => StreamController<VoiceCallInboxEntry>.broadcast(sync: true),
    );
  }

  StreamController<VoiceSignalingEnvelope> _offerController(String callId) {
    return _offerControllers.putIfAbsent(
      callId,
      () => StreamController<VoiceSignalingEnvelope>.broadcast(sync: true),
    );
  }

  StreamController<VoiceSignalingEnvelope> _answerController(String callId) {
    return _answerControllers.putIfAbsent(
      callId,
      () => StreamController<VoiceSignalingEnvelope>.broadcast(sync: true),
    );
  }

  StreamController<VoiceCallIceCandidateRecord> _iceController(String key) {
    return _iceControllers.putIfAbsent(
      key,
      () => StreamController<VoiceCallIceCandidateRecord>.broadcast(sync: true),
    );
  }

  void _emitCall(String callId) {
    final controller = _callControllers[callId];
    if (controller != null && !controller.isClosed) {
      controller.add(_rooms[callId]);
    }
  }

  void _emitInbox(String username, VoiceCallInboxEntry entry) {
    final controller = _inboxControllers[username];
    if (controller != null && !controller.isClosed) {
      controller.add(entry);
    }
  }

  String _iceKey(String callId, VoiceCallRole role) {
    return '${callId.trim()}/${role.name}';
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const VoiceSignalingException(
        'Voice signaling adapter has been disposed.',
      );
    }
  }
}
