import 'package:flutter/material.dart';

import 'package:rain/presentation/theme/rain_theme.dart';

class RainBackdrop extends StatelessWidget {
  const RainBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const <Color>[
                  RainColors.backgroundDark,
                  RainColors.backgroundMid,
                  RainColors.backgroundDeep,
                ]
              : const <Color>[
                  RainColors.backgroundLight,
                  RainColors.surfaceLight,
                  RainColors.backgroundLightCool,
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _RainAtmosphere(isDark: isDark),
          child,
        ],
      ),
    );
  }
}

class _RainAtmosphere extends StatelessWidget {
  const _RainAtmosphere({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _RainSignalMistPainter(isDark: isDark),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RainSignalMistPainter extends CustomPainter {
  const _RainSignalMistPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final linePaint = Paint()
      ..color = RainColors.mistCyan.withValues(alpha: isDark ? 0.055 : 0.070)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final accentPaint = Paint()
      ..color = RainColors.peerMint.withValues(alpha: isDark ? 0.038 : 0.052)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final wavePaint = Paint()
      ..color = RainColors.mistCyan.withValues(alpha: isDark ? 0.040 : 0.048)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final spacing = size.shortestSide < 520 ? 88.0 : 124.0;
    for (var x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height * 0.42, 0),
        linePaint,
      );
    }

    for (var x = -size.height * 0.35; x < size.width; x += spacing * 1.9) {
      canvas.drawLine(
        Offset(x, size.height * 0.84),
        Offset(x + size.height * 0.28, size.height * 0.22),
        accentPaint,
      );
    }

    final waveRect = Rect.fromCircle(
      center: Offset(size.width * 0.78, size.height * 0.24),
      radius: size.shortestSide * 0.34,
    );
    for (final inset in <double>[0, 28, 56]) {
      canvas.drawArc(waveRect.deflate(inset), 2.45, 1.05, false, wavePaint);
    }

    final lowerWaveRect = Rect.fromCircle(
      center: Offset(size.width * 0.18, size.height * 0.88),
      radius: size.shortestSide * 0.26,
    );
    canvas.drawArc(lowerWaveRect, -0.72, 0.82, false, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _RainSignalMistPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
