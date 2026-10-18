import 'package:flutter/widgets.dart';

import 'rain_performance.dart';

/// One answer to "may this widget animate?" for all of presentation/.
///
/// Reduced when the OS asks for fewer animations or the device is in the
/// low-power performance tier. Reduced code renders the end state with
/// [Duration.zero] and starts no repeating ticker.
class RainMotionPolicy {
  const RainMotionPolicy({required this.reduced});

  /// Subscribes to media-query and performance changes. Use inside `build`.
  factory RainMotionPolicy.of(BuildContext context) {
    return RainMotionPolicy(
      reduced:
          MediaQuery.maybeOf(context)?.disableAnimations == true ||
          RainPerformanceScope.of(context).isLowPower,
    );
  }

  /// Reads the current values without subscribing. Use outside `build`
  /// where the caller re-syncs on its own lifecycle hooks.
  factory RainMotionPolicy.read(BuildContext context) {
    return RainMotionPolicy(
      reduced:
          MediaQuery.maybeOf(context)?.disableAnimations == true ||
          RainPerformanceScope.read(context).isLowPower,
    );
  }

  final bool reduced;

  bool get allowContinuous => !reduced;

  Duration d(Duration normal) => reduced ? Duration.zero : normal;
}
