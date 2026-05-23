import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum RainSoundEffect {
  send,
  receive,
  action,
  error,
  callIncoming,
  callOutgoing,
  callConnected,
  callEnded,
  callFailed,
  mute,
  unmute,
  deafen,
  undeafen,
}

typedef RainSoundPlayerFactory = RainSoundPlayer Function(String playerId);

final AudioContextConfig rainSoundEffectsAudioContextConfig =
    AudioContextConfig(
      route: AudioContextConfigRoute.system,
      focus: AudioContextConfigFocus.mixWithOthers,
      respectSilence: false,
      stayAwake: false,
    );

const Map<RainSoundEffect, String> rainSoundEffectAssetPaths =
    <RainSoundEffect, String>{
      RainSoundEffect.send: 'sounds/send.wav',
      RainSoundEffect.receive: 'sounds/receive.wav',
      RainSoundEffect.action: 'sounds/action.wav',
      RainSoundEffect.error: 'sounds/error.wav',
      RainSoundEffect.callIncoming: 'sounds/call_incoming.wav',
      RainSoundEffect.callOutgoing: 'sounds/call_outgoing.wav',
      RainSoundEffect.callConnected: 'sounds/call_connected.wav',
      RainSoundEffect.callEnded: 'sounds/call_ended.wav',
      RainSoundEffect.callFailed: 'sounds/call_failed.wav',
      RainSoundEffect.mute: 'sounds/mute.wav',
      RainSoundEffect.unmute: 'sounds/unmute.wav',
      RainSoundEffect.deafen: 'sounds/deafen.wav',
      RainSoundEffect.undeafen: 'sounds/undeafen.wav',
    };

abstract interface class RainSoundPlayer {
  Future<void> configure({
    required PlayerMode mode,
    required AudioContext context,
  });

  Future<void> playAsset(String assetPath, {required double volume});

  Future<void> dispose();
}

class AudioplayersRainSoundPlayer implements RainSoundPlayer {
  AudioplayersRainSoundPlayer(this._player);

  final AudioPlayer _player;
  bool _configured = false;

  @override
  Future<void> configure({
    required PlayerMode mode,
    required AudioContext context,
  }) async {
    if (_configured) {
      return;
    }
    await _player.setPlayerMode(mode);
    await _player.setAudioContext(context);
    _configured = true;
  }

  @override
  Future<void> playAsset(String assetPath, {required double volume}) {
    return _player.play(AssetSource(assetPath), volume: volume);
  }

  @override
  Future<void> dispose() => _player.dispose();
}

class SoundEffectsService {
  SoundEffectsService({
    RainSoundPlayerFactory? playerFactory,
    DateTime Function()? clock,
    AudioContext? audioContext,
  }) : _playerFactory =
           playerFactory ??
           ((String playerId) =>
               AudioplayersRainSoundPlayer(AudioPlayer(playerId: playerId))),
       _clock = clock ?? DateTime.now,
       _audioContext =
           audioContext ?? rainSoundEffectsAudioContextConfig.build();

  final RainSoundPlayerFactory _playerFactory;
  final DateTime Function() _clock;
  final AudioContext _audioContext;
  final Map<RainSoundEffect, RainSoundPlayer> _players =
      <RainSoundEffect, RainSoundPlayer>{};
  final Map<RainSoundEffect, DateTime> _lastPlayedAt =
      <RainSoundEffect, DateTime>{};
  bool _disabled = false;

  Future<void> play(
    RainSoundEffect effect, {
    bool voiceCallActive = false,
  }) async {
    if (_disabled) {
      return;
    }
    if (!_shouldPlayInCurrentContext(effect, voiceCallActive)) {
      return;
    }
    final now = _clock();
    if (_isThrottled(effect, now)) {
      return;
    }
    _lastPlayedAt[effect] = now;

    try {
      final player = _players.putIfAbsent(
        effect,
        () => _playerFactory('rain-sfx-${effect.name}'),
      );
      await player.configure(
        mode: PlayerMode.lowLatency,
        context: _audioContext,
      );
      await player.playAsset(
        _assetFor(effect),
        volume: _volumeFor(effect, voiceCallActive: voiceCallActive),
      );
    } on MissingPluginException {
      _disabled = true;
    } catch (error) {
      _disabled = true;
      debugPrint('Rain sound effects disabled: $error');
    }
  }

  Future<void> dispose() async {
    final players = _players.values.toList(growable: false);
    _players.clear();
    await Future.wait(players.map((player) => player.dispose()));
  }

  bool _isThrottled(RainSoundEffect effect, DateTime now) {
    final interval = _throttleFor(effect);
    if (interval == Duration.zero) {
      return false;
    }
    final lastPlayedAt = _lastPlayedAt[effect];
    return lastPlayedAt != null && now.difference(lastPlayedAt) < interval;
  }
}

String _assetFor(RainSoundEffect effect) {
  return rainSoundEffectAssetPaths[effect]!;
}

double _volumeFor(RainSoundEffect effect, {required bool voiceCallActive}) {
  final baseVolume = switch (effect) {
    RainSoundEffect.send => 0.30,
    RainSoundEffect.receive => 0.32,
    RainSoundEffect.action => 0.36,
    RainSoundEffect.error => 0.34,
    RainSoundEffect.callIncoming => 0.42,
    RainSoundEffect.callOutgoing => 0.34,
    RainSoundEffect.callConnected => 0.34,
    RainSoundEffect.callEnded => 0.30,
    RainSoundEffect.callFailed => 0.34,
    RainSoundEffect.mute => 0.26,
    RainSoundEffect.unmute => 0.28,
    RainSoundEffect.deafen => 0.26,
    RainSoundEffect.undeafen => 0.28,
  };
  if (!voiceCallActive || !_isCriticalCallEffect(effect)) {
    return baseVolume;
  }
  return baseVolume * 0.55;
}

Duration _throttleFor(RainSoundEffect effect) {
  return switch (effect) {
    RainSoundEffect.send => const Duration(milliseconds: 160),
    RainSoundEffect.receive => const Duration(milliseconds: 520),
    RainSoundEffect.action => const Duration(milliseconds: 140),
    RainSoundEffect.error => const Duration(milliseconds: 420),
    RainSoundEffect.callIncoming => const Duration(milliseconds: 900),
    RainSoundEffect.callOutgoing => const Duration(milliseconds: 900),
    RainSoundEffect.callConnected => const Duration(milliseconds: 260),
    RainSoundEffect.callEnded => const Duration(milliseconds: 260),
    RainSoundEffect.callFailed => const Duration(milliseconds: 520),
    RainSoundEffect.mute => const Duration(milliseconds: 140),
    RainSoundEffect.unmute => const Duration(milliseconds: 140),
    RainSoundEffect.deafen => const Duration(milliseconds: 140),
    RainSoundEffect.undeafen => const Duration(milliseconds: 140),
  };
}

bool _shouldPlayInCurrentContext(RainSoundEffect effect, bool voiceCallActive) {
  if (!voiceCallActive) {
    return true;
  }
  return _isCriticalCallEffect(effect);
}

bool _isCriticalCallEffect(RainSoundEffect effect) {
  return switch (effect) {
    RainSoundEffect.callIncoming ||
    RainSoundEffect.callOutgoing ||
    RainSoundEffect.callConnected ||
    RainSoundEffect.callEnded ||
    RainSoundEffect.callFailed ||
    RainSoundEffect.mute ||
    RainSoundEffect.unmute ||
    RainSoundEffect.deafen ||
    RainSoundEffect.undeafen ||
    RainSoundEffect.error => true,
    RainSoundEffect.send ||
    RainSoundEffect.receive ||
    RainSoundEffect.action => false,
  };
}
