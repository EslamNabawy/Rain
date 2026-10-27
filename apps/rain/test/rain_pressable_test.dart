import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/feedback/rain_pressable.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onTap,
    bool autofocus = false,
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: RainTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Center(
              child: RainPressable(
                onTap: onTap,
                autofocus: autofocus,
                semanticLabel: 'Open chat',
                child: const SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double scale(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('tap fires once', (WidgetTester tester) async {
    var taps = 0;
    await pump(tester, onTap: () => taps += 1);

    await tester.tap(find.byType(RainPressable));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('Enter activates when focused', (WidgetTester tester) async {
    var taps = 0;
    await pump(tester, onTap: () => taps += 1, autofocus: true);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('scales down while pressed and back after release', (
    WidgetTester tester,
  ) async {
    await pump(tester, onTap: () {});

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RainPressable)),
    );
    await tester.pump();

    expect(scale(tester), lessThan(1));

    await gesture.up();
    await tester.pumpAndSettle();

    expect(scale(tester), 1);
  });

  testWidgets('reduced motion keeps scale at 1 while pressed', (
    WidgetTester tester,
  ) async {
    await pump(tester, onTap: () {}, disableAnimations: true);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(RainPressable)),
    );
    await tester.pump();

    expect(scale(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
    await gesture.up();
  });

  testWidgets('without onTap it only adds press scale', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.byType(FocusableActionDetector), findsNothing);
    expect(find.byType(AnimatedScale), findsOneWidget);
  });
}
