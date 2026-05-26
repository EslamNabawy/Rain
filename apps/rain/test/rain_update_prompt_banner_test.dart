import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/presentation/widgets/update/rain_update_prompt_banner.dart';

void main() {
  testWidgets('optional update banner shows latest version and actions', (
    WidgetTester tester,
  ) async {
    var updated = false;
    var dismissed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RainUpdatePromptBanner(
            result: const VersionCheckResult(
              status: VersionCheckStatus.optionalUpdateAvailable,
              currentVersion: '1.0.0',
              minVersion: '1.0.0',
              latestVersion: '1.1.0',
              latestBuild: 11,
              updateUrl: 'https://example.com',
            ),
            onUpdate: () => updated = true,
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );

    expect(find.text('Rain 1.1.0 is available.'), findsOneWidget);

    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(updated, isTrue);

    await tester.tap(find.byTooltip('Dismiss update'));
    await tester.pump();
    expect(dismissed, isTrue);
  });
}
