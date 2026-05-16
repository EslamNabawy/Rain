import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum RainSoundEffect { action, error, receive, send }

class SoundEffectsService {
  final Map<RainSoundEffect, AudioPlayer> _players =
      <RainSoundEffect, AudioPlayer>{};
  bool _disabled = false;

  Future<void> play(RainSoundEffect effect) async {
    if (_disabled) {
      return;
    }

    try {
      final player = _players.putIfAbsent(
        effect,
        () => AudioPlayer(playerId: 'rain-sfx-${effect.name}'),
      );
      await player.play(
        AssetSource(_assetFor(effect)),
        volume: _volumeFor(effect),
        mode: PlayerMode.lowLatency,
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
}

String _assetFor(RainSoundEffect effect) {
  return switch (effect) {
    RainSoundEffect.action => 'sounds/action.wav',
    RainSoundEffect.error => 'sounds/error.wav',
    RainSoundEffect.receive => 'sounds/receive.wav',
    RainSoundEffect.send => 'sounds/send.wav',
  };
}

double _volumeFor(RainSoundEffect effect) {
  return switch (effect) {
    RainSoundEffect.action => 0.36,
    RainSoundEffect.error => 0.34,
    RainSoundEffect.receive => 0.32,
    RainSoundEffect.send => 0.30,
  };
}
