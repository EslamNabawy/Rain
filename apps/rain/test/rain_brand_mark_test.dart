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
}
