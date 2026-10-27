/// # rain_state_surfaces_test.dart
///
/// Widget tests for Rain state surface components like RainMistStateCard. Validates title/message/action rendering, neutral chrome panel texture tokens, and border color theming.
///
/// **Key types:** RainMistStateCard, RainColors
///
/// **Depends on:** flutter_test, rain rain_state_surfaces, rain_theme, app_components
library;

import 'package:material_ui/material_ui.dart';
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

  testWidgets('AppStateMessage renders through RainMistStateCard with action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppStateMessage(
          icon: Icons.inbox_outlined,
          title: 'Nothing here',
          message: 'Try again later.',
          action: TextButton(onPressed: () {}, child: const Text('Retry')),
        ),
      ),
    );

    expect(find.byType(RainMistStateCard), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('RainMistStateCard fades in and settles', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RainMistStateCard(title: 'Hello', message: 'World'),
      ),
    );
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('RainMistStateCard has no pending animation when reduced', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: RainMistStateCard(title: 'Hello', message: 'World'),
        ),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('skeleton variants render their row keys', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Column(
            children: <Widget>[
              RainStreakSkeleton(
                rows: 2,
                variant: RainSkeletonVariant.messages,
              ),
              RainStreakSkeleton(rows: 2, variant: RainSkeletonVariant.friends),
              RainStreakSkeleton(rows: 2),
            ],
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('rain_skeleton_message_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rain_skeleton_friend_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('rain_streak_skeleton_row_1')),
      findsOneWidget,
    );
  });

  testWidgets('skeleton pulses normally and is still under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: RainStreakSkeleton(rows: 2)),
    );
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: RainStreakSkeleton(rows: 2)),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
