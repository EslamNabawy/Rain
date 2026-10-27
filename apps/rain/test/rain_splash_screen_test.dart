/// # rain_splash_screen_test.dart
///
/// Widget tests for the Rain splash screen. Verifies animated orbital Peer Core mark rendering, reduced motion static fallback, and low power tier static mark path.
///
/// **Key types:** RainSplashScreen, RainPeerCoreAnimatedMark, RainPeerCoreMark, RainBackdrop, RainPerformanceScope
///
/// **Depends on:** flutter_test, rain splash_screen, rain_peer_core_mark, rain_performance, rain_backdrop
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/screens/splash_screen.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/rain_backdrop.dart';

void main() {
  testWidgets('RainSplashScreen uses animated orbital Peer Core mark', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RainSplashScreen()));

    final mark = tester.widget<RainPeerCoreAnimatedMark>(
      find.byKey(const ValueKey<String>('rain-splash-peer-core-mark')),
    );
    expect(mark.motion, RainPeerCoreMotion.orbitalMesh);
    expect(mark.reducedMotion, isFalse);

    final backdrop = tester.widget<RainBackdrop>(find.byType(RainBackdrop));
    expect(backdrop.variant, RainBackdropVariant.splash);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RainSplashScreen reduced motion renders static mark path', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: RainSplashScreen(),
        ),
      ),
    );

    expect(find.byType(RainPeerCoreMark), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('rain_peer_core_orbital_mesh')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('RainSplashScreen low power tier renders static mark path', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RainPerformanceScope(
          profile: RainPerformanceProfile.detect(
            override: 'low_power',
            abiName: 'androidArm',
          ),
          child: const RainSplashScreen(),
        ),
      ),
    );

    expect(find.byType(RainPeerCoreMark), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('rain_peer_core_orbital_mesh')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('RainSplashScreen fits compact Android logical height', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: RainSplashScreen()));

    expect(find.text('Rain'), findsOneWidget);
    expect(find.text('Private peer link'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('RainSplashScreen intro scale plays once per process', (
    WidgetTester tester,
  ) async {
    debugResetSplashIntro();
    await tester.pumpWidget(const MaterialApp(home: RainSplashScreen()));
    var intro = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(intro.duration, RainMotion.splashIntro);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: RainSplashScreen()));
    intro = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(intro.duration, Duration.zero);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('startup failure hides raw exception text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RainStartupFailureScreen(
          error: StateError('SocketException: lookup firebase #12'),
        ),
      ),
    );
    expect(find.text('Rain could not start'), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('qa.startup.retry')),
      findsNothing,
    );
  });

  testWidgets('startup failure retry button calls the callback', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RainStartupFailureScreen(error: 'boom', onRetry: () => retries++),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('qa.startup.retry')));
    expect(retries, 1);
  });

  testWidgets('startup failure copies sanitized details', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RainStartupFailureScreen(
          error: Exception('Bad state: low disk space'),
          versionLoader: () async => '9.9.9 (1)',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('qa.startup.copy')));
    await tester.pump();
    await tester.pump();
    expect(copied, contains('Rain 9.9.9 (1)'));
    expect(copied, isNot(contains('Exception')));
    expect(find.text('Details copied'), findsOneWidget);
  });
}
