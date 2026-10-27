import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/widgets/feedback/rain_busy_indicator.dart';
import 'package:rain/presentation/widgets/feedback/rain_delayed_reveal.dart';

void main() {
  testWidgets('busy indicator exposes a semantics label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RainBusyIndicator(semanticsLabel: 'Sending')),
      ),
    );
    expect(find.bySemanticsLabel('Sending'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RainBusyIndicator())),
    );
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
  });

  testWidgets('busy indicator is a static ring under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: Scaffold(body: RainBusyIndicator())),
      ),
    );
    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 0.75);
  });

  testWidgets('delayed reveal shows the child only after the delay', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RainDelayedReveal(child: Text('Loading rows'))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Loading rows'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Loading rows'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('delayed reveal leaves no timer after dispose', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RainDelayedReveal(child: Text('x'))),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
