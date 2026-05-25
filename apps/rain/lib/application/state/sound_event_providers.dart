import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/audio/sound_event_router.dart';
import 'package:rain/application/runtime/app_exit_coordinator.dart';

import 'core_providers.dart';
import 'runtime_providers.dart';

final soundEventRouterProvider = Provider<SoundEventRouter>((Ref ref) {
  final router = SoundEventRouter(
    effects: ref.watch(soundEffectsProvider),
    settingsLoader: ref.watch(appSettingsStoreProvider).loadAudioSettings,
    callStateReader: () => ref.read(voiceCallProvider),
  );
  final exitRegistration = AppExitCoordinator.instance.register(
    (_) => router.stopAllForAppExit(),
  );
  ref.onDispose(() {
    exitRegistration.unregister();
    unawaited(router.dispose());
  });
  return router;
});
