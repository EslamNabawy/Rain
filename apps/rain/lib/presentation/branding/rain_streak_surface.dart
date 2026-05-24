import 'package:flutter/material.dart';

class RainStreakSurface extends StatelessWidget {
  const RainStreakSurface({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _RainStreakPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _RainStreakPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (var x = -size.width; x < size.width * 2; x += 18) {
      canvas.drawLine(
        Offset(x.toDouble(), -size.height * 0.2),
        Offset(x + size.width * 0.20, size.height * 1.2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RainStreakPainter oldDelegate) => false;
}
