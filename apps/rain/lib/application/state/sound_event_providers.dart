import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/audio/sound_event_router.dart';

import 'core_providers.dart';
import 'runtime_providers.dart';

final soundEventRouterProvider = Provider<SoundEventRouter>((Ref ref) {
  final router = SoundEventRouter(
    effects: ref.watch(soundEffectsProvider),
    settingsLoader: ref.watch(appSettingsStoreProvider).loadAudioSettings,
    callStateReader: () => ref.read(voiceCallProvider),
  );
  ref.onDispose(() => unawaited(router.dispose()));
  return router;
});
