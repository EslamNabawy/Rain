import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_state_surfaces.dart';

void main() {
  testWidgets('RainMistStateCard renders title message and action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RainMistStateCard(
          title: 'No messages yet',
          message: 'Start the first message when the link is ready.',
          icon: Icons.chat_bubble_outline,
          action: TextButton(onPressed: () {}, child: const Text('Message')),
        ),
      ),
    );

    expect(find.text('No messages yet'), findsOneWidget);
    expect(
      find.text('Start the first message when the link is ready.'),
      findsOneWidget,
    );
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('RainStreakSkeleton renders requested rows', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RainStreakSkeleton(rows: 4)),
    );

    for (var index = 0; index < 4; index += 1) {
      expect(
        find.byKey(ValueKey<String>('rain_streak_skeleton_row_$index')),
        findsOneWidget,
      );
    }
  });
}
