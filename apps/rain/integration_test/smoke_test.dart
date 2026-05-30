import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke flow', (tester) async {
    await app.runRainApp(
      environment: AppEnvironment.fromEnvironment(
        runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
      ),
    );
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey<String>('qa.auth.mode.toggle')),
    );

    final tapTarget = find.byKey(const ValueKey<String>('qa.auth.mode.toggle'));
    expect(tapTarget, findsOneWidget);

    await tester.tap(tapTarget);
    await _pumpUntilFound(tester, find.text('Create account'));

    expect(
      find.byKey(const ValueKey<String>('qa.auth.mode.title')),
      findsOneWidget,
    );
    expect(find.text('Create account'), findsWidgets);
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  throw TestFailure('Timed out waiting for $finder');
}
