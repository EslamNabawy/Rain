import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
const Duration _callLifecycleDedupeWindow = Duration(minutes: 10);
const Duration _callFailureWindow = Duration(milliseconds: 1200);
const double _sendBurstTrailingVolumeScale = 0.62;
const String _incomingCallLoopId = 'rain-call-incoming';
const String _outgoingCallLoopId = 'rain-call-outgoing';
const double _incomingCallLoopVolume = 0.42;
const double _outgoingCallLoopVolume = 0.34;

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
  final Map<String, DateTime> _playedCallLifecycleByKey = <String, DateTime>{};
  Timer? _pendingSendBurstTick;
  DateTime? _lastSendBurstSuppressedAt;
  DateTime? _lastDispatchedAt;
  String? _incomingLoopCallId;
  String? _outgoingLoopCallId;
  RainSoundEventKind? _lastEventKind;
  String? _lastSuppressedReason;
  bool _disposed = false;

  DateTime? get lastDispatchedAt => _lastDispatchedAt;

  SoundEventRouterDiagnostics get diagnostics {
    return SoundEventRouterDiagnostics(
      lastEventKind: _lastEventKind,
      lastSuppressedReason: _lastSuppressedReason,
      activeLoopIds: _activeLoopIds(),
      soundServiceDisabledReason: _effects.diagnostics.disabledReason,
      soundServiceLastFailureReason: _effects.diagnostics.lastFailureReason,
    );
  }

  Future<void> dispatch(RainSoundEvent event) async {
    if (_disposed) {
      return;
    }
    _lastEventKind = event.kind;
    try {
      final settings = await Future<AppAudioSettings>.value(_settingsLoader());
      if (!settings.soundEffectsEnabled || !settings.callSoundsEnabled) {
        await stopAllLoops();
      }
      final settingsSuppression = _settingsSuppressionReason(settings, event);
      if (settingsSuppression != null) {
        _lastSuppressedReason = settingsSuppression;
        return;
      }
      final callStateSuppression = _callStateSuppressionReason(settings, event);
      if (callStateSuppression != null) {
        _lastSuppressedReason = callStateSuppression;
        return;
      }
      final now = event.occurredAt ?? _clock();
      if (_isTerminalCallLifecycle(event.kind)) {
        await _stopLoopsForTerminalEvent(event);
      }
      final policySuppression = _policySuppressionReason(event, now);
      if (policySuppression != null) {
        if (event.kind == RainSoundEventKind.chatSend &&
            policySuppression == 'sendBurstWindow') {
          _scheduleSendBurstTick(event, now);
          _lastSuppressedReason = 'sendBurstQueued';
        } else {
          _lastSuppressedReason = policySuppression;
        }
        return;
      }
      if (event.kind == RainSoundEventKind.chatSend) {
        _cancelPendingSendBurstTick();
      }
      _lastSuppressedReason = null;
      _recordAllowedEvent(event, now);
      _lastDispatchedAt = now;
      if (event.kind == RainSoundEventKind.callIncomingStarted) {
        await _startIncomingLoop(event);
        return;
      }
      if (event.kind == RainSoundEventKind.callOutgoingStarted) {
        await _startOutgoingLoop(event);
        return;
      }
      await _effects.play(
        _effectFor(event),
        voiceCallActive: _isVoiceCallActive(event),
        allowDuringCall: event.isCallControlEvent,
      );
    } catch (error) {
      await _handleDispatchFailure(error);
    }
  }

  Future<void> stopAllLoops() async {
    _incomingLoopCallId = null;
    _outgoingLoopCallId = null;
    await _effects.stopAllLoops();
  }

  Future<void> dispose() async {
    _disposed = true;
    _cancelPendingSendBurstTick();
    await stopAllLoops();
  }

  Set<String> _activeLoopIds() {
    return <String>{
      if (_incomingLoopCallId != null) _incomingCallLoopId,
      if (_outgoingLoopCallId != null) _outgoingCallLoopId,
    };
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

  String? _callStateSuppressionReason(
    AppAudioSettings settings,
    RainSoundEvent event,
  ) {
    if (_isCallSoundEvent(event) || event.kind == RainSoundEventKind.warning) {
      return null;
    }
    final call = _readCallStateOrNull();
    if (call == null) {
      return null;
    }
    if (call.isRinging &&
        (event.kind == RainSoundEventKind.chatSend ||
            event.kind == RainSoundEventKind.chatReceive)) {
      return 'ringingSuppressesChat';
    }
    if (settings.reduceSoundsDuringCall &&
        call.isActive &&
        (event.kind == RainSoundEventKind.chatSend ||
            event.kind == RainSoundEventKind.chatReceive ||
            event.kind == RainSoundEventKind.uiAction)) {
      return 'activeCallReduction';
    }
    return null;
  }

  VoiceCallState? _readCallStateOrNull() {
    try {
      return _callStateReader();
    } catch (_) {
      return null;
    }
  }

  String? _policySuppressionReason(RainSoundEvent event, DateTime now) {
    final lifecycleSuppression = _callLifecycleSuppressionReason(event, now);
    if (lifecycleSuppression != null) {
      return lifecycleSuppression;
    }
    return switch (event.kind) {
      RainSoundEventKind.chatSend => _kindCooldownSuppressionReason(
        event.kind,
        now,
        _sendBurstWindow,
        'sendBurstWindow',
      ),
      RainSoundEventKind.chatReceive => _receiveSuppressionReason(event, now),
      RainSoundEventKind.uiAction => _kindCooldownSuppressionReason(
        event.kind,
        now,
        _uiActionWindow,
        'uiActionWindow',
      ),
      RainSoundEventKind.warning => _warningSuppressionReason(event, now),
      RainSoundEventKind.callIncomingStarted ||
      RainSoundEventKind.callOutgoingStarted ||
      RainSoundEventKind.callConnected ||
      RainSoundEventKind.callEnded ||
      RainSoundEventKind.callControlMute ||
      RainSoundEventKind.callControlUnmute ||
      RainSoundEventKind.callControlDeafen ||
      RainSoundEventKind.callControlUndeafen ||
      RainSoundEventKind.callControlCameraMute ||
      RainSoundEventKind.callControlCameraUnmute ||
      RainSoundEventKind.callRouteChanged => null,
      RainSoundEventKind.callFailed => _kindCooldownSuppressionReason(
        event.kind,
        now,
        _callFailureWindow,
        'callFailureWindow',
      ),
    };
  }

  String? _kindCooldownSuppressionReason(
    RainSoundEventKind kind,
    DateTime now,
    Duration window,
    String reason,
  ) {
    final lastPlayedAt = _lastPlayedByKind[kind];
    if (lastPlayedAt == null || now.difference(lastPlayedAt) >= window) {
      return null;
    }
    return reason;
  }

  String? _receiveSuppressionReason(RainSoundEvent event, DateTime now) {
    final conversationId = event.conversationId;
    if (conversationId == null) {
      return 'missingConversationId';
    }
    _pruneOlderThan(_recentReceivePlays, now, _receiveRollingWindow);
    if (_recentReceivePlays.length >= _maxReceivesPerRollingWindow) {
      return 'receiveRollingLimit';
    }
    final lastForConversation = _lastReceiveByConversation[conversationId];
    if (lastForConversation != null &&
        now.difference(lastForConversation) < _sameConversationReceiveWindow) {
      return 'receiveConversationWindow';
    }
    return _kindCooldownSuppressionReason(
      RainSoundEventKind.chatReceive,
      now,
      _globalReceiveWindow,
      'receiveGlobalWindow',
    );
  }

  String? _warningSuppressionReason(RainSoundEvent event, DateTime now) {
    final warningKey = event.errorKey ?? 'global';
    final lastForKey = _lastWarningByKey[warningKey];
    if (lastForKey != null && now.difference(lastForKey) < _warningKeyWindow) {
      return 'warningKeyWindow';
    }
    _pruneOlderThan(_recentWarningPlays, now, _warningRollingWindow);
    if (_recentWarningPlays.length >= _maxWarningsPerRollingWindow) {
      return 'warningRollingLimit';
    }
    return null;
  }

  String? _callLifecycleSuppressionReason(RainSoundEvent event, DateTime now) {
    if (!event.isCallLifecycleEvent) {
      return null;
    }
    if (!_shouldDedupeCallLifecycle(event.kind)) {
      return null;
    }
    if (_isTerminalCallLifecycle(event.kind) &&
        _hasActiveLoopForDifferentCall(event.callId)) {
      return 'staleCallLifecycle';
    }
    _pruneMapOlderThan(
      _playedCallLifecycleByKey,
      now,
      _callLifecycleDedupeWindow,
    );
    if (_playedCallLifecycleByKey.containsKey(_callLifecycleKey(event))) {
      return 'duplicateCallLifecycle';
    }
    return null;
  }

  void _recordAllowedEvent(RainSoundEvent event, DateTime now) {
    _lastPlayedByKind[event.kind] = now;
    if (_shouldDedupeCallLifecycle(event.kind)) {
      _playedCallLifecycleByKey[_callLifecycleKey(event)] = now;
    }
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

  void _scheduleSendBurstTick(RainSoundEvent event, DateTime now) {
    _lastSendBurstSuppressedAt = now;
    if (_pendingSendBurstTick != null) {
      return;
    }
    final lastPlayedAt = _lastPlayedByKind[RainSoundEventKind.chatSend] ?? now;
    final elapsed = now.difference(lastPlayedAt);
    final delay = elapsed >= _sendBurstWindow
        ? Duration.zero
        : _sendBurstWindow - elapsed;
    _pendingSendBurstTick = Timer(delay, () {
      _pendingSendBurstTick = null;
      unawaited(_playPendingSendBurstTick(event));
    });
  }

  void _cancelPendingSendBurstTick() {
    _pendingSendBurstTick?.cancel();
    _pendingSendBurstTick = null;
    _lastSendBurstSuppressedAt = null;
  }

  Future<void> _playPendingSendBurstTick(RainSoundEvent event) async {
    final burstSuppressedAt = _lastSendBurstSuppressedAt;
    if (_disposed || burstSuppressedAt == null) {
      return;
    }
    try {
      final settings = await Future<AppAudioSettings>.value(_settingsLoader());
      if (_disposed || _lastSendBurstSuppressedAt != burstSuppressedAt) {
        return;
      }
      if (!settings.soundEffectsEnabled || !settings.callSoundsEnabled) {
        await stopAllLoops();
      }
      final settingsSuppression = _settingsSuppressionReason(settings, event);
      if (settingsSuppression != null) {
        _lastSuppressedReason = settingsSuppression;
        return;
      }
      final callStateSuppression = _callStateSuppressionReason(settings, event);
      if (callStateSuppression != null) {
        _lastSuppressedReason = callStateSuppression;
        return;
      }
      final now = _clock();
      _lastSuppressedReason = null;
      _lastDispatchedAt = now;
      _lastPlayedByKind[RainSoundEventKind.chatSend] = now;
      await _effects.play(
        RainSoundEffect.send,
        voiceCallActive: _isVoiceCallActive(event),
        volumeScale: _sendBurstTrailingVolumeScale,
      );
    } catch (error) {
      await _handleDispatchFailure(error);
    } finally {
      if (_lastSendBurstSuppressedAt == burstSuppressedAt) {
        _lastSendBurstSuppressedAt = null;
      }
    }
  }

  Future<void> _handleDispatchFailure(Object error) async {
    if (error is MissingPluginException) {
      try {
        await stopAllLoops();
      } catch (cleanupError) {
        debugPrint('Rain sound loop cleanup ignored: $cleanupError');
      }
    }
    _lastSuppressedReason = _sanitizedSoundFailureReason(error);
    debugPrint('Rain sound event ignored: $_lastSuppressedReason');
  }

  Future<void> _startIncomingLoop(RainSoundEvent event) async {
    final callId = event.callId;
    if (callId == null || _incomingLoopCallId == callId) {
      return;
    }
    if (_outgoingLoopCallId != null) {
      await _effects.stopLoop(_outgoingCallLoopId);
      _outgoingLoopCallId = null;
    }
    if (_incomingLoopCallId != null) {
      await _effects.stopLoop(_incomingCallLoopId);
      _incomingLoopCallId = null;
    }
    await _effects.startLoop(
      RainSoundEffect.callIncoming,
      loopId: _incomingCallLoopId,
      volume: _incomingCallLoopVolume,
    );
    _incomingLoopCallId = callId;
  }

  Future<void> _startOutgoingLoop(RainSoundEvent event) async {
    final callId = event.callId;
    if (callId == null || _outgoingLoopCallId == callId) {
      return;
    }
    if (_incomingLoopCallId != null) {
      await _effects.stopLoop(_incomingCallLoopId);
      _incomingLoopCallId = null;
    }
    if (_outgoingLoopCallId != null) {
      await _effects.stopLoop(_outgoingCallLoopId);
      _outgoingLoopCallId = null;
    }
    await _effects.startLoop(
      RainSoundEffect.callOutgoing,
      loopId: _outgoingCallLoopId,
      volume: _outgoingCallLoopVolume,
    );
    _outgoingLoopCallId = callId;
  }

  Future<void> _stopLoopsForTerminalEvent(RainSoundEvent event) async {
    final callId = event.callId;
    if (callId == null) {
      return;
    }
    if (_incomingLoopCallId != callId && _outgoingLoopCallId != callId) {
      return;
    }
    await stopAllLoops();
  }

  bool _hasActiveLoopForDifferentCall(String? callId) {
    final activeCallIds = <String>{?_incomingLoopCallId, ?_outgoingLoopCallId};
    if (activeCallIds.isEmpty) {
      return false;
    }
    return callId == null || !activeCallIds.contains(callId);
  }
}

void _pruneOlderThan(List<DateTime> items, DateTime now, Duration window) {
  items.removeWhere((DateTime item) => now.difference(item) >= window);
}

void _pruneMapOlderThan(
  Map<String, DateTime> items,
  DateTime now,
  Duration window,
) {
  items.removeWhere((_, DateTime item) => now.difference(item) >= window);
}

String _callLifecycleKey(RainSoundEvent event) {
  return '${event.kind.name}:${event.callId ?? 'none'}:'
      '${event.sessionEpoch ?? 'none'}';
}

String? _settingsSuppressionReason(
  AppAudioSettings settings,
  RainSoundEvent event,
) {
  if (!settings.soundEffectsEnabled) {
    return 'soundEffectsDisabled';
  }
  if (!settings.callSoundsEnabled && _isCallSoundEvent(event)) {
    return 'callSoundsDisabled';
  }
  return null;
}

bool _isCallSoundEvent(RainSoundEvent event) {
  return event.isCallLifecycleEvent || event.isCallControlEvent;
}

bool _isTerminalCallLifecycle(RainSoundEventKind kind) {
  return switch (kind) {
    RainSoundEventKind.callConnected ||
    RainSoundEventKind.callEnded ||
    RainSoundEventKind.callFailed => true,
    RainSoundEventKind.chatSend ||
    RainSoundEventKind.chatReceive ||
    RainSoundEventKind.uiAction ||
    RainSoundEventKind.warning ||
    RainSoundEventKind.callIncomingStarted ||
    RainSoundEventKind.callOutgoingStarted ||
    RainSoundEventKind.callControlMute ||
    RainSoundEventKind.callControlUnmute ||
    RainSoundEventKind.callControlDeafen ||
    RainSoundEventKind.callControlUndeafen ||
    RainSoundEventKind.callControlCameraMute ||
    RainSoundEventKind.callControlCameraUnmute ||
    RainSoundEventKind.callRouteChanged => false,
  };
}

bool _shouldDedupeCallLifecycle(RainSoundEventKind kind) {
  return switch (kind) {
    RainSoundEventKind.callConnected ||
    RainSoundEventKind.callEnded ||
    RainSoundEventKind.callFailed => true,
    RainSoundEventKind.chatSend ||
    RainSoundEventKind.chatReceive ||
    RainSoundEventKind.uiAction ||
    RainSoundEventKind.warning ||
    RainSoundEventKind.callIncomingStarted ||
    RainSoundEventKind.callOutgoingStarted ||
    RainSoundEventKind.callControlMute ||
    RainSoundEventKind.callControlUnmute ||
    RainSoundEventKind.callControlDeafen ||
    RainSoundEventKind.callControlUndeafen ||
    RainSoundEventKind.callControlCameraMute ||
    RainSoundEventKind.callControlCameraUnmute ||
    RainSoundEventKind.callRouteChanged => false,
  };
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

String _sanitizedSoundFailureReason(Object error) {
  if (error is MissingPluginException) {
    return 'pluginUnavailable';
  }
  return 'soundPlaybackFailed';
}

final class SoundEventRouterDiagnostics {
  const SoundEventRouterDiagnostics({
    required this.lastEventKind,
    required this.lastSuppressedReason,
    required this.activeLoopIds,
    required this.soundServiceDisabledReason,
    required this.soundServiceLastFailureReason,
  });

  final RainSoundEventKind? lastEventKind;
  final String? lastSuppressedReason;
  final Set<String> activeLoopIds;
  final String? soundServiceDisabledReason;
  final String? soundServiceLastFailureReason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'lastEventKind': lastEventKind?.name,
      'lastSuppressedReason': lastSuppressedReason,
      'activeLoopIds': activeLoopIds.toList(growable: false)..sort(),
      'soundServiceDisabledReason': soundServiceDisabledReason,
      'soundServiceLastFailureReason': soundServiceLastFailureReason,
    };
  }
}
