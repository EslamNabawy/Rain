import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CallRetryPolicy evidence lock', () {
    test(
      'maps active user lock conflict to peer busy only when lock is live',
      () {
        fail(
          'Phase 03 must classify a live activeVoiceUsers conflict as '
          'CallRetryDecisionKind.peerBusy and show '
          '"@eslam is busy in another call.".',
        );
      },
      skip: 'Phase 03 adds CallRetryPolicy.',
    );

    test(
      'maps corrupt terminal room cleanup to retryable cleanup message',
      () {
        fail(
          'Phase 03 must classify repaired corrupt terminal call state as '
          'CallRetryDecisionKind.cleanedStaleState and show '
          '"Old call state was cleaned. Try again.".',
        );
      },
      skip: 'Phase 03 adds CallRetryPolicy.',
    );
  });
}
