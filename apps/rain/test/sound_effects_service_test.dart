import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('service source never requests audio focus gain for short SFX', () {
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

  test('asset map covers every sound effect', () {
    expect(rainSoundEffectAssetPaths.keys, containsAll(RainSoundEffect.values));
    expect(
      rainSoundEffectAssetPaths.values.toSet(),
      hasLength(RainSoundEffect.values.length),
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
}
