import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void rainBackgroundCallbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? inputData) async {
    return Future<bool>.value(true);
  });
}

@pragma('vm:entry-point')
void onRainBackgroundServiceStart(ServiceInstance service) {}

class BackgroundServices {
  Future<void> initialize() async {
    if (!Platform.isAndroid) {
      return;
    }

    await Workmanager().initialize(
      rainBackgroundCallbackDispatcher,
    );
    await Workmanager().registerPeriodicTask(
      'presenceHeartbeat',
      'heartbeatTask',
      frequency: const Duration(minutes: 3),
      constraints: Constraints(networkType: NetworkType.connected),
    );

    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onRainBackgroundServiceStart,
        isForegroundMode: true,
        autoStartOnBoot: false,
        initialNotificationTitle: 'Rain is running',
        initialNotificationContent: 'Keeping your connection alive',
        foregroundServiceTypes: <AndroidForegroundType>[
          AndroidForegroundType.dataSync,
          AndroidForegroundType.remoteMessaging,
        ],
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );
  }
}
