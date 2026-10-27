import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/widgets/home/rain_message_entrance.dart';

void main() {
  Future<void> pumpEntrance(
    WidgetTester tester, {
    required bool animate,
    bool disableAnimations = false,
  }) {
    return tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RainMessageEntrance(
            animate: animate,
            isOutgoing: true,
            child: const Text('hello'),
          ),
        ),
      ),
    );
  }

  double opacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.byType(Opacity)).opacity;

  testWidgets('animate false renders the message immediately', (
    WidgetTester tester,
  ) async {
    await pumpEntrance(tester, animate: false);

    expect(opacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('animate true fades in over the message entrance time', (
    WidgetTester tester,
  ) async {
    await pumpEntrance(tester, animate: true);
    await tester.pump(const Duration(milliseconds: 50));

    expect(opacity(tester), lessThan(1));

    await tester.pump(const Duration(milliseconds: 150));

    expect(opacity(tester), 1);
  });

  testWidgets('reduced motion renders the message immediately', (
    WidgetTester tester,
  ) async {
    await pumpEntrance(tester, animate: true, disableAnimations: true);

    expect(opacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a later rebuild with animate false keeps the entrance going', (
    WidgetTester tester,
  ) async {
    await pumpEntrance(tester, animate: true);
    await tester.pump(const Duration(milliseconds: 40));
    await pumpEntrance(tester, animate: false);
    await tester.pump(const Duration(milliseconds: 10));

    expect(opacity(tester), lessThan(1));
    expect(find.text('hello'), findsOneWidget);
  });
}
