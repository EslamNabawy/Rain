import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/runtime/voice_call_state.dart';

import 'runtime_providers.dart';

enum CallSurfaceMode { expanded, minimized }

enum CallSurfaceDock { chatCenter, chatTop, bottomSafe }

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
    required this.dock,
    this.peerId,
    this.callId,
  });

  const CallSurfaceState.hidden()
    : isVisible = false,
      mode = CallSurfaceMode.expanded,
      dock = CallSurfaceDock.chatCenter,
      peerId = null,
      callId = null;

  const CallSurfaceState.visible({
    required this.peerId,
    required this.callId,
    this.mode = CallSurfaceMode.expanded,
    this.dock = CallSurfaceDock.chatCenter,
  }) : isVisible = true;

  final bool isVisible;
  final CallSurfaceMode mode;
  final CallSurfaceDock dock;
  final String? peerId;
  final String? callId;

  bool get isExpanded => isVisible && mode == CallSurfaceMode.expanded;

  bool get isMinimized => isVisible && mode == CallSurfaceMode.minimized;

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
    CallSurfaceDock? dock,
  }) {
    return CallSurfaceState(
      isVisible: isVisible ?? this.isVisible,
      mode: mode ?? this.mode,
      dock: dock ?? this.dock,
      peerId: peerId,
      callId: callId,
    );
  }

  CallSurfaceState forCall(VoiceCallState call) {
    return CallSurfaceState(
      isVisible: isVisible,
      mode: mode,
      dock: dock,
      peerId: call.peerId,
      callId: call.callId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CallSurfaceState &&
        other.isVisible == isVisible &&
        other.mode == mode &&
        other.dock == dock &&
        other.peerId == peerId &&
        other.callId == callId;
  }

  @override
  int get hashCode => Object.hash(isVisible, mode, dock, peerId, callId);

  @override
  String toString() {
    return 'CallSurfaceState('
        'isVisible: $isVisible, '
        'mode: $mode, '
        'dock: $dock, '
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

  void expand({CallSurfaceDock dock = CallSurfaceDock.chatCenter}) {
    final current = state;
    if (!current.isVisible) {
      return;
    }
    _setState(current.copyWith(mode: CallSurfaceMode.expanded, dock: dock));
  }

  void minimize({CallSurfaceDock dock = CallSurfaceDock.bottomSafe}) {
    final current = state;
    if (!current.isVisible) {
      return;
    }
    _setState(current.copyWith(mode: CallSurfaceMode.minimized, dock: dock));
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

    if (call.isRinging) {
      return CallSurfaceState.visible(peerId: call.peerId, callId: call.callId);
    }

    if (previous != null && previous.matchesCall(call)) {
      return previous.forCall(call);
    }

    return CallSurfaceState.visible(peerId: call.peerId, callId: call.callId);
  }

  bool _shouldHide(VoiceCallState call) {
    return call.phase == VoiceCallPhase.idle ||
        call.phase == VoiceCallPhase.failed;
  }
}
