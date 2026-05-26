import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rain/presentation/performance/rain_performance.dart';

class RainRippleHaloSurface extends StatefulWidget {
  const RainRippleHaloSurface({
    super.key,
    required this.child,
    this.enabled = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.color,
    this.origin = Alignment.center,
    this.pulseKey,
    this.pulseOnMount = false,
    this.minSize,
    this.callSurface = false,
  });

  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;
  final Color? color;
  final Alignment origin;
  final Object? pulseKey;
  final bool pulseOnMount;
  final Size? minSize;
  final bool callSurface;

  @override
  State<RainRippleHaloSurface> createState() => _RainRippleHaloSurfaceState();
}

class _RainRippleHaloSurfaceState extends State<RainRippleHaloSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    if (widget.enabled && widget.pulseOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emitPulse());
    }
  }

  @override
  void didUpdateWidget(covariant RainRippleHaloSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameEnabled = widget.enabled && !oldWidget.enabled;
    final stateChanged =
        widget.enabled &&
        oldWidget.enabled &&
        oldWidget.pulseKey != widget.pulseKey;
    if (becameEnabled || stateChanged) {
      _emitPulse();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _constrainedChild();
    if (!widget.enabled) {
      return ClipRRect(borderRadius: widget.borderRadius, child: child);
    }

    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? scheme.primary;
    final performance = RainPerformanceScope.of(context);
    final lowPower = widget.callSurface
        ? performance.isLowPowerCallSurface
        : performance.isLowPower;
    final reducedMotion =
        MediaQuery.of(context).disableAnimations ||
        (widget.callSurface
            ? !performance.allowContinuousCallAnimation
            : lowPower);

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (BuildContext context, _) {
                  final progress =
                      reducedMotion || !_pulseController.isAnimating
                      ? null
                      : _pulseController.value;
                  return CustomPaint(
                    painter: _RainRippleHaloPainter(
                      color: color,
                      borderRadius: widget.borderRadius,
                      origin: widget.origin,
                      pulseProgress: progress,
                      lowPower: lowPower,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _constrainedChild() {
    final minSize = widget.minSize;
    if (minSize == null) {
      return widget.child;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minSize.width,
        minHeight: minSize.height,
      ),
      child: widget.child,
    );
  }

  void _emitPulse() {
    if (!mounted ||
        MediaQuery.maybeOf(context)?.disableAnimations == true ||
        (widget.callSurface
            ? !RainPerformanceScope.read(context).allowContinuousCallAnimation
            : RainPerformanceScope.read(context).isLowPower)) {
      return;
    }
    _pulseController.forward(from: 0);
  }
}

class _RainRippleHaloPainter extends CustomPainter {
  const _RainRippleHaloPainter({
    required this.color,
    required this.borderRadius,
    required this.origin,
    required this.pulseProgress,
    required this.lowPower,
  });

  final Color color;
  final BorderRadius borderRadius;
  final Alignment origin;
  final double? pulseProgress;
  final bool lowPower;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final rect = Offset.zero & size;
    final center = origin.alongSize(size);
    final shortestSide = math.min(size.width, size.height);
    final maxRadius =
        math.sqrt(size.width * size.width + size.height * size.height) * 0.58;

    _drawStaticRings(canvas, rect, center, maxRadius, shortestSide);
    _drawPulse(canvas, center, shortestSide, maxRadius);
  }

  void _drawStaticRings(
    Canvas canvas,
    Rect rect,
    Offset center,
    double maxRadius,
    double shortestSide,
  ) {
    final maxInset = math.max(0.0, (shortestSide / 2) - 0.1);
    final outer = borderRadius.toRRect(rect.deflate(math.min(0.75, maxInset)));
    final inner = borderRadius.toRRect(rect.deflate(math.min(3.25, maxInset)));
    final softPaint = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = lowPower ? 1.0 : 2.0;
    if (!lowPower) {
      softPaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);
    }
    final crispPaint = Paint()
      ..color = color.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final innerPaint = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    canvas.drawRRect(outer, softPaint);
    canvas.drawRRect(outer, crispPaint);
    canvas.drawRRect(inner, innerPaint);

    final signalRadius = math.min(maxRadius * 0.38, shortestSide * 0.58);
    if (signalRadius > 4) {
      final signalPaint = Paint()
        ..color = color.withValues(alpha: 0.11)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      canvas.drawCircle(center, signalRadius, signalPaint);
    }
  }

  void _drawPulse(
    Canvas canvas,
    Offset center,
    double shortestSide,
    double maxRadius,
  ) {
    final progress = pulseProgress;
    if (progress == null) {
      return;
    }

    final eased = Curves.easeOutCubic.transform(
      progress.clamp(0.0, 1.0).toDouble(),
    );
    final startRadius = math.max(8.0, shortestSide * 0.22);
    final radius = startRadius + ((maxRadius - startRadius) * eased);
    final alpha = (1 - eased) * 0.30;
    if (alpha <= 0) {
      return;
    }

    final pulsePaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    if (!lowPower) {
      pulsePaint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9);
    }
    canvas.drawCircle(center, radius, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant _RainRippleHaloPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.origin != origin ||
        oldDelegate.pulseProgress != pulseProgress ||
        oldDelegate.lowPower != lowPower;
  }
}
