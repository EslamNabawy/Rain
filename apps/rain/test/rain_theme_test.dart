import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/rain_backdrop.dart';

void main() {
  test('Rain texture tokens separate signal color from card chrome', () {
    expect(
      RainTextureTokens.signalLineDark,
      isNot(RainTextureTokens.cardBorderDark),
    );
    expect(
      RainTextureTokens.signalLineLight,
      isNot(RainTextureTokens.cardBorderLight),
    );
    expect(RainMotion.ambientLoop, greaterThan(RainMotion.splashIntro));
    expect(RainMotion.fullscreenTransition, greaterThan(RainMotion.quick));
  });

  test('spacing and radius tokens are strictly increasing', () {
    const space = <double>[
      RainSpace.xxs,
      RainSpace.xs,
      RainSpace.sm,
      RainSpace.md,
      RainSpace.lg,
      RainSpace.xl,
      RainSpace.xxl,
    ];
    const radius = <double>[
      RainRadius.sm,
      RainRadius.md,
      RainRadius.lg,
      RainRadius.xl,
      RainRadius.xxl,
      RainRadius.pill,
    ];
    for (final scale in <List<double>>[space, radius]) {
      for (var i = 1; i < scale.length; i++) {
        expect(scale[i], greaterThan(scale[i - 1]));
      }
    }
    expect(RainMotion.pressScale, lessThan(RainMotion.quick));
    expect(RainMotion.splashCaptionDelay, greaterThan(RainMotion.slow));
  });

  testWidgets('dark theme has a floating snackbar theme like light', (
    WidgetTester tester,
  ) async {
    final dark = RainTheme.dark().snackBarTheme;
    final light = RainTheme.light().snackBarTheme;
    expect(dark.behavior, SnackBarBehavior.floating);
    expect(dark.backgroundColor, RainColors.surfaceRaisedDark);
    expect(dark.behavior, light.behavior);
  });

  testWidgets(
    'RainBackdrop follows light theme surface instead of dark command gradient',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: RainColors.primaryLight,
              brightness: Brightness.light,
            ),
          ),
          home: const RainBackdrop(child: SizedBox.expand()),
        ),
      );

      final backdrop = tester.widget<DecoratedBox>(
        find.byWidgetPredicate((Widget widget) {
          if (widget is! DecoratedBox) {
            return false;
          }
          final decoration = widget.decoration;
          return decoration is BoxDecoration &&
              decoration.gradient is LinearGradient;
        }).first,
      );
      final decoration = backdrop.decoration as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;

      expect(gradient.colors.first, RainColors.backgroundLight);
      expect(gradient.colors, contains(RainColors.surfaceLight));
      expect(gradient.colors, isNot(contains(RainColors.backgroundDark)));
      expect(find.byType(CustomPaint), findsWidgets);
    },
  );

  testWidgets('RainBackdrop exposes dedicated splash texture variant', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: RainColors.primary,
            brightness: Brightness.dark,
          ),
        ),
        home: const RainBackdrop.splash(child: SizedBox.expand()),
      ),
    );

    final backdrop = tester.widget<RainBackdrop>(find.byType(RainBackdrop));
    expect(backdrop.variant, RainBackdropVariant.splash);

    final decoratedBox = tester.widget<DecoratedBox>(
      find.byWidgetPredicate((Widget widget) {
        if (widget is! DecoratedBox) {
          return false;
        }
        final decoration = widget.decoration;
        return decoration is BoxDecoration &&
            decoration.gradient is LinearGradient;
      }).first,
    );
    final decoration = decoratedBox.decoration as BoxDecoration;
    final gradient = decoration.gradient! as LinearGradient;

    expect(gradient.colors, contains(const Color(0xFF092934)));
    expect(gradient.colors, isNot(contains(RainColors.backgroundMid)));
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
