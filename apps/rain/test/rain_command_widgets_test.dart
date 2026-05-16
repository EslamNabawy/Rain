import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/widgets/rain_command_widgets.dart';

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
}

Finder _findMeterCells(String prefix) {
  return find.byWidgetPredicate((Widget widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith(prefix);
  });
}
