import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';

void main() {
  test('sound effect audio context mixes with other phone audio', () {
    expect(
      rainSoundEffectsAudioContextConfig.focus,
      AudioContextConfigFocus.mixWithOthers,
    );
    expect(
      rainSoundEffectsAudioContextConfig.route,
      AudioContextConfigRoute.system,
    );
    expect(rainSoundEffectsAudioContextConfig.respectSilence, isFalse);
    expect(rainSoundEffectsAudioContextConfig.stayAwake, isFalse);

    final context = rainSoundEffectsAudioContextConfig.build();
    expect(context.android.audioFocus, AndroidAudioFocus.none);
  });

  test('ringtone loop audio context also mixes with other phone audio', () {
    expect(
      rainSoundLoopAudioContextConfig.focus,
      AudioContextConfigFocus.mixWithOthers,
    );
    expect(
      rainSoundLoopAudioContextConfig.route,
      AudioContextConfigRoute.system,
    );
    expect(rainSoundLoopAudioContextConfig.respectSilence, isFalse);
    expect(rainSoundLoopAudioContextConfig.stayAwake, isFalse);

    final context = rainSoundLoopAudioContextConfig.build();
    expect(context.android.audioFocus, AndroidAudioFocus.none);
  });

  test('service source never requests audio focus gain for app sounds', () {
    final source = _soundEffectsServiceFile().readAsStringSync();

    expect(source, isNot(contains('AudioContextConfigFocus.gain')));
    expect(source, contains('AudioContextConfigFocus.mixWithOthers'));
  });

  test('configures each player for low-latency mixed playback', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.play(RainSoundEffect.send);

    expect(fakes, hasLength(1));
    expect(fakes.single.configuredMode, PlayerMode.lowLatency);
    expect(
      fakes.single.configuredContext,
      rainSoundEffectsAudioContextConfig.build(),
    );
    expect(fakes.single.played.single.assetPath, 'sounds/send.wav');
  });

  test('missing plugin disables SFX without crashing', () async {
    var created = 0;
    final service = SoundEffectsService(
      playerFactory: (String _) {
        created += 1;
        return _FakeRainSoundPlayer(throwOnConfigure: true);
      },
    );

    await service.play(RainSoundEffect.send);
    await service.play(RainSoundEffect.receive);

    expect(created, 1);
    expect(service.diagnostics.disabled, isTrue);
    expect(service.diagnostics.disabledReason, 'pluginUnavailable');
  });

  test('burst throttle suppresses repeated receive sounds', () async {
    var now = DateTime(2026, 5, 24, 12);
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      clock: () => now,
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.play(RainSoundEffect.receive);
    now = now.add(const Duration(milliseconds: 100));
    await service.play(RainSoundEffect.receive);
    now = now.add(const Duration(milliseconds: 600));
    await service.play(RainSoundEffect.receive);

    expect(fakes, hasLength(1));
    expect(fakes.single.played, hasLength(2));
  });

  test('active calls skip non-critical message sounds', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.play(RainSoundEffect.receive, voiceCallActive: true);
    await service.play(RainSoundEffect.send, voiceCallActive: true);
    await service.play(RainSoundEffect.action, voiceCallActive: true);

    expect(fakes, isEmpty);
  });

  test('active calls keep critical call sounds but lower volume', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.play(RainSoundEffect.mute, voiceCallActive: true);

    expect(fakes, hasLength(1));
    expect(fakes.single.played.single.assetPath, 'sounds/mute.wav');
    expect(fakes.single.played.single.volume, greaterThan(0.12));
    expect(fakes.single.played.single.volume, lessThan(0.20));
  });

  test(
    'active calls allow explicit call-control actions at lower volume',
    () async {
      final fakes = <_FakeRainSoundPlayer>[];
      final service = SoundEffectsService(
        playerFactory: (String _) {
          final fake = _FakeRainSoundPlayer();
          fakes.add(fake);
          return fake;
        },
      );

      await service.play(
        RainSoundEffect.action,
        voiceCallActive: true,
        allowDuringCall: true,
      );

      expect(fakes, hasLength(1));
      expect(fakes.single.played.single.assetPath, 'sounds/action.wav');
      expect(fakes.single.played.single.volume, greaterThan(0.18));
      expect(fakes.single.played.single.volume, lessThan(0.21));
    },
  );

  test('sound effects setting disables playback', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      settingsLoader: () => const AppAudioSettings(soundEffectsEnabled: false),
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.play(RainSoundEffect.send);

    expect(fakes, isEmpty);
  });

  test('call sounds setting disables only call sound effects', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      settingsLoader: () => const AppAudioSettings(callSoundsEnabled: false),
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.play(RainSoundEffect.callIncoming);
    await service.play(RainSoundEffect.send);

    expect(fakes, hasLength(1));
    expect(fakes.single.played.single.assetPath, 'sounds/send.wav');
  });

  test('sound effects volume scales playback volume', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      settingsLoader: () => const AppAudioSettings(soundEffectsVolume: 0.25),
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.play(RainSoundEffect.send);

    expect(fakes, hasLength(1));
    expect(fakes.single.played.single.volume, closeTo(0.075, 0.0001));
  });

  test('startLoop starts one low-latency looping player', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      settingsLoader: () => const AppAudioSettings(soundEffectsVolume: 0.5),
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming',
      volume: 0.42,
    );

    expect(fakes, hasLength(1));
    expect(fakes.single.configuredMode, PlayerMode.lowLatency);
    expect(fakes.single.releaseMode, ReleaseMode.loop);
    expect(
      fakes.single.configuredContext,
      rainSoundLoopAudioContextConfig.build(),
    );
    expect(
      fakes.single.played.single.assetPath,
      'sounds/call_incoming_loop.wav',
    );
    expect(fakes.single.played.single.volume, closeTo(0.21, 0.0001));
    expect(fakes.single.stopped, isFalse);
    expect(fakes.single.disposed, isFalse);
  });

  test('startLoop is idempotent for the same loop id and effect', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming',
      volume: 0.42,
    );
    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming',
      volume: 0.42,
    );

    expect(fakes, hasLength(1));
    expect(fakes.single.played, hasLength(1));
  });

  test('startLoop replaces an existing loop for the same effect', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming-1',
      volume: 0.42,
    );
    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming-2',
      volume: 0.42,
    );

    expect(fakes, hasLength(2));
    expect(fakes.first.stopped, isTrue);
    expect(fakes.first.disposed, isTrue);
    expect(fakes.last.played.single.assetPath, 'sounds/call_incoming_loop.wav');
  });

  test('stopLoop stops and disposes the loop player', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.startLoop(
      RainSoundEffect.callOutgoing,
      loopId: 'outgoing',
      volume: 0.34,
    );
    await service.stopLoop('outgoing');

    expect(fakes.single.stopped, isTrue);
    expect(fakes.single.disposed, isTrue);
  });

  test('disabled sound settings stop active loops', () async {
    var settings = const AppAudioSettings();
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      settingsLoader: () => settings,
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming',
      volume: 0.42,
    );
    settings = const AppAudioSettings(soundEffectsEnabled: false);
    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming',
      volume: 0.42,
    );

    expect(fakes, hasLength(1));
    expect(fakes.single.stopped, isTrue);
    expect(fakes.single.disposed, isTrue);
  });

  test('disabled call sounds stop active call loops', () async {
    var settings = const AppAudioSettings();
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      settingsLoader: () => settings,
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming',
      volume: 0.42,
    );
    settings = const AppAudioSettings(callSoundsEnabled: false);
    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming',
      volume: 0.42,
    );

    expect(fakes, hasLength(1));
    expect(fakes.single.stopped, isTrue);
    expect(fakes.single.disposed, isTrue);
  });

  test('dispose stops loops and disposes one-shot players', () async {
    final fakes = <_FakeRainSoundPlayer>[];
    final service = SoundEffectsService(
      playerFactory: (String _) {
        final fake = _FakeRainSoundPlayer();
        fakes.add(fake);
        return fake;
      },
    );

    await service.play(RainSoundEffect.send);
    await service.startLoop(
      RainSoundEffect.callIncoming,
      loopId: 'incoming',
      volume: 0.42,
    );
    await service.dispose();

    expect(fakes, hasLength(2));
    expect(fakes.first.stopped, isFalse);
    expect(fakes.first.disposed, isTrue);
    expect(fakes.last.stopped, isTrue);
    expect(fakes.last.disposed, isTrue);
  });

  test('asset map covers every sound effect', () {
    expect(rainSoundEffectAssetPaths.keys, containsAll(RainSoundEffect.values));
    expect(
      rainSoundEffectAssetPaths.values.toSet(),
      hasLength(RainSoundEffect.values.length),
    );
  });

  test('sound effect asset paths point to non-empty bundled files', () {
    final assetPaths = <String>{
      ...rainSoundEffectAssetPaths.values,
      ...rainSoundEffectLoopAssetPaths.values,
    };

    for (final assetPath in assetPaths) {
      final file = _soundAssetFile(assetPath);

      expect(file.existsSync(), isTrue, reason: assetPath);
      expect(file.lengthSync(), greaterThan(44), reason: assetPath);
    }
  });

  test('loop asset map covers ringtone and ringback effects', () {
    expect(
      rainSoundEffectLoopAssetPaths.keys,
      containsAll(<RainSoundEffect>[
        RainSoundEffect.callIncoming,
        RainSoundEffect.callOutgoing,
      ]),
    );
    expect(
      rainSoundEffectLoopAssetPaths.values.toSet(),
      hasLength(rainSoundEffectLoopAssetPaths.length),
    );
    expect(
      rainSoundEffectAssetPaths.values.toSet().intersection(
        rainSoundEffectLoopAssetPaths.values.toSet(),
      ),
      isEmpty,
    );
  });
}

File _soundEffectsServiceFile() {
  for (final path in <String>[
    'lib/infrastructure/services/sound_effects_service.dart',
    'apps/rain/lib/infrastructure/services/sound_effects_service.dart',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  fail('Could not locate sound_effects_service.dart.');
}

File _soundAssetFile(String assetPath) {
  for (final path in <String>[
    'assets/$assetPath',
    'apps/rain/assets/$assetPath',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  return File('apps/rain/assets/$assetPath');
}

class _PlayedSound {
  const _PlayedSound({required this.assetPath, required this.volume});

  final String assetPath;
  final double volume;
}

class _FakeRainSoundPlayer implements RainSoundPlayer {
  _FakeRainSoundPlayer({this.throwOnConfigure = false});

  final bool throwOnConfigure;
  final List<_PlayedSound> played = <_PlayedSound>[];
  PlayerMode? configuredMode;
  AudioContext? configuredContext;
  ReleaseMode? releaseMode;
  var stopped = false;
  var disposed = false;

  @override
  Future<void> configure({
    required PlayerMode mode,
    required AudioContext context,
  }) async {
    if (throwOnConfigure) {
      throw MissingPluginException('audioplayers unavailable');
    }
    configuredMode = mode;
    configuredContext = context;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> playAsset(String assetPath, {required double volume}) async {
    played.add(_PlayedSound(assetPath: assetPath, volume: volume));
  }

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    releaseMode = mode;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
