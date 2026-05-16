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
