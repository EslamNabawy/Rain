import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_state_surfaces.dart';
import 'package:rain/presentation/feedback/rain_snack.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

void main() {
  Future<ScaffoldMessengerState> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RainTheme.dark(),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );
    return tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
  }

  testWidgets('neutral snack shows its icon and lasts 4 seconds', (
    WidgetTester tester,
  ) async {
    final messenger = await pump(tester);

    showRainSnack(messenger, 'Saved');
    await tester.pump();

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.duration, const Duration(seconds: 4));
    expect(
      find.byKey(const ValueKey<String>('rain-snack-icon-neutral')),
      findsOneWidget,
    );
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('error snack uses the error colour and lasts 6 seconds', (
    WidgetTester tester,
  ) async {
    final messenger = await pump(tester);

    showRainSnack(
      messenger,
      'Could not save',
      severity: RainStateSeverity.error,
      action: SnackBarAction(label: 'Retry', onPressed: () {}),
    );
    await tester.pump();

    final snack = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snack.duration, const Duration(seconds: 6));
    expect(snack.backgroundColor, RainTheme.dark().colorScheme.error);
    expect(
      find.byKey(const ValueKey<String>('rain-snack-icon-error')),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('warning snack shows the warning icon', (
    WidgetTester tester,
  ) async {
    final messenger = await pump(tester);

    showRainSnack(messenger, 'Heads up', severity: RainStateSeverity.warning);
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('rain-snack-icon-warning')),
      findsOneWidget,
    );
  });
}
