import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/rain_backdrop.dart';

void main() {
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
    },
  );
}
