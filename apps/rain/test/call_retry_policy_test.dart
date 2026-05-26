import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/call_retry_policy.dart';

void main() {
  group('CallRetryPolicy evidence lock', () {
    test(
      'maps active user lock conflict to peer busy only when lock is live',
      () {
        final live = CallRetryPolicy.classifySignalingFailure(
          const CallSignalingFailureSnapshot(
            message: 'Active voice call already exists for user eslam.',
            lockWasReclaimed: false,
            terminalRoomWasCleaned: false,
            corruptRoomWasRepaired: false,
            peerId: 'eslam',
          ),
        );
        final reclaimed = CallRetryPolicy.classifySignalingFailure(
          const CallSignalingFailureSnapshot(
            message: 'Active voice call already exists for user eslam.',
            lockWasReclaimed: true,
            terminalRoomWasCleaned: false,
            corruptRoomWasRepaired: false,
            peerId: 'eslam',
          ),
        );

        expect(live.kind, CallRetryDecisionKind.peerBusy);
        expect(live.userMessage, '@eslam is busy in another call.');
        expect(live.canRetryImmediately, isFalse);
        expect(reclaimed.kind, CallRetryDecisionKind.cleanedStaleState);
        expect(reclaimed.userMessage, 'Old call state was cleaned. Try again.');
        expect(reclaimed.canRetryImmediately, isTrue);
      },
    );

    test('maps corrupt terminal room cleanup to retryable cleanup message', () {
      final decision = CallRetryPolicy.classifySignalingFailure(
        const CallSignalingFailureSnapshot(
          message: 'Call room timestamps are invalid.',
          lockWasReclaimed: false,
          terminalRoomWasCleaned: true,
          corruptRoomWasRepaired: true,
          peerId: 'bob',
        ),
      );

      expect(decision.kind, CallRetryDecisionKind.cleanedStaleState);
      expect(decision.userMessage, 'Old call state was cleaned. Try again.');
      expect(decision.canRetryImmediately, isTrue);
    });

    test('maps cleanup in progress to a non-retry-spam message', () {
      final decision = CallRetryPolicy.classifySignalingFailure(
        const CallSignalingFailureSnapshot(
          message: 'Voice call cleanup in progress.',
          lockWasReclaimed: false,
          terminalRoomWasCleaned: false,
          corruptRoomWasRepaired: false,
          cleanupInProgress: true,
          peerId: 'bob',
        ),
      );

      expect(decision.kind, CallRetryDecisionKind.cleanupInProgress);
      expect(
        decision.userMessage,
        'Call state is cleaning up. Try again in a moment.',
      );
      expect(decision.canRetryImmediately, isFalse);
    });

    test('maps offline signaling failures without claiming peer busy', () {
      final decision = CallRetryPolicy.classifySignalingFailure(
        const CallSignalingFailureSnapshot(
          message: '@bob is offline. Keep both apps open, then try again.',
          lockWasReclaimed: false,
          terminalRoomWasCleaned: false,
          corruptRoomWasRepaired: false,
          peerId: 'bob',
        ),
      );

      expect(decision.kind, CallRetryDecisionKind.peerOffline);
      expect(
        decision.userMessage,
        '@bob is offline. Keep both apps open, then try again.',
      );
      expect(decision.canRetryImmediately, isFalse);
    });

    test('maps presence confirmation failures without claiming peer busy', () {
      final decision = CallRetryPolicy.classifySignalingFailure(
        const CallSignalingFailureSnapshot(
          message: 'Could not confirm @bob is online. Try again.',
          lockWasReclaimed: false,
          terminalRoomWasCleaned: false,
          corruptRoomWasRepaired: false,
          peerId: 'bob',
        ),
      );

      expect(decision.kind, CallRetryDecisionKind.peerOffline);
      expect(
        decision.userMessage,
        'Could not confirm @bob is online. Try again.',
      );
      expect(decision.canRetryImmediately, isFalse);
    });

    test('maps generic signaling failures without claiming peer busy', () {
      final decision = CallRetryPolicy.classifySignalingFailure(
        const CallSignalingFailureSnapshot(
          message: 'Firebase permission-denied at voiceCalls/call-1',
          lockWasReclaimed: false,
          terminalRoomWasCleaned: false,
          corruptRoomWasRepaired: false,
          peerId: 'bob',
        ),
      );

      expect(decision.kind, CallRetryDecisionKind.signalingFailed);
      expect(decision.userMessage, 'Call signaling failed. Try again.');
      expect(decision.canRetryImmediately, isFalse);
    });
  });
}
