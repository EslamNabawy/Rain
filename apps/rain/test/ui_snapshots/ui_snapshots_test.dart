import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/presentation/branding/rain_state_surfaces.dart';
import 'package:rain/presentation/screens/onboarding_screen.dart';
import 'package:rain/presentation/screens/splash_screen.dart';
import 'package:rain/presentation/screens/startup_surface.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/app_components.dart';
import 'package:rain/presentation/widgets/calls/rain_call_ended_surface.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';

// Opt-in visual snapshots. Normal runs skip every case. Generate with:
// flutter test --update-goldens --dart-define=RAIN_UI_SNAPSHOTS=true test/ui_snapshots/ui_snapshots_test.dart
const bool _enabled = bool.fromEnvironment('RAIN_UI_SNAPSHOTS');

const Map<String, Size> _sizes = <String, Size>{
  'phone': Size(390, 844),
  'desktop': Size(1280, 800),
};

// google_fonts tries to fetch Inter/Space Grotesk, which the test HTTP stack
// rejects with 400. Those async errors are dropped; text renders in a fallback
// font until fonts are bundled (T1.1).
Future<void> _shoot(
  WidgetTester tester,
  String name,
  Widget Function() build,
) async {
  final Completer<void> done = Completer<void>();
  runZonedGuarded(() async {
    try {
      await _shootUnguarded(tester, name, build);
      done.complete();
    } catch (error, stack) {
      done.completeError(error, stack);
    }
  }, (Object error, StackTrace stack) {});
  await done.future;
}

Future<void> _shootUnguarded(
  WidgetTester tester,
  String name,
  Widget Function() build,
) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1;
  for (final MapEntry<String, Size> size in _sizes.entries) {
    for (final ThemeMode mode in <ThemeMode>[ThemeMode.light, ThemeMode.dark]) {
      tester.view.physicalSize = size.value;
      await tester.pumpWidget(
        ProviderScope(
          child: MediaQuery(
            data: MediaQueryData(size: size.value, disableAnimations: true),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RainTheme.light(),
              darkTheme: RainTheme.dark(),
              themeMode: mode,
              home: build(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/${name}_${mode.name}_${size.key}.png'),
      );
    }
  }
}

Widget _framed(Widget child) => Scaffold(
  body: Center(
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

RainMessageBubble _bubble({
  required String text,
  required bool isOutgoing,
  String? deliveryLabel,
  Color? deliveryColor,
  VoidCallback? onRetry,
}) {
  return RainMessageBubble(
    text: text,
    timeLabel: '10:42',
    isOutgoing: isOutgoing,
    startsCluster: true,
    endsCluster: true,
    maxWidth: 300,
    deliveryLabel: deliveryLabel,
    deliveryColor: deliveryColor,
    onRetry: onRetry,
  );
}

void main() {
  const bool skip = !_enabled;

  testWidgets('splash', skip: skip, (tester) async {
    await _shoot(tester, 'splash', () => const RainSplashScreen());
  });

  testWidgets('startup_failure', skip: skip, (tester) async {
    await _shoot(
      tester,
      'startup_failure',
      () => RainStartupFailureScreen(error: StateError('x')),
    );
  });

  testWidgets('force_update', skip: skip, (tester) async {
    await _shoot(
      tester,
      'force_update',
      () => const RainForceUpdateGate(
        result: ForceUpdateResult(
          status: ForceUpdateStatus.updateRequired,
          currentVersion: '1.0.0',
          minVersion: '2.0.0',
          updateUrl: 'https://example.com',
        ),
      ),
    );
  });

  testWidgets('account_deletion', skip: skip, (tester) async {
    await _shoot(
      tester,
      'account_deletion',
      () => const RainAccountDeletionScreen(),
    );
  });

  testWidgets('state_card', skip: skip, (tester) async {
    await _shoot(
      tester,
      'state_card',
      () => _framed(
        const Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: <Widget>[
            RainMistStateCard(
              title: 'Nothing here yet',
              message: 'Neutral state.',
              icon: Icons.chat_bubble_outline,
            ),
            RainMistStateCard(
              title: 'Heads up',
              message: 'Warning state.',
              icon: Icons.warning_amber_rounded,
              severity: RainStateSeverity.warning,
            ),
            RainMistStateCard(
              title: 'Something failed',
              message: 'Error state.',
              icon: Icons.error_outline,
              severity: RainStateSeverity.error,
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('app_state_message', skip: skip, (tester) async {
    await _shoot(
      tester,
      'app_state_message',
      () => _framed(
        const AppStateMessage(
          icon: Icons.people_outline,
          title: 'No friends yet',
          message: 'Add someone to start chatting.',
        ),
      ),
    );
  });

  testWidgets('skeleton', skip: skip, (tester) async {
    await _shoot(
      tester,
      'skeleton',
      () => _framed(const RainStreakSkeleton(rows: 5)),
    );
  });

  testWidgets('bubbles', skip: skip, (tester) async {
    await _shoot(
      tester,
      'bubbles',
      () => _framed(
        Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: <Widget>[
            _bubble(text: 'Hey, are you there?', isOutgoing: false),
            _bubble(
              text: 'Sending a message',
              isOutgoing: true,
              deliveryLabel: 'Sending',
            ),
            _bubble(
              text: 'This one failed',
              isOutgoing: true,
              deliveryLabel: 'Failed',
              deliveryColor: Colors.redAccent,
              onRetry: () {},
            ),
          ],
        ),
      ),
    );
  });

  // file_transfer: skipped. _FileTransferBubble is library-private and has no
  // public constructor helper (see audit/ui/STATE.md Notes).

  testWidgets('call_ended', skip: skip, (tester) async {
    await _shoot(
      tester,
      'call_ended',
      () => _framed(
        RainCallEndedSurface(
          summary: CallEndSummary(
            peerId: 'bob',
            peerLabel: 'Bob',
            mediaMode: CallMediaMode.audio,
            duration: const Duration(minutes: 1, seconds: 8),
            initiator: CallEndInitiator.remote,
            reason: 'Peer ended the call.',
            endedAt: DateTime(2026, 5, 26),
          ),
          onClose: () {},
          onCallAgain: () {},
        ),
      ),
    );
  });

  testWidgets('onboarding', skip: skip, (tester) async {
    await _shoot(tester, 'onboarding', () => const OnboardingScreen());
  });
}
