import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/screens/splash_screen.dart';
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
}
