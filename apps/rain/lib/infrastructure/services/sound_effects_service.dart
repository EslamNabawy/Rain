import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_settings_store.dart';

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
typedef RainSoundSettingsLoader = FutureOr<AppAudioSettings> Function();

final AudioContextConfig rainSoundEffectsAudioContextConfig =
    AudioContextConfig(
      route: AudioContextConfigRoute.system,
      focus: AudioContextConfigFocus.mixWithOthers,
      respectSilence: false,
      stayAwake: false,
    );

final AudioContextConfig rainSoundLoopAudioContextConfig = AudioContextConfig(
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

const Map<RainSoundEffect, String> rainSoundEffectLoopAssetPaths =
    <RainSoundEffect, String>{
      RainSoundEffect.callIncoming: 'sounds/call_incoming_loop.wav',
      RainSoundEffect.callOutgoing: 'sounds/call_outgoing_loop.wav',
    };

abstract interface class RainSoundPlayer {
  Future<void> configure({
    required PlayerMode mode,
    required AudioContext context,
  });

  Future<void> playAsset(String assetPath, {required double volume});

  Future<void> setReleaseMode(ReleaseMode mode);

  Future<void> stop();

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
  Future<void> setReleaseMode(ReleaseMode mode) {
    return _player.setReleaseMode(mode);
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

class SoundEffectsService {
  SoundEffectsService({
    RainSoundPlayerFactory? playerFactory,
    RainSoundSettingsLoader? settingsLoader,
    DateTime Function()? clock,
    AudioContext? audioContext,
    AudioContext? loopAudioContext,
  }) : _playerFactory =
           playerFactory ??
           ((String playerId) =>
               AudioplayersRainSoundPlayer(AudioPlayer(playerId: playerId))),
       _settingsLoader = settingsLoader ?? (() => const AppAudioSettings()),
       _clock = clock ?? DateTime.now,
       _effectAudioContext =
           audioContext ?? rainSoundEffectsAudioContextConfig.build(),
       _loopAudioContext =
           loopAudioContext ??
           audioContext ??
           rainSoundLoopAudioContextConfig.build();

  final RainSoundPlayerFactory _playerFactory;
  final RainSoundSettingsLoader _settingsLoader;
  final DateTime Function() _clock;
  final AudioContext _effectAudioContext;
  final AudioContext _loopAudioContext;
  final Map<RainSoundEffect, RainSoundPlayer> _players =
      <RainSoundEffect, RainSoundPlayer>{};
  final Map<String, RainSoundPlayer> _loopPlayers = <String, RainSoundPlayer>{};
  final Map<String, RainSoundEffect> _loopEffects = <String, RainSoundEffect>{};
  final Map<RainSoundEffect, DateTime> _lastPlayedAt =
      <RainSoundEffect, DateTime>{};
  bool _disabled = false;
  String? _disabledReason;
  String? _lastFailureReason;

  SoundEffectsDiagnostics get diagnostics {
    return SoundEffectsDiagnostics(
      disabled: _disabled,
      disabledReason: _disabledReason,
      lastFailureReason: _lastFailureReason,
      activeLoopIds: Set<String>.unmodifiable(_loopPlayers.keys),
    );
  }

  Future<void> play(
    RainSoundEffect effect, {
    bool voiceCallActive = false,
    bool allowDuringCall = false,
    double volumeScale = 1.0,
  }) async {
    if (_disabled) {
      return;
    }
    late final AppAudioSettings settings;
    try {
      settings = await Future<AppAudioSettings>.value(_settingsLoader());
    } catch (error) {
      _recordFailure('settingsUnavailable');
      debugPrint('Rain sound effect skipped: $error');
      return;
    }
    if (!settings.soundEffectsEnabled) {
      await stopAllLoops();
      return;
    }
    if (!settings.callSoundsEnabled && _isCallSoundEffect(effect)) {
      await stopAllLoops();
      return;
    }
    final reduceDuringCall = voiceCallActive && settings.reduceSoundsDuringCall;
    if (!_shouldPlayInCurrentContext(
      effect,
      reduceDuringCall,
      allowDuringCall: allowDuringCall,
    )) {
      return;
    }
    final now = _clock();
    if (_isThrottled(effect, now)) {
      return;
    }

    RainSoundPlayer? player;
    try {
      player = _players.putIfAbsent(
        effect,
        () => _playerFactory('rain-sfx-${effect.name}'),
      );
      await player.configure(
        mode: PlayerMode.lowLatency,
        context: _effectAudioContext,
      );
      await player.playAsset(
        _assetFor(effect),
        volume:
            _volumeFor(
              effect,
              voiceCallActive: reduceDuringCall,
              allowDuringCall: allowDuringCall,
            ) *
            settings.soundEffectsVolume *
            volumeScale.clamp(0.0, 1.0).toDouble(),
      );
      _lastPlayedAt[effect] = now;
    } on MissingPluginException {
      _disable('pluginUnavailable');
      await stopAllLoops();
    } catch (error) {
      _recordFailure('playbackFailed');
      if (player != null && identical(_players[effect], player)) {
        _players.remove(effect);
        await _disposeOneShotPlayer(player);
      }
      debugPrint('Rain sound effect skipped: $error');
    }
  }

  Future<void> startLoop(
    RainSoundEffect effect, {
    required String loopId,
    required double volume,
  }) async {
    final normalizedLoopId = loopId.trim();
    if (normalizedLoopId.isEmpty) {
      throw ArgumentError.value(loopId, 'loopId', 'must not be blank');
    }
    if (_disabled) {
      return;
    }
    late final AppAudioSettings settings;
    try {
      settings = await Future<AppAudioSettings>.value(_settingsLoader());
    } catch (error) {
      _recordFailure('settingsUnavailable');
      debugPrint('Rain sound loop skipped: $error');
      return;
    }
    if (!settings.soundEffectsEnabled) {
      await stopAllLoops();
      return;
    }
    if (!settings.callSoundsEnabled && _isCallSoundEffect(effect)) {
      await stopAllLoops();
      return;
    }

    final existingEffect = _loopEffects[normalizedLoopId];
    if (existingEffect == effect) {
      return;
    }
    if (existingEffect != null) {
      await stopLoop(normalizedLoopId);
    }

    final existingLoopForEffect = _loopIdForEffect(effect);
    if (existingLoopForEffect != null &&
        existingLoopForEffect != normalizedLoopId) {
      await stopLoop(existingLoopForEffect);
    }

    final player = _playerFactory(_loopPlayerId(normalizedLoopId));
    _loopPlayers[normalizedLoopId] = player;
    _loopEffects[normalizedLoopId] = effect;
    try {
      await player.configure(
        mode: PlayerMode.lowLatency,
        context: _loopAudioContext,
      );
      await player.setReleaseMode(ReleaseMode.loop);
      await player.playAsset(
        _loopAssetFor(effect),
        volume: volume.clamp(0.0, 1.0).toDouble() * settings.soundEffectsVolume,
      );
    } on MissingPluginException {
      _disable('pluginUnavailable');
      _loopPlayers.remove(normalizedLoopId);
      _loopEffects.remove(normalizedLoopId);
      await _stopAndDisposeLoopPlayer(player);
      await stopAllLoops();
    } catch (error) {
      _recordFailure('loopPlaybackFailed');
      _loopPlayers.remove(normalizedLoopId);
      _loopEffects.remove(normalizedLoopId);
      await _stopAndDisposeLoopPlayer(player);
      debugPrint('Rain sound loop skipped: $error');
    }
  }

  Future<void> stopLoop(String loopId) async {
    final normalizedLoopId = loopId.trim();
    if (normalizedLoopId.isEmpty) {
      return;
    }
    final player = _loopPlayers.remove(normalizedLoopId);
    _loopEffects.remove(normalizedLoopId);
    if (player == null) {
      return;
    }
    await _stopAndDisposeLoopPlayer(player);
  }

  Future<void> stopAllLoops() async {
    final players = _loopPlayers.values.toList(growable: false);
    _loopPlayers.clear();
    _loopEffects.clear();
    await Future.wait(players.map(_stopAndDisposeLoopPlayer));
  }

  Future<void> stopAll() async {
    await stopAllLoops();
    final players = _players.values.toList(growable: false);
    _players.clear();
    _lastPlayedAt.clear();
    await Future.wait(players.map(_stopAndDisposeOneShotPlayer));
  }

  Future<void> dispose() async {
    await stopAll();
  }

  bool _isThrottled(RainSoundEffect effect, DateTime now) {
    final interval = _throttleFor(effect);
    if (interval == Duration.zero) {
      return false;
    }
    final lastPlayedAt = _lastPlayedAt[effect];
    return lastPlayedAt != null && now.difference(lastPlayedAt) < interval;
  }

  String? _loopIdForEffect(RainSoundEffect effect) {
    for (final entry in _loopEffects.entries) {
      if (entry.value == effect) {
        return entry.key;
      }
    }
    return null;
  }

  void _disable(String reason) {
    _disabled = true;
    _disabledReason = reason;
    _recordFailure(reason);
  }

  void _recordFailure(String reason) {
    _lastFailureReason = reason;
  }
}

final class SoundEffectsDiagnostics {
  const SoundEffectsDiagnostics({
    required this.disabled,
    required this.disabledReason,
    required this.lastFailureReason,
    required this.activeLoopIds,
  });

  final bool disabled;
  final String? disabledReason;
  final String? lastFailureReason;
  final Set<String> activeLoopIds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'disabled': disabled,
      'disabledReason': disabledReason,
      'lastFailureReason': lastFailureReason,
      'activeLoopIds': activeLoopIds.toList(growable: false)..sort(),
    };
  }
}

Future<void> _disposeOneShotPlayer(RainSoundPlayer player) async {
  try {
    await player.dispose();
  } catch (error) {
    debugPrint('Rain sound player dispose ignored: $error');
  }
}

Future<void> _stopAndDisposeOneShotPlayer(RainSoundPlayer player) async {
  try {
    await player.stop();
  } catch (error) {
    debugPrint('Rain sound player stop ignored: $error');
  }
  await _disposeOneShotPlayer(player);
}

Future<void> _stopAndDisposeLoopPlayer(RainSoundPlayer player) async {
  try {
    await player.stop();
  } catch (error) {
    debugPrint('Rain sound loop stop ignored: $error');
  }
  try {
    await player.dispose();
  } catch (error) {
    debugPrint('Rain sound loop dispose ignored: $error');
  }
}

String _loopPlayerId(String loopId) {
  final safeLoopId = loopId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-');
  return 'rain-loop-$safeLoopId';
}

String _assetFor(RainSoundEffect effect) {
  return rainSoundEffectAssetPaths[effect]!;
}

String _loopAssetFor(RainSoundEffect effect) {
  return rainSoundEffectLoopAssetPaths[effect] ?? _assetFor(effect);
}

double _volumeFor(
  RainSoundEffect effect, {
  required bool voiceCallActive,
  required bool allowDuringCall,
}) {
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
  if (!voiceCallActive ||
      (!_isCriticalCallEffect(effect) && !allowDuringCall)) {
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

bool _shouldPlayInCurrentContext(
  RainSoundEffect effect,
  bool voiceCallActive, {
  required bool allowDuringCall,
}) {
  if (!voiceCallActive) {
    return true;
  }
  return allowDuringCall || _isCriticalCallEffect(effect);
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

bool _isCallSoundEffect(RainSoundEffect effect) {
  return switch (effect) {
    RainSoundEffect.callIncoming ||
    RainSoundEffect.callOutgoing ||
    RainSoundEffect.callConnected ||
    RainSoundEffect.callEnded ||
    RainSoundEffect.callFailed ||
    RainSoundEffect.mute ||
    RainSoundEffect.unmute ||
    RainSoundEffect.deafen ||
    RainSoundEffect.undeafen => true,
    RainSoundEffect.send ||
    RainSoundEffect.receive ||
    RainSoundEffect.action ||
    RainSoundEffect.error => false,
  };
}
