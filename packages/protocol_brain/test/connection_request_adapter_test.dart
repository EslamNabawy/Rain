import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  group('ConnectionRequestAdapter', () {
    test('fake adapter mirrors status to inbox and outbox', () async {
      var now = 1000;
      final adapter = FakeConnectionRequestAdapter(
        currentUsername: 'alice',
        clock: () => now,
      );
      addTearDown(adapter.dispose);

      final created = await adapter.createConnectionRequest('bob');

      expect(created.allowed, isTrue);
      expect(created.requestId, isNotNull);
      expect(adapter.incomingForTest('bob'), hasLength(1));
      expect(adapter.outgoingForTest('alice'), hasLength(1));
      expect(
        adapter.incomingForTest('bob').single.status,
        ConnectionRequestStatus.pending,
      );

      now = 1200;
      final canceled = await adapter.cancelConnectionRequest(
        created.requestId!,
      );

      expect(canceled.allowed, isTrue);
      expect(canceled.status, ConnectionRequestStatus.canceled);
      expect(
        adapter.incomingForTest('bob').single.status,
        ConnectionRequestStatus.canceled,
      );
      expect(
        adapter.outgoingForTest('alice').single.status,
        ConnectionRequestStatus.canceled,
      );
    });

    test('duplicate create returns the existing pending request', () async {
      final adapter = FakeConnectionRequestAdapter(
        currentUsername: 'alice',
        clock: () => 1000,
      );
      addTearDown(adapter.dispose);

      final first = await adapter.createConnectionRequest('bob');
      final second = await adapter.createConnectionRequest('bob');

      expect(first.allowed, isTrue);
      expect(second.allowed, isFalse);
      expect(
        second.reasonCode,
        ConnectionRequestReasonCode.duplicatePendingRequest,
      );
      expect(second.requestId, first.requestId);
      expect(adapter.outgoingForTest('alice'), hasLength(1));
    });

    test('stream ignores corrupt rows', () async {
      final diagnostics = <ConnectionRequestAdapterDiagnosticEvent>[];
      final adapter = FakeConnectionRequestAdapter(
        currentUsername: 'alice',
        clock: () => 1000,
        diagnosticsSink: diagnostics.add,
      );
      addTearDown(adapter.dispose);

      adapter.seedIncomingRawForTest(
        username: 'alice',
        requestId: 'bad-row',
        value: 'not-a-map',
      );
      adapter.seedIncomingRawForTest(
        username: 'alice',
        requestId: 'request-01',
        value: const ConnectionRequestPayload(
          requestId: 'request-01',
          from: 'bob',
          to: 'alice',
          pairKey: 'bob:alice',
          status: ConnectionRequestStatus.pending,
          createdAt: 1000,
          updatedAt: 1000,
          expiresAt: 45000,
        ).toJson(),
      );

      final payloads = await adapter
          .watchIncomingConnectionRequests('alice')
          .first;

      expect(payloads, hasLength(1));
      expect(payloads.single.requestId, 'request-01');
      expect(payloads.single.from, 'bob');
      expect(diagnostics, isNotEmpty);
      expect(
        diagnostics.map((event) => event.name),
        contains('corrupt_connection_request_row_ignored'),
      );
    });

    test('network failure returns safe message and raw diagnostics', () async {
      final adapter = FakeConnectionRequestAdapter(
        currentUsername: 'alice',
        clock: () => 1000,
      );
      addTearDown(adapter.dispose);
      adapter.failNextMutationForTest(Exception('socket exploded'));

      final decision = await adapter.createConnectionRequest('bob');

      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ConnectionRequestReasonCode.backendRejected);
      expect(decision.userMessage, isNot(contains('socket exploded')));
      expect(decision.diagnostics['error'], contains('socket exploded'));
    });

    test('function response parser supports backend quota shape', () {
      final decision = connectionRequestDecisionFromFunctionJson(
        <Object?, Object?>{
          'allowed': false,
          'reasonCode': 'rateLimited',
          'retryAfterMs': 12000,
          'requestId': 'request-01',
          'status': 'pending',
          'to': 'bob',
          'quota': <Object?, Object?>{
            'dailyFreeLimit': 20,
            'freeUsed': 4,
            'extraCreditsRemaining': 2,
            'perTargetDailyLimit': 3,
            'perTargetUsed': 1,
            'pendingOutboundCount': 2,
            'pendingInboundCount': 1,
          },
          'diagnostics': <Object?, Object?>{
            'action': 'createConnectionRequest',
          },
        },
      );

      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, ConnectionRequestReasonCode.rateLimited);
      expect(decision.status, ConnectionRequestStatus.pending);
      expect(decision.peerId, 'bob');
      expect(decision.quota!.dailyLimit, 20);
      expect(decision.quota!.usedToday, 4);
      expect(decision.quota!.perTargetRemainingToday, 2);
      expect(decision.diagnostics['action'], 'createConnectionRequest');
    });
  });
}
