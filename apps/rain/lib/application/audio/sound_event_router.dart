import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';

import 'rain_sound_event.dart';

typedef VoiceCallStateReader = VoiceCallState Function();

final class SoundEventRouter {
  SoundEventRouter({
    required SoundEffectsService effects,
    required RainSoundSettingsLoader settingsLoader,
    required VoiceCallStateReader callStateReader,
    DateTime Function()? clock,
  }) : _effects = effects,
       _settingsLoader = settingsLoader,
       _callStateReader = callStateReader,
       _clock = clock ?? DateTime.now;

  final SoundEffectsService _effects;
  final RainSoundSettingsLoader _settingsLoader;
  final VoiceCallStateReader _callStateReader;
  final DateTime Function() _clock;
  DateTime? _lastDispatchedAt;
  bool _disposed = false;

  DateTime? get lastDispatchedAt => _lastDispatchedAt;

  Future<void> dispatch(RainSoundEvent event) async {
    if (_disposed) {
      return;
    }
    try {
      final settings = await Future<AppAudioSettings>.value(_settingsLoader());
      if (!_settingsAllowEvent(settings, event)) {
        return;
      }
      _lastDispatchedAt = event.occurredAt ?? _clock();
      await _effects.play(
        _effectFor(event),
        voiceCallActive: _isVoiceCallActive(event),
        allowDuringCall: event.isCallControlEvent,
      );
    } catch (error) {
      debugPrint('Rain sound event ignored: $error');
    }
  }

  Future<void> stopAllLoops() async {}

  Future<void> dispose() async {
    _disposed = true;
    await stopAllLoops();
  }

  bool _isVoiceCallActive(RainSoundEvent event) {
    if (event.isCallControlEvent) {
      return true;
    }
    try {
      return _callStateReader().isActive;
    } catch (_) {
      return false;
    }
  }
}

bool _settingsAllowEvent(AppAudioSettings settings, RainSoundEvent event) {
  if (!settings.soundEffectsEnabled) {
    return false;
  }
  if (!settings.callSoundsEnabled && _isCallSoundEvent(event)) {
    return false;
  }
  return true;
}

bool _isCallSoundEvent(RainSoundEvent event) {
  return event.isCallLifecycleEvent || event.isCallControlEvent;
}

RainSoundEffect _effectFor(RainSoundEvent event) {
  return switch (event.kind) {
    RainSoundEventKind.chatSend => RainSoundEffect.send,
    RainSoundEventKind.chatReceive => RainSoundEffect.receive,
    RainSoundEventKind.uiAction => RainSoundEffect.action,
    RainSoundEventKind.warning => RainSoundEffect.error,
    RainSoundEventKind.callIncomingStarted => RainSoundEffect.callIncoming,
    RainSoundEventKind.callOutgoingStarted => RainSoundEffect.callOutgoing,
    RainSoundEventKind.callConnected => RainSoundEffect.callConnected,
    RainSoundEventKind.callEnded => RainSoundEffect.callEnded,
    RainSoundEventKind.callFailed => RainSoundEffect.callFailed,
    RainSoundEventKind.callControlMute => RainSoundEffect.mute,
    RainSoundEventKind.callControlUnmute => RainSoundEffect.unmute,
    RainSoundEventKind.callControlDeafen => RainSoundEffect.deafen,
    RainSoundEventKind.callControlUndeafen => RainSoundEffect.undeafen,
    RainSoundEventKind.callControlCameraMute ||
    RainSoundEventKind.callControlCameraUnmute ||
    RainSoundEventKind.callRouteChanged => RainSoundEffect.action,
  };
}
