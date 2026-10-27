import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/screens/splash_screen.dart';
import 'package:rain/presentation/screens/startup_surface.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

void main() {
  testWidgets('force update gate shows versions and the update action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RainTheme.dark(),
        home: const RainForceUpdateGate(
          result: ForceUpdateResult(
            status: ForceUpdateStatus.updateRequired,
            currentVersion: '1.0.0',
            minVersion: '1.2.0',
            updateUrl: 'https://example.com/rain',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(
      find.text('This version of Rain can no longer connect.'),
      findsOneWidget,
    );
    expect(find.text('Installed 1.0.0'), findsOneWidget);
    expect(find.text('Required 1.2.0'), findsOneWidget);
    expect(find.text('Get the update'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('qa.update.open')),
      findsOneWidget,
    );
  });

  testWidgets('account deletion screen shows the brand mark and a label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RainTheme.dark(),
        home: const RainAccountDeletionScreen(),
      ),
    );
    await tester.pump();

    expect(find.text('Deleting your account'), findsOneWidget);
    expect(find.byType(RainPeerCoreAnimatedMark), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byWidgetPredicate(
        (Widget w) =>
            w is Semantics && w.properties.label == 'Deleting account',
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
