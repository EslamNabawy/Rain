/// # rain_theme_test.dart
///
/// Tests for Rain theme system including texture tokens, motion durations, and backdrop gradients. Validates light/dark theme separation, signal color tokens, and splash texture variants.
///
/// **Key types:** RainTextureTokens, RainMotion, RainColors, RainBackdrop, RainBackdropVariant
///
/// **Depends on:** flutter_test, rain rain_theme, rain_backdrop
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';
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

  test(
    'rebuilt button themes are equal so MaterialApp does not re-animate',
    () {
      for (final build in <ThemeData Function()>[
        RainTheme.dark,
        RainTheme.light,
      ]) {
        final a = build();
        final b = build();
        expect(a.filledButtonTheme, b.filledButtonTheme);
        expect(a.outlinedButtonTheme, b.outlinedButtonTheme);
        expect(a.textButtonTheme, b.textButtonTheme);
        expect(a.focusColor, b.focusColor);
      }
    },
  );

  test('Space Grotesk styles use bundled google_fonts families', () {
    // google_fonts registers bundled weights as SpaceGrotesk_<weight> from
    // assets/google_fonts/SpaceGrotesk-<Weight>.ttf.
    const bundled = <String, String>{
      'SpaceGrotesk_500': 'Medium',
      'SpaceGrotesk_600': 'SemiBold',
      'SpaceGrotesk_700': 'Bold',
    };
    for (final weight in bundled.values) {
      expect(
        File('assets/google_fonts/SpaceGrotesk-$weight.ttf').existsSync(),
        isTrue,
        reason: weight,
      );
    }

    final dark = RainTheme.dark();
    final light = RainTheme.light();
    final styles = <TextStyle?>[
      for (final theme in <ThemeData>[dark, light]) ...<TextStyle?>[
        theme.filledButtonTheme.style!.textStyle!.resolve(<WidgetState>{}),
        theme.outlinedButtonTheme.style!.textStyle!.resolve(<WidgetState>{}),
        theme.textButtonTheme.style!.textStyle!.resolve(<WidgetState>{}),
        theme.inputDecorationTheme.labelStyle,
      ],
      light.navigationBarTheme.labelTextStyle!.resolve(<WidgetState>{}),
      light.navigationRailTheme.selectedLabelTextStyle,
      light.navigationRailTheme.unselectedLabelTextStyle,
    ];
    for (final style in styles) {
      expect(bundled.keys, contains(style!.fontFamily));
    }
  });

  test('buttons show hover, focus and press overlays', () {
    for (final theme in <ThemeData>[RainTheme.dark(), RainTheme.light()]) {
      final overlay = theme.textButtonTheme.style!.overlayColor!;
      expect(overlay.resolve(<WidgetState>{WidgetState.hovered}), isNotNull);
      expect(overlay.resolve(<WidgetState>{WidgetState.focused}), isNotNull);
      expect(overlay.resolve(<WidgetState>{WidgetState.pressed}), isNotNull);
      expect(overlay.resolve(<WidgetState>{}), isNull);
      expect(theme.filledButtonTheme.style!.overlayColor, isNotNull);
      expect(theme.outlinedButtonTheme.style!.overlayColor, isNotNull);
    }
  });
}
