import 'package:material_ui/material_ui.dart';
import 'package:rain/presentation/performance/rain_motion_policy.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

const Key rainConnectingPulseAnimatedKey = ValueKey<String>(
  'rain-connecting-pulse-animated',
);
const Key rainConnectingPulseStaticKey = ValueKey<String>(
  'rain-connecting-pulse-static',
);

/// Expanding, fading rings painted behind [child] while a call is connecting.
///
/// The rings paint outside the child's bounds, so the layout size is always
/// the child's size. Animates only when [active], motion is not reduced and
/// the performance tier allows continuous call animation; otherwise an active
/// pulse renders one static ring.
class RainConnectingPulse extends StatefulWidget {
  const RainConnectingPulse({
    super.key,
    required this.child,
    required this.active,
    this.color,
  });

  final Widget child;
  final bool active;
  final Color? color;

  @override
  State<RainConnectingPulse> createState() => _RainConnectingPulseState();
}

class _RainConnectingPulseState extends State<RainConnectingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: RainMotion.connectingPulse,
  );
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RainConnectingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _animate =
        widget.active &&
        RainMotionPolicy.of(context).allowContinuous &&
        RainPerformanceScope.of(context).allowContinuousCallAnimation;
    if (_animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!_animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return widget.child;
    }
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        Positioned.fill(
          child: _animate
              ? AnimatedBuilder(
                  key: rainConnectingPulseAnimatedKey,
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _PulsePainter(
                      color: color,
                      progress: _controller.value,
                    ),
                  ),
                )
              : CustomPaint(
                  key: rainConnectingPulseStaticKey,
                  painter: _PulsePainter(color: color, progress: null),
                ),
        ),
        widget.child,
      ],
    );
  }
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter({required this.color, required this.progress});

  final Color color;

  /// Loop position 0..1, or null for the single static ring.
  final double? progress;

  static const double _maxGrowth = 0.32;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseRadius = size.shortestSide / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final loop = progress;
    if (loop == null) {
      paint.color = color.withValues(alpha: 0.24);
      canvas.drawCircle(center, baseRadius * 1.12, paint);
      return;
    }
    // Two rings half a loop apart.
    for (final offset in const <double>[0, 0.5]) {
      final t = (loop + offset) % 1;
      paint.color = color.withValues(alpha: 0.32 * (1 - t));
      canvas.drawCircle(center, baseRadius * (1 + _maxGrowth * t), paint);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
