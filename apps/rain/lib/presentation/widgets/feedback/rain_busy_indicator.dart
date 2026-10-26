import 'package:flutter/material.dart';
import 'package:rain/presentation/performance/rain_motion_policy.dart';

/// Small progress ring used for inline busy states (buttons, list tiles,
/// status chips). Shows a static three-quarter ring under reduced motion.
class RainBusyIndicator extends StatelessWidget {
  const RainBusyIndicator({
    super.key,
    this.size = 16,
    this.color,
    this.semanticsLabel,
  });

  final double size;
  final Color? color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final reduced = RainMotionPolicy.of(context).reduced;
    return Semantics(
      label: semanticsLabel ?? 'Loading',
      child: SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(
          strokeWidth: size / 8,
          color: color ?? Theme.of(context).colorScheme.primary,
          value: reduced ? 0.75 : null,
        ),
      ),
    );
  }
}
