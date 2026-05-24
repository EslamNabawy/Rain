import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';

void main() {
  testWidgets('RainPeerCoreMark renders static asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: RainPeerCoreMark(size: 64)),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('RainPeerCoreAnimatedMark respects reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RainPeerCoreAnimatedMark(size: 96, reducedMotion: true),
      ),
    );

    expect(find.byType(RainPeerCoreMark), findsOneWidget);
  });

  testWidgets('RainPeerCoreAnimatedMark rotates orbital mesh when enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RainPeerCoreAnimatedMark(
          size: 112,
          motion: RainPeerCoreMotion.orbitalMesh,
        ),
      ),
    );

    final finder = find.byKey(
      const ValueKey<String>('rain_peer_core_orbital_mesh'),
    );
    expect(finder, findsOneWidget);

    final initial = List<double>.of(
      tester.widget<Transform>(finder).transform.storage,
    );
    await tester.pump(const Duration(milliseconds: 240));
    final rotated = List<double>.of(
      tester.widget<Transform>(finder).transform.storage,
    );

    expect(rotated, isNot(initial));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
