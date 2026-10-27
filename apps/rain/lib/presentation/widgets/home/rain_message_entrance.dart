/// # rain_message_entrance.dart
///
/// Gentle fade and 8 px side slide for messages that arrive while the chat is
/// open. Messages present on first load render without animation.
///
/// **Key types:** RainMessageEntrance
///
/// **Depends on:** RainMotion, RainMotionPolicy
library;

import 'package:flutter/widgets.dart';

import 'package:rain/presentation/performance/rain_motion_policy.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

class RainMessageEntrance extends StatefulWidget {
  const RainMessageEntrance({
    super.key,
    required this.child,
    required this.animate,
    required this.isOutgoing,
  });

  final Widget child;

  /// Read once when the row mounts; later rebuilds never restart or cancel
  /// the entrance, and the widget tree shape never changes.
  final bool animate;
  final bool isOutgoing;

  @override
  State<RainMessageEntrance> createState() => _RainMessageEntranceState();
}

class _RainMessageEntranceState extends State<RainMessageEntrance> {
  late final bool _play = widget.animate;

  @override
  Widget build(BuildContext context) {
    final policy = RainMotionPolicy.of(context);
    final play = _play && !policy.reduced;
    final side = widget.isOutgoing ? 8.0 : -8.0;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: play ? 0 : 1, end: 1),
      duration: play ? RainMotion.messageEnter : Duration.zero,
      curve: RainMotion.enter,
      child: widget.child,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(side * (1 - t), 0),
            child: child,
          ),
        );
      },
    );
  }
}
