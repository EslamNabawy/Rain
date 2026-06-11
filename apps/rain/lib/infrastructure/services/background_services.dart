/// # background_services.dart
///
/// [BackgroundServices] is a stub/placeholder for Rain's background execution
/// support (workmanager tasks, Android foreground service). Currently no-op
/// with entry-point annotations reserved for future implementation.
///
/// **Key types:** [BackgroundServices]
///
/// **Depends on:** (none — placeholder)

import 'dart:async';

@pragma('vm:entry-point')
void onRainWorkmanagerTaskStart() {}

@pragma('vm:entry-point')
Future<void> onRainBackgroundServiceStart(Object service) async {}

class BackgroundServices {
  BackgroundServices._();

  static final BackgroundServices instance = BackgroundServices._();

  Future<void> initialize() async {}

  Future<void> start() async {}

  Future<void> stop() async {}
}
