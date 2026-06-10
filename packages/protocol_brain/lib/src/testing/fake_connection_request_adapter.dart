import 'dart:async';

import '../connection_request_adapter.dart';
import '../connection_request_contract.dart';

typedef ConnectionRequestClock = int Function();

final class FakeConnectionRequestAdapter implements ConnectionRequestAdapter {
  FakeConnectionRequestAdapter({
    required String currentUsername,
    ConnectionRequestClock? clock,
    ConnectionRequestAdapterDiagnosticsSink? diagnosticsSink,
  }) : _currentUsername = normalizeConnectionRequestUsername(currentUsername),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
       _diagnosticsSink = diagnosticsSink;

  final String _currentUsername;
  final ConnectionRequestClock _clock;
  final ConnectionRequestAdapterDiagnosticsSink? _diagnosticsSink;
  final Map<String, Map<String, Object?>> _incoming =
      <String, Map<String, Object?>>{};
  final Map<String, Map<String, Object?>> _outgoing =
      <String, Map<String, Object?>>{};
  final Map<String, StreamController<List<ConnectionRequestPayload>>>
  _incomingControllers =
      <String, StreamController<List<ConnectionRequestPayload>>>{};
  final Map<String, StreamController<List<ConnectionRequestPayload>>>
  _outgoingControllers =
      <String, StreamController<List<ConnectionRequestPayload>>>{};

  int _nextRequest = 0;
  Object? _nextFailure;
  bool _disposed = false;

  void failNextMutationForTest(Object error) {
    _nextFailure = error;
  }

  void seedIncomingRawForTest({
    required String username,
    required String requestId,
    required Object? value,
  }) {
    _ensureOpen();
    final normalizedUsername = normalizeConnectionRequestUsername(username);
    validateConnectionRequestId(requestId);
    _incoming.putIfAbsent(
      normalizedUsername,
      () => <String, Object?>{},
    )[requestId] = value;
    _emitIncoming(normalizedUsername);
  }

  List<ConnectionRequestPayload> incomingForTest(String username) {
    final normalizedUsername = normalizeConnectionRequestUsername(username);
    return _payloadsFor(
      _incoming,
      normalizedUsername,
      path: 'connectionRequests/$normalizedUsername',
    );
  }

  List<ConnectionRequestPayload> outgoingForTest(String username) {
    final normalizedUsername = normalizeConnectionRequestUsername(username);
    return _payloadsFor(
      _outgoing,
      normalizedUsername,
      path: 'connectionRequestOutboxes/$normalizedUsername',
    );
  }

  void dispose() {
    _disposed = true;
    for (final controller in _incomingControllers.values) {
      unawaited(controller.close());
    }
    for (final controller in _outgoingControllers.values) {
      unawaited(controller.close());
    }
    _incomingControllers.clear();
    _outgoingControllers.clear();
  }

  @override
  Future<ConnectionRequestDecision> createConnectionRequest(
    String peerId,
  ) async {
    _ensureOpen();
    final failure = _takeFailure();
    if (failure != null) {
      return backendRejectedConnectionRequestDecision(
        peerId: peerId,
        error: failure,
      );
    }

    final peer = normalizeConnectionRequestUsername(peerId);
    final existing = _findOpenOutgoing(peer);
    if (existing != null) {
      return ConnectionRequestDecision(
        allowed: false,
        reasonCode: ConnectionRequestReasonCode.duplicatePendingRequest,
        userMessage: messageForConnectionRequestReason(
          ConnectionRequestReasonCode.duplicatePendingRequest,
          peer,
        ),
        requestId: existing.requestId,
        status: existing.status,
        peerId: peer,
      );
    }

    final now = _clock();
    final requestId = validateConnectionRequestId(
      'cr_${now}_${_nextRequest++}',
    );
    final payload = ConnectionRequestPayload(
      requestId: requestId,
      from: _currentUsername,
      to: peer,
      pairKey: connectionRequestPairKey(_currentUsername, peer),
      status: ConnectionRequestStatus.pending,
      createdAt: now,
      updatedAt: now,
      expiresAt: now + const Duration(seconds: 45).inMilliseconds,
    );
    final json = payload.toJson();
    _incoming.putIfAbsent(peer, () => <String, Object?>{})[requestId] = json;
    _outgoing.putIfAbsent(
      _currentUsername,
      () => <String, Object?>{},
    )[requestId] = json;
    _emitIncoming(peer);
    _emitOutgoing(_currentUsername);
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: 'Connection request sent to @$peer.',
      requestId: requestId,
      status: ConnectionRequestStatus.pending,
      peerId: peer,
      quota: await fetchConnectionRequestQuota(),
    );
  }

  @override
  Future<ConnectionRequestDecision> cancelConnectionRequest(String requestId) {
    return _terminalAction(
      requestId: requestId,
      actorInbox: _outgoing,
      actorUsername: _currentUsername,
      status: ConnectionRequestStatus.canceled,
      successMessage: 'Connection request canceled.',
    );
  }

  @override
  Future<ConnectionRequestDecision> acceptConnectionRequest(String requestId) {
    return _terminalAction(
      requestId: requestId,
      actorInbox: _incoming,
      actorUsername: _currentUsername,
      status: ConnectionRequestStatus.accepted,
      successMessage: 'Connection request accepted.',
    );
  }

  @override
  Future<ConnectionRequestDecision> rejectConnectionRequest(String requestId) {
    return _terminalAction(
      requestId: requestId,
      actorInbox: _incoming,
      actorUsername: _currentUsername,
      status: ConnectionRequestStatus.rejected,
      successMessage: 'Connection request rejected.',
    );
  }

  @override
  Future<ConnectionRequestDecision> markConnectionRequestSeen(
    String requestId,
  ) async {
    _ensureOpen();
    final normalizedRequestId = validateConnectionRequestId(requestId);
    final payload = _payloadFromMap(_incoming[_currentUsername], requestId);
    if (payload == null) {
      return _staleDecision(normalizedRequestId);
    }
    if (payload.status.isTerminal) {
      return _terminalRaceDecision(payload);
    }
    if (payload.status == ConnectionRequestStatus.seen) {
      return ConnectionRequestDecision(
        allowed: true,
        userMessage: 'Connection request already seen.',
        requestId: payload.requestId,
        status: ConnectionRequestStatus.seen,
        peerId: payload.from,
      );
    }
    final now = _clock();
    final seen = _copyPayload(
      payload,
      status: ConnectionRequestStatus.seen,
      updatedAt: now,
      seenAt: now,
    );
    _putMirrors(seen);
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: 'Connection request marked seen.',
      requestId: seen.requestId,
      status: seen.status,
      peerId: seen.from,
    );
  }

  @override
  Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(
    String peerId,
  ) async {
    _ensureOpen();
    final peer = normalizeConnectionRequestUsername(peerId);
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: 'Muted connection requests from @$peer.',
      peerId: peer,
    );
  }

  @override
  Future<ConnectionRequestDecision> unmuteConnectionRequestsFromPeer(
    String peerId,
  ) async {
    _ensureOpen();
    final peer = normalizeConnectionRequestUsername(peerId);
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: 'Unmuted connection requests from @$peer.',
      peerId: peer,
    );
  }

  @override
  Future<ConnectionRequestQuotaSnapshot> fetchConnectionRequestQuota() async {
    _ensureOpen();
    return const ConnectionRequestQuotaSnapshot(
      dailyLimit: 20,
      usedToday: 0,
      extraCreditsRemaining: 0,
      perTargetRemainingToday: 3,
      pendingOutboundCount: 0,
      pendingInboundCount: 0,
    );
  }

  @override
  Stream<List<ConnectionRequestPayload>> watchIncomingConnectionRequests(
    String username,
  ) async* {
    _ensureOpen();
    final normalizedUsername = normalizeConnectionRequestUsername(username);
    yield _payloadsFor(
      _incoming,
      normalizedUsername,
      path: 'connectionRequests/$normalizedUsername',
    );
    yield* _controllerFor(_incomingControllers, normalizedUsername).stream;
  }

  @override
  Stream<List<ConnectionRequestPayload>> watchOutgoingConnectionRequests(
    String username,
  ) async* {
    _ensureOpen();
    final normalizedUsername = normalizeConnectionRequestUsername(username);
    yield _payloadsFor(
      _outgoing,
      normalizedUsername,
      path: 'connectionRequestOutboxes/$normalizedUsername',
    );
    yield* _controllerFor(_outgoingControllers, normalizedUsername).stream;
  }

  Future<ConnectionRequestDecision> _terminalAction({
    required String requestId,
    required Map<String, Map<String, Object?>> actorInbox,
    required String actorUsername,
    required ConnectionRequestStatus status,
    required String successMessage,
  }) async {
    _ensureOpen();
    final normalizedRequestId = validateConnectionRequestId(requestId);
    final payload = _payloadFromMap(actorInbox[actorUsername], requestId);
    if (payload == null) {
      return _staleDecision(normalizedRequestId);
    }
    if (payload.status.isTerminal) {
      return _terminalRaceDecision(payload);
    }
    final now = _clock();
    if (!canTransition(payload.status, status, now, payload.expiresAt)) {
      final expired = _copyPayload(
        payload,
        status: ConnectionRequestStatus.expired,
        updatedAt: now,
        respondedAt: now,
      );
      _putMirrors(expired);
      return ConnectionRequestDecision(
        allowed: false,
        reasonCode: ConnectionRequestReasonCode.expired,
        userMessage: messageForConnectionRequestReason(
          ConnectionRequestReasonCode.expired,
          payload.from == _currentUsername ? payload.to : payload.from,
        ),
        requestId: payload.requestId,
        status: ConnectionRequestStatus.expired,
        peerId: payload.from == _currentUsername ? payload.to : payload.from,
      );
    }
    final terminal = _copyPayload(
      payload,
      status: status,
      updatedAt: now,
      respondedAt: now,
    );
    _putMirrors(terminal);
    return ConnectionRequestDecision(
      allowed: true,
      userMessage: successMessage,
      requestId: terminal.requestId,
      status: terminal.status,
      peerId: terminal.from == _currentUsername ? terminal.to : terminal.from,
    );
  }

  ConnectionRequestPayload? _findOpenOutgoing(String peer) {
    for (final payload in outgoingForTest(_currentUsername)) {
      if (payload.to == peer &&
          !payload.status.isTerminal &&
          !payload.isExpiredAt(_clock())) {
        return payload;
      }
    }
    return null;
  }

  void _putMirrors(ConnectionRequestPayload payload) {
    final json = payload.toJson();
    _incoming.putIfAbsent(
      payload.to,
      () => <String, Object?>{},
    )[payload.requestId] = json;
    _outgoing.putIfAbsent(
      payload.from,
      () => <String, Object?>{},
    )[payload.requestId] = json;
    _emitIncoming(payload.to);
    _emitOutgoing(payload.from);
  }

  ConnectionRequestPayload? _payloadFromMap(
    Map<String, Object?>? values,
    String requestId,
  ) {
    final normalizedRequestId = validateConnectionRequestId(requestId);
    final value = values == null ? null : values[normalizedRequestId];
    if (value is! Map) {
      return null;
    }
    try {
      return ConnectionRequestPayload.fromJson(
        requestId: normalizedRequestId,
        json: connectionRequestObjectMap(value),
      );
    } on FormatException {
      return null;
    }
  }

  List<ConnectionRequestPayload> _payloadsFor(
    Map<String, Map<String, Object?>> source,
    String username, {
    required String path,
  }) {
    final values = source[username];
    if (values == null) {
      return const <ConnectionRequestPayload>[];
    }
    final payloads = <ConnectionRequestPayload>[];
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is! Map) {
        _emitDiagnostic(
          ConnectionRequestAdapterDiagnosticEvent(
            name: 'corrupt_connection_request_row_ignored',
            path: path,
            requestId: entry.key,
            error: 'row is not a map',
          ),
        );
        continue;
      }
      try {
        payloads.add(
          ConnectionRequestPayload.fromJson(
            requestId: entry.key,
            json: connectionRequestObjectMap(value),
          ),
        );
      } on FormatException catch (error) {
        _emitDiagnostic(
          ConnectionRequestAdapterDiagnosticEvent(
            name: 'corrupt_connection_request_row_ignored',
            path: path,
            requestId: entry.key,
            error: error,
          ),
        );
        continue;
      }
    }
    payloads.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List<ConnectionRequestPayload>.unmodifiable(payloads);
  }

  ConnectionRequestPayload _copyPayload(
    ConnectionRequestPayload payload, {
    required ConnectionRequestStatus status,
    required int updatedAt,
    int? seenAt,
    int? respondedAt,
  }) {
    return ConnectionRequestPayload(
      requestId: payload.requestId,
      from: payload.from,
      to: payload.to,
      pairKey: payload.pairKey,
      status: status,
      reasonCode: payload.reasonCode,
      createdAt: payload.createdAt,
      updatedAt: updatedAt,
      expiresAt: payload.expiresAt,
      seenAt: seenAt ?? payload.seenAt,
      respondedAt: respondedAt ?? payload.respondedAt,
      senderPresenceAt: payload.senderPresenceAt,
      receiverPresenceAt: payload.receiverPresenceAt,
      v: payload.v,
    );
  }

  ConnectionRequestDecision _staleDecision(String requestId) {
    return ConnectionRequestDecision(
      allowed: false,
      reasonCode: ConnectionRequestReasonCode.staleRequest,
      userMessage: messageForConnectionRequestReason(
        ConnectionRequestReasonCode.staleRequest,
        'Peer',
      ),
      requestId: requestId,
    );
  }

  ConnectionRequestDecision _terminalRaceDecision(
    ConnectionRequestPayload payload,
  ) {
    return ConnectionRequestDecision(
      allowed: false,
      reasonCode: ConnectionRequestReasonCode.terminalRaceLost,
      userMessage: messageForConnectionRequestReason(
        ConnectionRequestReasonCode.terminalRaceLost,
        payload.from == _currentUsername ? payload.to : payload.from,
      ),
      requestId: payload.requestId,
      status: payload.status,
      peerId: payload.from == _currentUsername ? payload.to : payload.from,
    );
  }

  StreamController<List<ConnectionRequestPayload>> _controllerFor(
    Map<String, StreamController<List<ConnectionRequestPayload>>> controllers,
    String username,
  ) {
    return controllers.putIfAbsent(
      username,
      () => StreamController<List<ConnectionRequestPayload>>.broadcast(),
    );
  }

  void _emitIncoming(String username) {
    final controller = _incomingControllers[username];
    if (controller != null && !controller.isClosed) {
      controller.add(
        _payloadsFor(_incoming, username, path: 'connectionRequests/$username'),
      );
    }
  }

  void _emitOutgoing(String username) {
    final controller = _outgoingControllers[username];
    if (controller != null && !controller.isClosed) {
      controller.add(
        _payloadsFor(
          _outgoing,
          username,
          path: 'connectionRequestOutboxes/$username',
        ),
      );
    }
  }

  void _emitDiagnostic(ConnectionRequestAdapterDiagnosticEvent event) {
    _diagnosticsSink?.call(event);
  }

  Object? _takeFailure() {
    final failure = _nextFailure;
    _nextFailure = null;
    return failure;
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('FakeConnectionRequestAdapter has been disposed.');
    }
  }
}
