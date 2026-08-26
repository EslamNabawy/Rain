/// # sound_event_providers.dart
///
/// Riverpod provider for [SoundEventRouter]. Wires the router to the sound
/// effects service, audio settings, and voice call state. Registers an
/// app-exit handler to stop all sounds on shutdown.
///
/// **Key types:** (provider only)
///
/// **Depends on:** sound event router, core providers, runtime providers
library;

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
