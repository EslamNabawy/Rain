import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/presentation/widgets/calls/rain_call_ended_surface.dart';

void main() {
  testWidgets('ended-call surface shows call details and actions', (
    WidgetTester tester,
  ) async {
    var closed = false;
    var calledAgain = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainCallEndedSurface(
            summary: CallEndSummary(
              peerId: 'bob',
              peerLabel: 'Bob',
              mediaMode: CallMediaMode.audio,
              duration: const Duration(minutes: 1, seconds: 8),
              initiator: CallEndInitiator.remote,
              reason: 'Peer ended the call.',
              endedAt: DateTime(2026, 5, 26),
            ),
            onClose: () => closed = true,
            onCallAgain: () => calledAgain = true,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-ended-popup-surface')),
      findsOneWidget,
    );
    expect(find.text('Voice call ended'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Ended by Bob'), findsOneWidget);
    expect(find.text('Peer ended the call.'), findsOneWidget);

    await tester.tap(find.text('Close'));
    expect(closed, isTrue);

    await tester.tap(find.text('Call again'));
    expect(calledAgain, isTrue);
  });

  testWidgets('ended-call fullscreen surface owns the whole call area', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainCallEndedSurface(
            fullscreen: true,
            summary: CallEndSummary(
              peerId: 'bob',
              peerLabel: 'Bob',
              mediaMode: CallMediaMode.video,
              duration: const Duration(seconds: 3),
              initiator: CallEndInitiator.local,
              reason: 'Call ended.',
              endedAt: DateTime(2026, 5, 26),
            ),
            onClose: () {},
            onCallAgain: () {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('rain-call-ended-fullscreen-surface')),
      findsOneWidget,
    );
    expect(find.text('Video call ended'), findsOneWidget);
    expect(find.text('Ended by you'), findsOneWidget);
  });
}
