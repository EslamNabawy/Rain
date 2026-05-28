import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  group('RtdbOnlyConnectionRequestAdapter', () {
    test('rtdbOnly adapter starts empty', () async {
      final harness = _RtdbOnlyAdapterHarness(username: 'alice');
      addTearDown(harness.dispose);

      expect(
        await harness.adapter
            .watchIncomingConnectionRequests('alice')
            .first
            .timeout(const Duration(seconds: 1)),
        isEmpty,
      );
    });

    test('rtdbOnly quota summary uses best effort defaults', () async {
      final harness = _RtdbOnlyAdapterHarness(username: 'alice');
      addTearDown(harness.dispose);

      final quota = await harness.adapter.fetchConnectionRequestQuota();

      expect(quota.dailyLimit, greaterThan(0));
      expect(quota.perTargetRemainingToday, greaterThan(0));
      expect(quota.disabled, isFalse);
    });

    test('watcher parses payloads and reports corrupt rows', () async {
      final harness = _RtdbOnlyAdapterHarness(username: 'alice');
      addTearDown(harness.dispose);
      harness.setValue('connectionRequests/alice', <String, Object?>{
        'bad-row': 'not-a-map',
        'request-01': _payload(
          requestId: 'request-01',
          from: 'bob',
          to: 'alice',
        ).toJson(),
      });

      final payloads = await harness.adapter
          .watchIncomingConnectionRequests('alice')
          .first
          .timeout(const Duration(seconds: 1));

      expect(payloads, hasLength(1));
      expect(payloads.single.requestId, 'request-01');
      expect(payloads.single.from, 'bob');
      expect(
        harness.diagnostics.map((event) => event.name),
        contains('corrupt_connection_request_row_ignored'),
      );
    });

    test('quota counts pending inbound and outbound rows', () async {
      final harness = _RtdbOnlyAdapterHarness(username: 'alice', now: 1000);
      addTearDown(harness.dispose);
      harness.setValue('connectionRequests/alice', <String, Object?>{
        'request-01': _payload(
          requestId: 'request-01',
          from: 'bob',
          to: 'alice',
        ).toJson(),
      });
      harness.setValue('connectionRequestOutboxes/alice', <String, Object?>{
        'request-02': _payload(
          requestId: 'request-02',
          from: 'alice',
          to: 'cara',
        ).toJson(),
      });

      final quota = await harness.adapter.fetchConnectionRequestQuota();

      expect(quota.pendingInboundCount, 1);
      expect(quota.pendingOutboundCount, 1);
    });

    test(
      'create preflight denies offline peer before foundation fallback',
      () async {
        final harness = _RtdbOnlyAdapterHarness(
          username: 'alice',
          acceptedPeers: <String>{'bob'},
        );
        addTearDown(harness.dispose);

        final decision = await harness.adapter.createConnectionRequest('bob');

        expect(decision.allowed, isFalse);
        expect(decision.reasonCode, ConnectionRequestReasonCode.peerOffline);
        expect(decision.userMessage, contains('@bob is offline'));
      },
    );

    test('create writes receiver inbox and sender outbox', () async {
      final harness = _RtdbOnlyAdapterHarness(
        username: 'alice',
        acceptedPeers: <String>{'bob'},
        onlinePeers: <String>{'bob'},
        randomSuffixes: <String>['a1b2'],
      );
      addTearDown(harness.dispose);

      final decision = await harness.adapter.createConnectionRequest('bob');
      final requestId = createConnectionRequestId(
        from: 'alice',
        to: 'bob',
        now: 1000,
        randomSuffix: 'a1b2',
      );

      expect(decision.allowed, isTrue);
      expect(decision.requestId, requestId);
      expect(decision.status, ConnectionRequestStatus.pending);
      expect(
        harness.valueAt('connectionRequests/bob/$requestId/requestId'),
        requestId,
      );
      expect(
        harness.valueAt('connectionRequestOutboxes/alice/$requestId/from'),
        'alice',
      );
      expect(
        harness.valueAt('connectionRequestPairLocks/alice:bob/requestId'),
        requestId,
      );
    });

    test('create duplicate returns existing pending decision', () async {
      final harness = _RtdbOnlyAdapterHarness(
        username: 'alice',
        acceptedPeers: <String>{'bob'},
        onlinePeers: <String>{'bob'},
        randomSuffixes: <String>['a1b2', 'c3d4'],
      );
      addTearDown(harness.dispose);

      final first = await harness.adapter.createConnectionRequest('bob');
      final second = await harness.adapter.createConnectionRequest('bob');

      expect(first.allowed, isTrue);
      expect(second.allowed, isFalse);
      expect(
        second.reasonCode,
        ConnectionRequestReasonCode.duplicatePendingRequest,
      );
      expect(second.requestId, first.requestId);
      expect(
        harness.valueAt('connectionRequestOutboxes/alice') as Map,
        hasLength(1),
      );
    });

    test('create denied for offline peer writes no request rows', () async {
      final harness = _RtdbOnlyAdapterHarness(
        username: 'alice',
        acceptedPeers: <String>{'bob'},
      );
      addTearDown(harness.dispose);

      final decision = await harness.adapter.createConnectionRequest('bob');

      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ConnectionRequestReasonCode.peerOffline);
      expect(harness.valueAt('connectionRequests/bob'), isNull);
      expect(harness.valueAt('connectionRequestOutboxes/alice'), isNull);
      expect(harness.valueAt('connectionRequestPairLocks/alice:bob'), isNull);
    });

    test('create mirror failure attempts matching lock rollback', () async {
      final harness = _RtdbOnlyAdapterHarness(
        username: 'alice',
        acceptedPeers: <String>{'bob'},
        onlinePeers: <String>{'bob'},
        randomSuffixes: <String>['a1b2'],
      )..failNextUpdateForTest(Exception('permission denied'));
      addTearDown(harness.dispose);

      final decision = await harness.adapter.createConnectionRequest('bob');

      expect(decision.allowed, isFalse);
      expect(
        decision.reasonCode,
        ConnectionRequestReasonCode.backendUnavailable,
      );
      expect(decision.diagnostics['rollbackPairLock'], isTrue);
      expect(harness.valueAt('connectionRequestPairLocks/alice:bob'), isNull);
      expect(harness.valueAt('connectionRequests/bob'), isNull);
      expect(harness.valueAt('connectionRequestOutboxes/alice'), isNull);
    });
  });
}

ConnectionRequestPayload _payload({
  required String requestId,
  required String from,
  required String to,
}) {
  return ConnectionRequestPayload(
    requestId: requestId,
    from: from,
    to: to,
    pairKey: connectionRequestPairKey(from, to),
    status: ConnectionRequestStatus.pending,
    createdAt: 1000,
    updatedAt: 1000,
    expiresAt: 45000,
  );
}

final class _RtdbOnlyAdapterHarness {
  _RtdbOnlyAdapterHarness({
    required this.username,
    this.now = 1000,
    Set<String>? acceptedPeers,
    Set<String>? onlinePeers,
    List<String>? randomSuffixes,
  }) : acceptedPeers = acceptedPeers ?? const <String>{},
       onlinePeers = onlinePeers ?? const <String>{},
       _randomSuffixes = randomSuffixes ?? const <String>[] {
    adapter = RtdbOnlyConnectionRequestAdapter.forTest(
      currentUsername: () async => username,
      isAcceptedFriend: (String peerId) async =>
          this.acceptedPeers.contains(peerId),
      isPeerOnline: (String peerId) async => this.onlinePeers.contains(peerId),
      watchValue: _watchValue,
      getValue: (String path) async => valueAt(path),
      updateValue: _updateValue,
      runTransaction: _runTransaction,
      randomSuffix: _nextRandomSuffix,
      diagnosticsSink: diagnostics.add,
      clock: () => DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  final String username;
  final int now;
  final Set<String> acceptedPeers;
  final Set<String> onlinePeers;
  final List<String> _randomSuffixes;
  final List<ConnectionRequestAdapterDiagnosticEvent> diagnostics =
      <ConnectionRequestAdapterDiagnosticEvent>[];
  final Map<String, Object?> _values = <String, Object?>{};
  final Map<String, StreamController<Object?>> _controllers =
      <String, StreamController<Object?>>{};
  var _randomSuffixIndex = 0;
  Object? _nextUpdateFailure;

  late final RtdbOnlyConnectionRequestAdapter adapter;

  Object? valueAt(String path) {
    if (path.isEmpty) {
      return _values;
    }
    Object? cursor = _values;
    for (final segment in path.split('/')) {
      if (cursor is! Map) {
        return null;
      }
      cursor = cursor[segment];
    }
    return cursor;
  }

  void setValue(String path, Object? value) {
    _setValue(path, value);
    _emitPathAndParents(path);
  }

  void failNextUpdateForTest(Object error) {
    _nextUpdateFailure = error;
  }

  Future<void> _updateValue(Map<String, Object?> updates) async {
    final failure = _nextUpdateFailure;
    if (failure != null) {
      _nextUpdateFailure = null;
      throw failure;
    }
    for (final entry in updates.entries) {
      _setValue(entry.key, entry.value);
    }
    for (final path in updates.keys) {
      _emitPathAndParents(path);
    }
  }

  Future<RtdbOnlyConnectionRequestTransactionResult> _runTransaction(
    String path,
    RtdbOnlyConnectionRequestTransactionHandler handler,
  ) async {
    final current = valueAt(path);
    final action = handler(current);
    if (action.aborted) {
      return RtdbOnlyConnectionRequestTransactionResult(
        committed: false,
        value: current,
      );
    }
    _setValue(path, action.value);
    _emitPathAndParents(path);
    return RtdbOnlyConnectionRequestTransactionResult(
      committed: true,
      value: action.value,
    );
  }

  Stream<Object?> _watchValue(String path) {
    final controller = _controllers.putIfAbsent(
      path,
      () => StreamController<Object?>.broadcast(),
    );
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(valueAt(path));
      }
    });
    return controller.stream;
  }

  void _setValue(String path, Object? value) {
    final segments = path.split('/');
    Map<String, Object?> cursor = _values;
    for (final segment in segments.take(segments.length - 1)) {
      final child = cursor[segment];
      if (child is Map<String, Object?>) {
        cursor = child;
      } else if (child is Map) {
        final normalized = Map<String, Object?>.from(child);
        cursor[segment] = normalized;
        cursor = normalized;
      } else {
        final next = <String, Object?>{};
        cursor[segment] = next;
        cursor = next;
      }
    }
    final leaf = segments.last;
    if (value == null) {
      cursor.remove(leaf);
    } else {
      cursor[leaf] = value;
    }
  }

  void _emitPathAndParents(String path) {
    var current = path;
    while (current.isNotEmpty) {
      final controller = _controllers[current];
      if (controller != null && !controller.isClosed) {
        controller.add(valueAt(current));
      }
      final lastSlash = current.lastIndexOf('/');
      if (lastSlash < 0) {
        break;
      }
      current = current.substring(0, lastSlash);
    }
  }

  String _nextRandomSuffix() {
    if (_randomSuffixIndex < _randomSuffixes.length) {
      return _randomSuffixes[_randomSuffixIndex++];
    }
    return 'test${_randomSuffixIndex++}';
  }

  Future<void> dispose() async {
    await Future.wait<void>(
      _controllers.values.map(
        (StreamController<Object?> controller) => controller.close(),
      ),
    );
  }
}
