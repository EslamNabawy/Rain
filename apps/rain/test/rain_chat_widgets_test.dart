import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';

void main() {
  testWidgets('RainLiveLinkBar renders link state and strength', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainLiveLinkBar(
            label: 'Linked',
            detail: 'Encrypted peer lane is open.',
            color: const Color(0xFF2DD4A3),
            icon: Icons.hub_outlined,
            strength: 3,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Linked'), findsOneWidget);
    expect(find.text('Encrypted peer lane is open.'), findsOneWidget);
    expect(_findMeterCells('rain-link-meter-on-'), findsNWidgets(3));
    expect(_findMeterCells('rain-link-meter-off-'), findsOneWidget);

    await tester.tap(find.text('Linked'));
    expect(tapped, isTrue);
  });

  testWidgets('RainAvatar uses first display-name letter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RainAvatar(name: 'nora voss', statusColor: Color(0xFF2DD4A3)),
        ),
      ),
    );

    expect(find.text('N'), findsOneWidget);
  });

  testWidgets('RainAvatar uses gender assets when gender is known', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              RainAvatar(name: 'Nora', gender: 'female'),
              RainAvatar(name: 'Omar', gender: 'male'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsNWidgets(2));
    for (final widget in tester.widgetList<SvgPicture>(
      find.byType(SvgPicture),
    )) {
      expect(widget.fit, BoxFit.contain);
    }
    expect(find.text('N'), findsNothing);
    expect(find.text('O'), findsNothing);
  });

  testWidgets('RainMessageBubble renders delivery state and retry action', (
    WidgetTester tester,
  ) async {
    var retryTapped = false;
    var actionsOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainMessageBubble(
            text: 'Peer lane dropped during send',
            timeLabel: '10:42',
            isOutgoing: true,
            startsCluster: true,
            endsCluster: true,
            maxWidth: 320,
            deliveryLabel: 'Failed',
            deliveryColor: const Color(0xFFFF6B6B),
            onRetry: () => retryTapped = true,
            onOpenActions: () => actionsOpened = true,
          ),
        ),
      ),
    );

    expect(find.text('Peer lane dropped during send'), findsOneWidget);
    expect(find.text('10:42'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Message actions'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retryTapped, isTrue);

    await tester.tap(find.byTooltip('Message actions'));
    expect(actionsOpened, isTrue);
  });

  testWidgets('RainMessageDayDivider labels grouped days', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RainMessageDayDivider(label: 'Today')),
      ),
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('RainComposerCommandStrip shows link action', (
    WidgetTester tester,
  ) async {
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainComposerCommandStrip(
            label: 'Ready',
            detail: 'Peer online; open link',
            color: const Color(0xFF7DD3FC),
            icon: Icons.wifi_tethering,
            actionLabel: 'Open',
            actionIcon: Icons.hub_outlined,
            onAction: () => opened = true,
          ),
        ),
      ),
    );

    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Peer online; open link'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);

    await tester.tap(find.text('Open'));
    expect(opened, isTrue);
  });

  testWidgets('voice call button disables during active transfer', (
    WidgetTester tester,
  ) async {
    var started = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallButton(
            peerId: 'bob',
            state: const VoiceCallState.idle(),
            canStart: false,
            hasActiveTransfer: true,
            onStart: () => started = true,
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(button.tooltip, 'Finish the active file transfer first.');
    await tester.tap(find.byType(IconButton));
    expect(started, isFalse);
  });

  testWidgets('voice call button disables during another call', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallButton(
            peerId: 'bob',
            state: const VoiceCallState(
              phase: VoiceCallPhase.active,
              peerId: 'alice',
              callId: 'call-1',
            ),
            canStart: false,
            hasActiveTransfer: false,
            onStart: () {},
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
    expect(button.tooltip, 'Finish the active call with @alice first.');
  });

  testWidgets('voice call incoming ring actions are wired', (
    WidgetTester tester,
  ) async {
    var accepted = false;
    var rejected = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: const VoiceCallState(
              phase: VoiceCallPhase.incomingRinging,
              peerId: 'bob',
              callId: 'call-1',
            ),
            displayName: 'Bob',
            onAccept: () => accepted = true,
            onReject: () => rejected = true,
            onHangUp: () {},
            onRetry: () {},
            onToggleMute: () {},
          ),
        ),
      ),
    );

    expect(find.text('Bob is calling'), findsOneWidget);
    expect(find.text('Incoming voice call.'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    expect(accepted, isTrue);

    await tester.tap(find.text('Reject'));
    expect(rejected, isTrue);
  });

  testWidgets('voice call active mute and hangup actions are wired', (
    WidgetTester tester,
  ) async {
    var muted = false;
    var hungUp = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: VoiceCallState(
              phase: VoiceCallPhase.active,
              peerId: 'bob',
              callId: 'call-1',
              startedAt: DateTime.now()
                  .subtract(const Duration(seconds: 7))
                  .millisecondsSinceEpoch,
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () => hungUp = true,
            onRetry: () {},
            onToggleMute: () => muted = true,
          ),
        ),
      ),
    );

    expect(find.text('Voice call with Bob'), findsOneWidget);
    await tester.tap(find.byTooltip('Mute microphone'));
    expect(muted, isTrue);

    await tester.tap(find.byTooltip('Hang up'));
    expect(hungUp, isTrue);
  });

  testWidgets('voice call mic permission failure offers retry', (
    WidgetTester tester,
  ) async {
    var retried = false;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: const VoiceCallState(
              phase: VoiceCallPhase.failed,
              peerId: 'bob',
              callId: 'call-1',
              failureReason: VoiceCallFailureReason.microphoneDenied,
              detail: 'NotAllowedError: Permission denied',
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () => dismissed = true,
            onRetry: () => retried = true,
            onToggleMute: () {},
          ),
        ),
      ),
    );

    expect(find.text('Voice call failed'), findsOneWidget);
    expect(find.text('Microphone permission required.'), findsOneWidget);
    expect(find.textContaining('NotAllowedError'), findsNothing);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);

    await tester.tap(find.text('Dismiss'));
    expect(dismissed, isTrue);
  });

  testWidgets('voice call failed dismiss hides raw native errors', (
    WidgetTester tester,
  ) async {
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainVoiceCallPanel(
            state: const VoiceCallState(
              phase: VoiceCallPhase.failed,
              peerId: 'bob',
              callId: 'call-1',
              failureReason: VoiceCallFailureReason.mediaConnectionFailed,
              detail:
                  'Unable to RTCRtpTransceiver::setDirection: RtpTransceiver has been disposed.',
            ),
            displayName: 'Bob',
            onAccept: () {},
            onReject: () {},
            onHangUp: () => dismissed = true,
            onRetry: () {},
            onToggleMute: () {},
          ),
        ),
      ),
    );

    expect(
      find.text('Call media could not connect. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('RTCRtpTransceiver'), findsNothing);

    await tester.tap(find.text('Dismiss'));
    expect(dismissed, isTrue);
  });
}

Finder _findMeterCells(String prefix) {
  return find.byWidgetPredicate((Widget widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });
}
