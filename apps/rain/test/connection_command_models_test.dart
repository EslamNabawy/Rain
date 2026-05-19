import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/connection_command/connection_failure_messages.dart';
import 'package:rain/application/connection_command/connection_command_models.dart';
import 'package:rain/application/connection_command/connection_timeouts.dart';

void main() {
  group('ConnectionPolicy', () {
    test('defaults to auto with one fallback prompt and no persistence', () {
      const policy = ConnectionPolicy.defaults();

      expect(policy.mode, ConnectionMode.auto);
      expect(policy.askBeforeFallback, isTrue);
      expect(policy.rememberForSession, isFalse);
    });
  });

  group('ConnectionTimeline', () {
    test('adding a step returns a new timeline instance', () {
      final timeline = ConnectionTimeline.initial(
        peerId: 'bob',
        attemptId: 'attempt-1',
        policy: const ConnectionPolicy.defaults(),
      );

      final updated = timeline.addStep(
        ConnectionAttemptStep.pending(
          layer: ConnectionLayer.preflight,
          userMessage: 'Checking peer.',
          startedAt: 10,
        ),
      );

      expect(updated, isNot(same(timeline)));
      expect(timeline.steps, isEmpty);
      expect(updated.steps, hasLength(1));
      expect(updated.steps.single.layer, ConnectionLayer.preflight);
    });

    test('visible steps are capped at 24 by dropping the oldest entry', () {
      final timeline = ConnectionTimeline.initial(
        peerId: 'bob',
        attemptId: 'attempt-1',
        policy: const ConnectionPolicy.defaults(),
      );

      var updated = timeline;
      for (var index = 0; index < 25; index += 1) {
        updated = updated.addStep(
          ConnectionAttemptStep.pending(
            layer: ConnectionLayer.webRtcDirect,
            userMessage: 'Step $index',
            startedAt: index,
          ),
        );
      }

      expect(updated.steps, hasLength(24));
      expect(updated.steps.first.userMessage, 'Step 1');
      expect(updated.steps.last.userMessage, 'Step 24');
      expect(updated.fullHistory, hasLength(25));
      expect(updated.fullHistory.first.userMessage, 'Step 0');
    });

    test('fallback prompt state is a one-way guard for a connect attempt', () {
      final timeline = ConnectionTimeline.initial(
        peerId: 'bob',
        attemptId: 'attempt-1',
        policy: const ConnectionPolicy.defaults(),
      );

      expect(timeline.shouldShowFallbackPrompt, isTrue);

      final prompted = timeline.markFallbackPromptShown();

      expect(prompted.fallbackPromptAlreadyShown, isTrue);
      expect(prompted.shouldShowFallbackPrompt, isFalse);
      expect(prompted, isNot(same(timeline)));
    });
  });

  group('ConnectionMode', () {
    test('iroh fallback has no force-direct or force-relay subtype', () {
      expect(ConnectionMode.irohFallback.isIroh, isTrue);
      expect(ConnectionMode.irohFallback.canForceIrohRoute, isFalse);
      expect(
        ConnectionMode.values.where((mode) => mode.name.startsWith('iroh')),
        <ConnectionMode>[ConnectionMode.irohFallback],
      );
    });
  });

  group('ConnectionTimeouts', () {
    test('keeps connection timing defaults in one place', () {
      expect(ConnectionTimeouts.webRtcDirect, const Duration(seconds: 12));
      expect(
        ConnectionTimeouts.webRtcPrimaryRelay,
        const Duration(seconds: 30),
      );
      expect(
        ConnectionTimeouts.webRtcBackupRelay,
        const Duration(seconds: 20),
      );
      expect(
        ConnectionTimeouts.webRtcFullRestart,
        const Duration(seconds: 25),
      );
      expect(ConnectionTimeouts.iroh, const Duration(seconds: 25));
      expect(ConnectionTimeouts.globalBudget, const Duration(seconds: 90));
      expect(
        ConnectionTimeouts.retryBaseDelay,
        const Duration(milliseconds: 1200),
      );
      expect(
        ConnectionTimeouts.retryMaxJitter,
        const Duration(milliseconds: 600),
      );
    });

    test('documents that layer timeout sum exceeds global budget', () {
      final layerSum =
          ConnectionTimeouts.webRtcDirect +
          ConnectionTimeouts.webRtcPrimaryRelay +
          ConnectionTimeouts.webRtcBackupRelay +
          ConnectionTimeouts.webRtcFullRestart +
          ConnectionTimeouts.iroh;

      expect(layerSum, const Duration(seconds: 112));
      expect(layerSum, greaterThan(ConnectionTimeouts.globalBudget));
    });
  });

  group('ConnectionFailureMessages', () {
    test('maps failure codes to stable user-facing messages', () {
      expect(
        ConnectionFailureMessages.userMessage(
          ConnectionFailureCode.directPathBlocked,
        ),
        'Direct path blocked.',
      );
      expect(
        ConnectionFailureMessages.userMessage(
          ConnectionFailureCode.turnCredentialsUnavailable,
        ),
        'Relay credentials unavailable.',
      );
      expect(
        ConnectionFailureMessages.userMessage(
          ConnectionFailureCode.turnProviderTimedOut,
        ),
        'Relay provider timed out.',
      );
      expect(
        ConnectionFailureMessages.userMessage(
          ConnectionFailureCode.dataChannelTimeout,
        ),
        'Data channel did not open.',
      );
      expect(
        ConnectionFailureMessages.userMessage(
          ConnectionFailureCode.irohAddressTimeout,
        ),
        'Iroh address exchange timed out.',
      );
      expect(
        ConnectionFailureMessages.userMessage(
          ConnectionFailureCode.irohHandshakeRejected,
        ),
        'Iroh handshake rejected.',
      );
      expect(
        ConnectionFailureMessages.userMessage(
          ConnectionFailureCode.globalBudgetExceeded,
        ),
        'All connection routes timed out.',
      );
      expect(
        ConnectionFailureMessages.userMessage(
          ConnectionFailureCode.userCanceled,
        ),
        'Connection canceled.',
      );
    });
  });
}
