import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/application/runtime/media_device_settings.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/crash_diagnostics_service.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'package:rain/infrastructure/services/received_file_export_service.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';
import 'package:rain/infrastructure/services/turn_credential_service.dart';

final appBootstrapProvider = Provider<AppBootstrapState>(
  (_) => throw UnimplementedError('AppBootstrapState has not been overridden.'),
);

final appEnvironmentProvider = Provider(
  (Ref ref) => ref.watch(appBootstrapProvider).environment,
);

final databaseProvider = Provider<RainDatabase>(
  (Ref ref) => ref.watch(appBootstrapProvider).database,
);

final adapterProvider = Provider<SignalingAdapter>(
  (Ref ref) => ref.watch(appBootstrapProvider).adapter,
);

final forceUpdateServiceProvider = Provider(
  (Ref ref) => ref.watch(appBootstrapProvider).forceUpdateService,
);

final networkStatusServiceProvider = Provider((Ref ref) {
  final bootstrap = ref.watch(appBootstrapProvider);
  final firebaseDatabase = bootstrap.firebaseDatabase;
  return NetworkStatusService(
    connectivityProbe: ConnectivityPlusProbe(),
    backendProbe: firebaseDatabase == null
        ? const AlwaysConnectedBackendProbe()
        : FirebaseBackendConnectivityProbe(firebaseDatabase),
  );
});

final networkStatusProvider = StreamProvider<NetworkStatusState>((Ref ref) {
  return ref.watch(networkStatusServiceProvider).watch();
});

final soundEffectsProvider = Provider<SoundEffectsService>((Ref ref) {
  final service = SoundEffectsService(
    settingsLoader: ref.watch(appSettingsStoreProvider).loadAudioSettings,
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final appSettingsStoreProvider = Provider((Ref ref) => AppSettingsStore());

final platformBridgeProvider = Provider<PlatformBridge>(
  (Ref ref) => FlutterWebRTCBridge(),
);

final mediaDeviceSettingsProvider = Provider<MediaDeviceSettings>((Ref ref) {
  return MediaDeviceSettings(
    platformBridge: ref.watch(platformBridgeProvider),
    settingsStore: ref.watch(appSettingsStoreProvider),
  );
});

void assertNetworkReady(Ref ref) {
  final status = ref.read(networkStatusProvider).value;
  if (status != null && status.blocksNetworkActions) {
    throw StateError(status.actionErrorMessage);
  }
}

final friendStoreProvider = Provider(
  (Ref ref) => FriendStore(ref.watch(databaseProvider)),
);

final messageStoreProvider = Provider(
  (Ref ref) => MessageStore(ref.watch(databaseProvider)),
);

final offlineQueueStoreProvider = Provider(
  (Ref ref) => OfflineQueueStore(ref.watch(databaseProvider)),
);

final fileTransferStoreProvider = Provider(
  (Ref ref) => FileTransferStore(ref.watch(databaseProvider)),
);

final receivedFileExportServiceProvider = Provider(
  (Ref ref) => ReceivedFileExportService(),
);

final crashDiagnosticsServiceProvider = Provider<CrashDiagnosticsService>(
  (Ref ref) => CrashDiagnosticsService.instance,
);

final lastCrashDiagnosticsProvider = FutureProvider<CrashDiagnosticsRecord?>((
  Ref ref,
) {
  return ref.watch(crashDiagnosticsServiceProvider).loadLastCrash();
});

final connectionMemoryStoreProvider = Provider(
  (Ref ref) => DriftConnectionMemoryStore(ref.watch(databaseProvider)),
);

final turnCredentialServiceProvider = Provider<TurnCredentialService>((
  Ref ref,
) {
  final environment = ref.watch(appEnvironmentProvider);
  final service = TurnCredentialService(
    baseIceServers: environment.iceServers,
    brokerUrl: environment.turnBrokerUrl,
  );
  ref.onDispose(service.dispose);
  return service;
});

final messageDeliveryServiceProvider = Provider((Ref ref) {
  final service = MessageDeliveryService(
    messageStore: ref.watch(messageStoreProvider),
    offlineQueueStore: ref.watch(offlineQueueStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final forceUpdateProvider =
    AsyncNotifierProvider<ForceUpdateController, ForceUpdateResult>(
      ForceUpdateController.new,
    );

class ForceUpdateController extends AsyncNotifier<ForceUpdateResult> {
  @override
  Future<ForceUpdateResult> build() {
    final networkStatus = ref.watch(networkStatusProvider).value;
    if (networkStatus != null && networkStatus.blocksNetworkActions) {
      return ref.watch(forceUpdateServiceProvider).checkUnavailable();
    }
    return ref.watch(forceUpdateServiceProvider).check();
  }
}
