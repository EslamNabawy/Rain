import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/branding/rain_state_surfaces.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/app_components.dart';

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

  testWidgets('RainMistStateCard neutral chrome uses panel texture tokens', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: RainColors.primary,
            brightness: Brightness.dark,
            surface: RainColors.surfaceDark,
          ),
        ),
        home: const RainMistStateCard(
          title: 'No messages yet',
          message: 'Start the first message when the link is ready.',
          icon: Icons.chat_bubble_outline,
        ),
      ),
    );

    final decorations = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((DecoratedBox widget) => widget.decoration)
        .whereType<BoxDecoration>();
    final cardDecoration = decorations.firstWhere(
      (BoxDecoration decoration) => decoration.border != null,
    );
    final border = cardDecoration.border! as Border;

    expect(
      border.top.color,
      RainTextureTokens.cardBorderDark.withValues(
        alpha: RainTextureTokens.panelBorderAlphaDark,
      ),
    );
    expect(border.top.color, isNot(RainTextureTokens.signalLineDark));
  });

  testWidgets('chat empty state helper renders Rain mist card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppStateMessage(
          icon: Icons.water_drop_outlined,
          title: 'No messages yet',
          message: 'Start the first message when the link is ready.',
        ),
      ),
    );

    expect(find.byType(RainMistStateCard), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
    expect(
      find.text('Start the first message when the link is ready.'),
      findsOneWidget,
    );
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
