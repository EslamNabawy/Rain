import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:rain/presentation/performance/rain_motion_policy.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

/// Shows nothing until [delay] has passed, then fades [child] in. Keeps quick
/// loads from flashing a skeleton or spinner.
class RainDelayedReveal extends StatefulWidget {
  const RainDelayedReveal({
    super.key,
    required this.child,
    this.delay = RainMotion.loadingRevealDelay,
  });

  final Widget child;
  final Duration delay;

  @override
  State<RainDelayedReveal> createState() => _RainDelayedRevealState();
}

class _RainDelayedRevealState extends State<RainDelayedReveal> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: RainMotionPolicy.of(context).d(RainMotion.standard),
      child: widget.child,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(opacity: value, child: child);
      },
    );
  }
}
