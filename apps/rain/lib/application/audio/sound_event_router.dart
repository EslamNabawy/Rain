import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';

import 'rain_sound_event.dart';

typedef VoiceCallStateReader = VoiceCallState Function();

const Duration _sendBurstWindow = Duration(milliseconds: 300);
const Duration _sameConversationReceiveWindow = Duration(milliseconds: 900);
const Duration _globalReceiveWindow = Duration(milliseconds: 350);
const Duration _receiveRollingWindow = Duration(seconds: 3);
const int _maxReceivesPerRollingWindow = 4;
const Duration _uiActionWindow = Duration(milliseconds: 140);
const Duration _warningKeyWindow = Duration(milliseconds: 1500);
const Duration _warningRollingWindow = Duration(seconds: 5);
const int _maxWarningsPerRollingWindow = 3;

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
  final Map<RainSoundEventKind, DateTime> _lastPlayedByKind =
      <RainSoundEventKind, DateTime>{};
  final Map<String, DateTime> _lastReceiveByConversation = <String, DateTime>{};
  final List<DateTime> _recentReceivePlays = <DateTime>[];
  final Map<String, DateTime> _lastWarningByKey = <String, DateTime>{};
  final List<DateTime> _recentWarningPlays = <DateTime>[];
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
      final now = event.occurredAt ?? _clock();
      if (!_allowEvent(event, now)) {
        return;
      }
      _recordAllowedEvent(event, now);
      _lastDispatchedAt = now;
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

  bool _allowEvent(RainSoundEvent event, DateTime now) {
    return switch (event.kind) {
      RainSoundEventKind.chatSend => _allowsKindCooldown(
        event.kind,
        now,
        _sendBurstWindow,
      ),
      RainSoundEventKind.chatReceive => _allowsReceive(event, now),
      RainSoundEventKind.uiAction => _allowsKindCooldown(
        event.kind,
        now,
        _uiActionWindow,
      ),
      RainSoundEventKind.warning => _allowsWarning(event, now),
      RainSoundEventKind.callIncomingStarted ||
      RainSoundEventKind.callOutgoingStarted ||
      RainSoundEventKind.callConnected ||
      RainSoundEventKind.callEnded ||
      RainSoundEventKind.callFailed ||
      RainSoundEventKind.callControlMute ||
      RainSoundEventKind.callControlUnmute ||
      RainSoundEventKind.callControlDeafen ||
      RainSoundEventKind.callControlUndeafen ||
      RainSoundEventKind.callControlCameraMute ||
      RainSoundEventKind.callControlCameraUnmute ||
      RainSoundEventKind.callRouteChanged => true,
    };
  }

  bool _allowsKindCooldown(
    RainSoundEventKind kind,
    DateTime now,
    Duration window,
  ) {
    final lastPlayedAt = _lastPlayedByKind[kind];
    return lastPlayedAt == null || now.difference(lastPlayedAt) >= window;
  }

  bool _allowsReceive(RainSoundEvent event, DateTime now) {
    final conversationId = event.conversationId;
    if (conversationId == null) {
      return false;
    }
    _pruneOlderThan(_recentReceivePlays, now, _receiveRollingWindow);
    if (_recentReceivePlays.length >= _maxReceivesPerRollingWindow) {
      return false;
    }
    final lastForConversation = _lastReceiveByConversation[conversationId];
    if (lastForConversation != null &&
        now.difference(lastForConversation) < _sameConversationReceiveWindow) {
      return false;
    }
    return _allowsKindCooldown(
      RainSoundEventKind.chatReceive,
      now,
      _globalReceiveWindow,
    );
  }

  bool _allowsWarning(RainSoundEvent event, DateTime now) {
    final warningKey = event.errorKey ?? 'global';
    final lastForKey = _lastWarningByKey[warningKey];
    if (lastForKey != null && now.difference(lastForKey) < _warningKeyWindow) {
      return false;
    }
    _pruneOlderThan(_recentWarningPlays, now, _warningRollingWindow);
    return _recentWarningPlays.length < _maxWarningsPerRollingWindow;
  }

  void _recordAllowedEvent(RainSoundEvent event, DateTime now) {
    _lastPlayedByKind[event.kind] = now;
    switch (event.kind) {
      case RainSoundEventKind.chatReceive:
        final conversationId = event.conversationId;
        if (conversationId != null) {
          _lastReceiveByConversation[conversationId] = now;
          _recentReceivePlays.add(now);
        }
        break;
      case RainSoundEventKind.warning:
        _lastWarningByKey[event.errorKey ?? 'global'] = now;
        _recentWarningPlays.add(now);
        break;
      case RainSoundEventKind.chatSend:
      case RainSoundEventKind.uiAction:
      case RainSoundEventKind.callIncomingStarted:
      case RainSoundEventKind.callOutgoingStarted:
      case RainSoundEventKind.callConnected:
      case RainSoundEventKind.callEnded:
      case RainSoundEventKind.callFailed:
      case RainSoundEventKind.callControlMute:
      case RainSoundEventKind.callControlUnmute:
      case RainSoundEventKind.callControlDeafen:
      case RainSoundEventKind.callControlUndeafen:
      case RainSoundEventKind.callControlCameraMute:
      case RainSoundEventKind.callControlCameraUnmute:
      case RainSoundEventKind.callRouteChanged:
        break;
    }
  }
}

void _pruneOlderThan(List<DateTime> items, DateTime now, Duration window) {
  items.removeWhere((DateTime item) => now.difference(item) >= window);
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
