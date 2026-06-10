import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

enum RainBackdropVariant { shell, splash, call, settings }

class RainBackdrop extends StatelessWidget {
  const RainBackdrop({
    super.key,
    required this.child,
    this.variant = RainBackdropVariant.shell,
  });

  const RainBackdrop.shell({super.key, required this.child})
    : variant = RainBackdropVariant.shell;

  const RainBackdrop.splash({super.key, required this.child})
    : variant = RainBackdropVariant.splash;

  const RainBackdrop.call({super.key, required this.child})
    : variant = RainBackdropVariant.call;

  const RainBackdrop.settings({super.key, required this.child})
    : variant = RainBackdropVariant.settings;

  final Widget child;
  final RainBackdropVariant variant;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
    final lowPower = RainPerformanceScope.of(context).isLowPower;
    final style = _RainBackdropStyle.resolve(variant, isDark: isDark);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: style.gradientColors,
          stops: style.gradientStops,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _RainAtmosphere(isDark: isDark, variant: variant, lowPower: lowPower),
          child,
        ],
      ),
    );
  }
}

class _RainBackdropStyle {
  const _RainBackdropStyle({
    required this.gradientColors,
    required this.gradientStops,
    required this.mistAlpha,
    required this.accentAlpha,
    required this.waveAlpha,
    required this.glowAlpha,
    required this.spacing,
    required this.lineStrokeWidth,
    required this.showNodes,
  });

  final List<Color> gradientColors;
  final List<double> gradientStops;
  final double mistAlpha;
  final double accentAlpha;
  final double waveAlpha;
  final double glowAlpha;
  final double spacing;
  final double lineStrokeWidth;
  final bool showNodes;

  static _RainBackdropStyle resolve(
    RainBackdropVariant variant, {
    required bool isDark,
  }) {
    final mistAlpha = switch (variant) {
      RainBackdropVariant.splash =>
        isDark
            ? RainTextureTokens.splashMistAlphaDark
            : RainTextureTokens.splashMistAlphaLight,
      RainBackdropVariant.call =>
        isDark
            ? RainTextureTokens.callMistAlphaDark
            : RainTextureTokens.callMistAlphaLight,
      RainBackdropVariant.settings =>
        isDark
            ? RainTextureTokens.panelMistAlphaDark
            : RainTextureTokens.panelMistAlphaLight,
      RainBackdropVariant.shell =>
        isDark
            ? RainTextureTokens.shellMistAlphaDark
            : RainTextureTokens.shellMistAlphaLight,
    };

    return _RainBackdropStyle(
      gradientColors: _gradientColors(variant, isDark: isDark),
      gradientStops: switch (variant) {
        RainBackdropVariant.splash => const <double>[0, 0.52, 1],
        RainBackdropVariant.call => const <double>[0, 0.48, 1],
        RainBackdropVariant.settings => const <double>[0, 0.58, 1],
        RainBackdropVariant.shell => const <double>[0, 0.55, 1],
      },
      mistAlpha: mistAlpha,
      accentAlpha: switch (variant) {
        RainBackdropVariant.splash => isDark ? 0.112 : 0.082,
        RainBackdropVariant.call => isDark ? 0.094 : 0.070,
        RainBackdropVariant.settings => isDark ? 0.060 : 0.052,
        RainBackdropVariant.shell =>
          isDark
              ? RainTextureTokens.accentAlphaDark
              : RainTextureTokens.accentAlphaLight,
      },
      waveAlpha: switch (variant) {
        RainBackdropVariant.splash => isDark ? 0.105 : 0.078,
        RainBackdropVariant.call => isDark ? 0.096 : 0.070,
        RainBackdropVariant.settings => isDark ? 0.056 : 0.044,
        RainBackdropVariant.shell =>
          isDark
              ? RainTextureTokens.waveAlphaDark
              : RainTextureTokens.waveAlphaLight,
      },
      glowAlpha: switch (variant) {
        RainBackdropVariant.splash => isDark ? 0.105 : 0.066,
        RainBackdropVariant.call => isDark ? 0.092 : 0.058,
        RainBackdropVariant.settings => isDark ? 0.054 : 0.038,
        RainBackdropVariant.shell => isDark ? 0.066 : 0.044,
      },
      spacing: switch (variant) {
        RainBackdropVariant.splash => 74,
        RainBackdropVariant.call => 82,
        RainBackdropVariant.settings => 118,
        RainBackdropVariant.shell => 98,
      },
      lineStrokeWidth: switch (variant) {
        RainBackdropVariant.splash => 1.24,
        RainBackdropVariant.call => 1.16,
        RainBackdropVariant.settings => 0.92,
        RainBackdropVariant.shell => 1.0,
      },
      showNodes:
          variant == RainBackdropVariant.splash ||
          variant == RainBackdropVariant.call,
    );
  }

  static List<Color> _gradientColors(
    RainBackdropVariant variant, {
    required bool isDark,
  }) {
    if (!isDark) {
      return switch (variant) {
        RainBackdropVariant.splash => const <Color>[
          Color(0xFFEAFBFE),
          RainColors.surfaceLight,
          Color(0xFFDDF4F8),
        ],
        RainBackdropVariant.call => const <Color>[
          RainColors.backgroundLightCool,
          RainColors.surfaceLight,
          Color(0xFFE3F5EF),
        ],
        RainBackdropVariant.settings => const <Color>[
          RainColors.backgroundLight,
          RainColors.surfaceLight,
          RainColors.backgroundLightCool,
        ],
        RainBackdropVariant.shell => const <Color>[
          RainColors.backgroundLight,
          RainColors.surfaceLight,
          RainColors.backgroundLightCool,
        ],
      };
    }

    return switch (variant) {
      RainBackdropVariant.splash => const <Color>[
        RainColors.backgroundDark,
        Color(0xFF092934),
        RainColors.backgroundDeep,
      ],
      RainBackdropVariant.call => const <Color>[
        Color(0xFF051016),
        Color(0xFF0A252C),
        RainColors.backgroundDeep,
      ],
      RainBackdropVariant.settings => const <Color>[
        RainColors.backgroundDark,
        Color(0xFF0A1B23),
        RainColors.backgroundDeep,
      ],
      RainBackdropVariant.shell => const <Color>[
        RainColors.backgroundDark,
        RainColors.backgroundMid,
        RainColors.backgroundDeep,
      ],
    };
  }
}

class _RainAtmosphere extends StatelessWidget {
  const _RainAtmosphere({
    required this.isDark,
    required this.variant,
    required this.lowPower,
  });

  final bool isDark;
  final RainBackdropVariant variant;
  final bool lowPower;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _RainSignalMistPainter(
          isDark: isDark,
          variant: variant,
          lowPower: lowPower,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RainSignalMistPainter extends CustomPainter {
  const _RainSignalMistPainter({
    required this.isDark,
    required this.variant,
    required this.lowPower,
  });

  final bool isDark;
  final RainBackdropVariant variant;
  final bool lowPower;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final style = _RainBackdropStyle.resolve(variant, isDark: isDark);
    final signalLineColor = isDark
        ? RainTextureTokens.signalLineDark
        : RainTextureTokens.signalLineLight;
    final signalAccentColor = isDark
        ? RainTextureTokens.signalAccentDark
        : RainTextureTokens.signalAccentLight;

    final glowPaint = Paint()
      ..color = signalLineColor.withValues(
        alpha: lowPower ? 0 : style.glowAlpha,
      );
    final linePaint = Paint()
      ..color = signalLineColor.withValues(alpha: style.mistAlpha)
      ..strokeWidth = style.lineStrokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final accentPaint = Paint()
      ..color = signalAccentColor.withValues(alpha: style.accentAlpha)
      ..strokeWidth = style.lineStrokeWidth + 0.18
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final wavePaint = Paint()
      ..color = signalLineColor.withValues(alpha: style.waveAlpha)
      ..strokeWidth = style.lineStrokeWidth
      ..style = PaintingStyle.stroke;

    final glowRadius =
        size.shortestSide *
        switch (variant) {
          RainBackdropVariant.splash => 0.36,
          RainBackdropVariant.call => 0.32,
          RainBackdropVariant.settings => 0.22,
          RainBackdropVariant.shell => 0.26,
        };
    if (!lowPower) {
      glowPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 42);
      canvas.drawCircle(
        Offset(size.width * 0.72, size.height * 0.24),
        glowRadius,
        glowPaint,
      );
      canvas.drawCircle(
        Offset(size.width * 0.22, size.height * 0.88),
        glowRadius * 0.72,
        glowPaint..color = signalAccentColor.withValues(alpha: style.glowAlpha),
      );
    }

    final spacing =
        style.spacing *
        (size.shortestSide < 520 ? 0.88 : 1.18) *
        (lowPower ? 1.7 : 1);
    for (var x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height * 0.42, 0),
        linePaint,
      );
    }

    if (!lowPower) {
      for (var x = -size.height * 0.35; x < size.width; x += spacing * 1.85) {
        canvas.drawLine(
          Offset(x, size.height * 0.84),
          Offset(x + size.height * 0.28, size.height * 0.22),
          accentPaint,
        );
      }
    }

    final waveRect = Rect.fromCircle(
      center: Offset(size.width * 0.78, size.height * 0.24),
      radius: size.shortestSide * 0.34,
    );
    for (final inset
        in lowPower ? const <double>[28] : const <double>[0, 28, 56]) {
      canvas.drawArc(waveRect.deflate(inset), 2.45, 1.05, false, wavePaint);
    }

    final lowerWaveRect = Rect.fromCircle(
      center: Offset(size.width * 0.18, size.height * 0.88),
      radius: size.shortestSide * 0.26,
    );
    if (!lowPower) {
      canvas.drawArc(lowerWaveRect, -0.72, 0.82, false, accentPaint);
    }

    if (style.showNodes && !lowPower) {
      _paintSignalNodes(
        canvas,
        size,
        signalAccentColor.withValues(alpha: style.accentAlpha + 0.045),
      );
    }
  }

  void _paintSignalNodes(Canvas canvas, Size size, Color color) {
    final center = Offset(size.width * 0.18, size.height * 0.28);
    final radius = math.min(size.width, size.height) * 0.055;
    final points = <Offset>[
      center + Offset(-radius * 1.45, radius * 0.36),
      center + Offset(radius * 0.08, -radius * 1.15),
      center + Offset(radius * 1.26, radius * 0.86),
    ];
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawLine(points[0], points[1], paint);
    canvas.drawLine(points[1], points[2], paint);
    canvas.drawLine(points[2], points[0], paint);
    for (final point in points) {
      canvas.drawCircle(point, 3.2, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RainSignalMistPainter oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.variant != variant ||
        oldDelegate.lowPower != lowPower;
  }
}
