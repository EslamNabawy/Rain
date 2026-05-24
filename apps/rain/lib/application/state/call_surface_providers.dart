import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/runtime/voice_call_state.dart';

import 'runtime_providers.dart';

enum CallSurfaceMode { managerOnly, expanded, fullscreen, pip }

final voiceCallStateForCallSurfaceProvider = Provider<VoiceCallState>(
  (Ref ref) => ref.watch(voiceCallProvider),
);

final callSurfaceProvider =
    NotifierProvider<CallSurfaceController, CallSurfaceState>(
      CallSurfaceController.new,
    );

class CallSurfaceState {
  const CallSurfaceState({
    required this.isVisible,
    required this.mode,
    required this.restoreMode,
    required this.mediaMode,
    this.peerId,
    this.callId,
  });

  const CallSurfaceState.hidden()
    : isVisible = false,
      mode = CallSurfaceMode.expanded,
      restoreMode = CallSurfaceMode.expanded,
      mediaMode = CallMediaMode.audio,
      peerId = null,
      callId = null;

  const CallSurfaceState.visible({
    required this.peerId,
    required this.callId,
    this.mode = CallSurfaceMode.expanded,
    this.restoreMode = CallSurfaceMode.expanded,
    this.mediaMode = CallMediaMode.audio,
  }) : isVisible = true;

  final bool isVisible;
  final CallSurfaceMode mode;
  final CallSurfaceMode restoreMode;
  final CallMediaMode mediaMode;
  final String? peerId;
  final String? callId;

  bool get isExpanded => isVisible && mode == CallSurfaceMode.expanded;

  bool get isManagerOnly => isVisible && mode == CallSurfaceMode.managerOnly;

  bool get isFullscreen => isVisible && mode == CallSurfaceMode.fullscreen;

  bool get isPip => isVisible && mode == CallSurfaceMode.pip;

  bool get hasMediaPanel => isVisible && mode != CallSurfaceMode.managerOnly;

  bool get showsMediaSurface =>
      isVisible && mode != CallSurfaceMode.managerOnly;

  bool get showsManagerBar =>
      isVisible &&
      (mode == CallSurfaceMode.managerOnly || mode == CallSurfaceMode.pip);

  bool matchesCall(VoiceCallState call) {
    if (!isVisible || call.peerId == null) {
      return false;
    }
    final nextCallId = call.callId?.trim();
    if (nextCallId != null && nextCallId.isNotEmpty) {
      return callId == nextCallId;
    }
    return peerId == call.peerId;
  }

  CallSurfaceState copyWith({
    bool? isVisible,
    CallSurfaceMode? mode,
    CallSurfaceMode? restoreMode,
    CallMediaMode? mediaMode,
  }) {
    return CallSurfaceState(
      isVisible: isVisible ?? this.isVisible,
      mode: mode ?? this.mode,
      restoreMode: restoreMode ?? this.restoreMode,
      mediaMode: mediaMode ?? this.mediaMode,
      peerId: peerId,
      callId: callId,
    );
  }

  CallSurfaceState forCall(VoiceCallState call) {
    return CallSurfaceState(
      isVisible: isVisible,
      mode: _modeForMediaMode(mode, call.mediaMode),
      restoreMode: _restoreModeForMediaMode(restoreMode, call.mediaMode),
      mediaMode: call.mediaMode,
      peerId: call.peerId,
      callId: call.callId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CallSurfaceState &&
        other.isVisible == isVisible &&
        other.mode == mode &&
        other.restoreMode == restoreMode &&
        other.mediaMode == mediaMode &&
        other.peerId == peerId &&
        other.callId == callId;
  }

  @override
  int get hashCode =>
      Object.hash(isVisible, mode, restoreMode, mediaMode, peerId, callId);

  @override
  String toString() {
    return 'CallSurfaceState('
        'isVisible: $isVisible, '
        'mode: $mode, '
        'restoreMode: $restoreMode, '
        'mediaMode: $mediaMode, '
        'peerId: $peerId, '
        'callId: $callId'
        ')';
  }
}

class CallSurfaceController extends Notifier<CallSurfaceState> {
  CallSurfaceState? _lastState;

  @override
  CallSurfaceState build() {
    final call = ref.watch(voiceCallStateForCallSurfaceProvider);
    final next = _deriveFromCall(call, previous: _lastState);
    _lastState = next;
    return next;
  }

  void expand() {
    final current = state;
    if (!current.isVisible) {
      return;
    }
    _setState(
      current.copyWith(
        mode: CallSurfaceMode.expanded,
        restoreMode: CallSurfaceMode.expanded,
      ),
    );
  }

  void minimize() {
    final current = state;
    if (!current.isVisible) {
      return;
    }
    _setState(_nextMinimizedState(current));
  }

  void showManagerOnly() {
    final current = state;
    if (!current.isVisible) {
      return;
    }
    _setState(
      current.copyWith(
        mode: CallSurfaceMode.managerOnly,
        restoreMode: _usefulRestoreModeFor(current),
      ),
    );
  }

  void restore() {
    final current = state;
    if (!current.isVisible) {
      return;
    }
    if (current.mode == CallSurfaceMode.fullscreen) {
      exitFullscreen();
      return;
    }
    _setState(current.copyWith(mode: _safeRestoreMode(current)));
  }

  void enterFullscreen() {
    final current = state;
    if (!current.isVisible || current.mediaMode != CallMediaMode.video) {
      return;
    }
    _setState(
      current.copyWith(
        mode: CallSurfaceMode.fullscreen,
        restoreMode: _usefulRestoreModeFor(current),
      ),
    );
  }

  void exitFullscreen() {
    final current = state;
    if (!current.isVisible || current.mode != CallSurfaceMode.fullscreen) {
      return;
    }
    _setState(current.copyWith(mode: _safeRestoreMode(current)));
  }

  bool handleBackIntent() {
    final current = state;
    if (!current.isVisible || current.mode == CallSurfaceMode.managerOnly) {
      return false;
    }
    if (current.mode == CallSurfaceMode.fullscreen) {
      exitFullscreen();
      return true;
    }
    minimize();
    return true;
  }

  void _setState(CallSurfaceState next) {
    _lastState = next;
    state = next;
  }

  CallSurfaceState _deriveFromCall(
    VoiceCallState call, {
    required CallSurfaceState? previous,
  }) {
    if (_shouldHide(call)) {
      return const CallSurfaceState.hidden();
    }

    if (call.isRinging || call.phase == VoiceCallPhase.failed) {
      return CallSurfaceState.visible(
        peerId: call.peerId,
        callId: call.callId,
        mediaMode: call.mediaMode,
      );
    }

    if (previous != null && previous.matchesCall(call)) {
      return previous.forCall(call);
    }

    return CallSurfaceState.visible(
      peerId: call.peerId,
      callId: call.callId,
      mediaMode: call.mediaMode,
    );
  }

  bool _shouldHide(VoiceCallState call) {
    return call.phase == VoiceCallPhase.idle;
  }

  CallSurfaceState _nextMinimizedState(CallSurfaceState current) {
    return switch (current.mode) {
      CallSurfaceMode.expanded when current.mediaMode == CallMediaMode.video =>
        current.copyWith(
          mode: CallSurfaceMode.pip,
          restoreMode: CallSurfaceMode.pip,
        ),
      CallSurfaceMode.pip => current.copyWith(
        mode: CallSurfaceMode.managerOnly,
        restoreMode: CallSurfaceMode.pip,
      ),
      CallSurfaceMode.fullscreen => current.copyWith(
        mode: current.mediaMode == CallMediaMode.video
            ? CallSurfaceMode.pip
            : CallSurfaceMode.managerOnly,
        restoreMode: current.mediaMode == CallMediaMode.video
            ? CallSurfaceMode.pip
            : CallSurfaceMode.expanded,
      ),
      CallSurfaceMode.managerOnly => current,
      CallSurfaceMode.expanded => current.copyWith(
        mode: CallSurfaceMode.managerOnly,
        restoreMode: CallSurfaceMode.expanded,
      ),
    };
  }

  CallSurfaceMode _usefulRestoreModeFor(CallSurfaceState state) {
    return switch (state.mode) {
      CallSurfaceMode.pip => CallSurfaceMode.pip,
      CallSurfaceMode.expanded ||
      CallSurfaceMode.fullscreen => CallSurfaceMode.expanded,
      CallSurfaceMode.managerOnly => _safeRestoreMode(state),
    };
  }

  CallSurfaceMode _safeRestoreMode(CallSurfaceState state) {
    return _restoreModeForMediaMode(state.restoreMode, state.mediaMode);
  }
}

CallSurfaceMode _modeForMediaMode(
  CallSurfaceMode mode,
  CallMediaMode mediaMode,
) {
  if (mediaMode == CallMediaMode.video) {
    return mode;
  }
  return switch (mode) {
    CallSurfaceMode.fullscreen ||
    CallSurfaceMode.pip => CallSurfaceMode.expanded,
    CallSurfaceMode.managerOnly || CallSurfaceMode.expanded => mode,
  };
}

CallSurfaceMode _restoreModeForMediaMode(
  CallSurfaceMode mode,
  CallMediaMode mediaMode,
) {
  if (mediaMode == CallMediaMode.video && mode == CallSurfaceMode.pip) {
    return CallSurfaceMode.pip;
  }
  return CallSurfaceMode.expanded;
}
