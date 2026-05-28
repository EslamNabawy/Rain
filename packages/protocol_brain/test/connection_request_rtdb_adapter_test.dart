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
  }) : acceptedPeers = acceptedPeers ?? const <String>{},
       onlinePeers = onlinePeers ?? const <String>{} {
    adapter = RtdbOnlyConnectionRequestAdapter.forTest(
      currentUsername: () async => username,
      isAcceptedFriend: (String peerId) async =>
          this.acceptedPeers.contains(peerId),
      isPeerOnline: (String peerId) async => this.onlinePeers.contains(peerId),
      watchValue: _watchValue,
      getValue: (String path) async => _values[path],
      diagnosticsSink: diagnostics.add,
      clock: () => DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  final String username;
  final int now;
  final Set<String> acceptedPeers;
  final Set<String> onlinePeers;
  final List<ConnectionRequestAdapterDiagnosticEvent> diagnostics =
      <ConnectionRequestAdapterDiagnosticEvent>[];
  final Map<String, Object?> _values = <String, Object?>{};
  final Map<String, StreamController<Object?>> _controllers =
      <String, StreamController<Object?>>{};

  late final RtdbOnlyConnectionRequestAdapter adapter;

  void setValue(String path, Object? value) {
    _values[path] = value;
    final controller = _controllers[path];
    if (controller != null && !controller.isClosed) {
      controller.add(value);
    }
  }

  Stream<Object?> _watchValue(String path) {
    final controller = _controllers.putIfAbsent(
      path,
      () => StreamController<Object?>.broadcast(),
    );
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(_values[path]);
      }
    });
    return controller.stream;
  }

  Future<void> dispose() async {
    await Future.wait<void>(
      _controllers.values.map(
        (StreamController<Object?> controller) => controller.close(),
      ),
    );
  }
}
