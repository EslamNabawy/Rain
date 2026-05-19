import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/connection_command/connection_command_models.dart';
import 'package:rain/application/connection_command/connection_command_orchestrator.dart';
import 'package:rain/application/connection_command/fake_connection_transport.dart';
import 'package:rain/application/connection_command/connection_run_token.dart';

void main() {
  group('ConnectionRunToken', () {
    test('starts active and records cancel reason', () {
      final token = ConnectionRunToken(
        peerId: 'bob',
        runId: 'run-1',
        generation: 1,
        startedAt: 100,
      );

      expect(token.isCanceled, isFalse);
      expect(token.cancelReason, isNull);

      token.cancel(ConnectionCancelReason.userCanceled);

      expect(token.isCanceled, isTrue);
      expect(token.cancelReason, ConnectionCancelReason.userCanceled);
    });

    test('matches only the current peer, run, and generation while active', () {
      final token = ConnectionRunToken(
        peerId: 'bob',
        runId: 'run-1',
        generation: 2,
        startedAt: 100,
      );

      expect(token.isActiveFor('bob', 'run-1', 2), isTrue);
      expect(token.isActiveFor('alice', 'run-1', 2), isFalse);
      expect(token.isActiveFor('bob', 'run-2', 2), isFalse);
      expect(token.isActiveFor('bob', 'run-1', 3), isFalse);

      token.cancel(ConnectionCancelReason.supersededAttempt);

      expect(token.isActiveFor('bob', 'run-1', 2), isFalse);
    });

    test('guarded callbacks drop events after cancellation', () {
      final token = ConnectionRunToken(
        peerId: 'bob',
        runId: 'run-1',
        generation: 1,
        startedAt: 100,
      );
      final dispatched = <String>[];

      void guardedDispatch(String event) {
        if (!token.isActiveFor('bob', 'run-1', 1)) {
          return;
        }
        dispatched.add(event);
      }

      guardedDispatch('ice-before-cancel');
      token.cancel(ConnectionCancelReason.userCanceled);
      guardedDispatch('ice-after-cancel');

      expect(dispatched, <String>['ice-before-cancel']);
    });

    test('new attempts use a fresh token and generation', () {
      final oldToken = ConnectionRunToken(
        peerId: 'bob',
        runId: 'run-1',
        generation: 1,
        startedAt: 100,
      )..cancel(ConnectionCancelReason.supersededAttempt);
      final newToken = ConnectionRunToken(
        peerId: 'bob',
        runId: 'run-2',
        generation: 2,
        startedAt: 200,
      );

      expect(oldToken.isCanceled, isTrue);
      expect(newToken.isCanceled, isFalse);
      expect(oldToken.isActiveFor('bob', 'run-2', 2), isFalse);
      expect(newToken.isActiveFor('bob', 'run-2', 2), isTrue);
    });

    test('throwIfCanceled reports the cancel reason', () {
      final token = ConnectionRunToken(
        peerId: 'bob',
        runId: 'run-1',
        generation: 1,
        startedAt: 100,
      )..cancel(ConnectionCancelReason.networkLost);

      expect(
        token.throwIfCanceled,
        throwsA(
          isA<ConnectionRunCanceledException>().having(
            (error) => error.reason,
            'reason',
            ConnectionCancelReason.networkLost,
          ),
        ),
      );
    });
  });

  group('ConnectionCommandOrchestrator cancellation', () {
    test('cancel waits for transport disposal before emitting canceled', () async {
      final cancelCompleter = Completer<void>();
      final transport = FakeConnectionTransport.hanging(
        cancelCompleter: cancelCompleter,
      );
      final orchestrator = ConnectionCommandOrchestrator(
        transport: transport,
        runIdFactory: () => 'run-1',
      );
      addTearDown(orchestrator.dispose);

      await orchestrator.connect('bob');
      final cancelFuture = orchestrator.cancel('bob');
      await Future<void>.delayed(Duration.zero);

      expect(transport.cancelCalls, <ConnectionLayer>[ConnectionLayer.preflight]);
      expect(
        orchestrator.currentTimeline('bob')!.steps.last.state,
        isNot(ConnectionStepState.canceled),
      );

      cancelCompleter.complete();
      await cancelFuture;

      final timeline = orchestrator.currentTimeline('bob')!;
      expect(timeline.canCancel, isFalse);
      expect(timeline.steps.last.state, ConnectionStepState.canceled);
      expect(
        timeline.steps.last.failureCode,
        ConnectionFailureCode.userCanceled,
      );
    });

    test('new connect after cancel uses a fresh run', () async {
      final transport = FakeConnectionTransport.hanging();
      var nextRun = 0;
      final orchestrator = ConnectionCommandOrchestrator(
        transport: transport,
        runIdFactory: () => 'run-${nextRun += 1}',
      );
      addTearDown(orchestrator.dispose);

      await orchestrator.connect('bob');
      await orchestrator.cancel('bob');
      await orchestrator.connect('bob');

      expect(orchestrator.currentTimeline('bob')!.attemptId, 'run-2');
    });
  });
}
