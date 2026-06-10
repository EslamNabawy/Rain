import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';

import '../voice_call_state.dart';

typedef VoiceCallRuntimeEventRecorder =
    void Function({
      required String category,
      required String name,
      String severity,
      String? message,
      Map<String, Object?> context,
    });

/// Coordinates voice-call media reconnect state without owning runtime state.
///
/// The runtime owns the active call, session, and timer fields. This
/// coordinator receives those values and mutation callbacks at the call site.
final class VoiceCallReconnectCoordinator {
  const VoiceCallReconnectCoordinator();

  static const VoiceCallReconnectCoordinator instance =
      VoiceCallReconnectCoordinator();

  void failVoiceCallForPeer(
    String peerId,
    String message, {
    required String Function(String) normalizeUsername,
    required VoiceCallState currentState,
    required Future<void> Function(String peerId, String message) failPeer,
  }) {
    final normalizedPeerId = normalizeUsername(peerId);
    if (!_matchesLivePeer(currentState, normalizedPeerId)) {
      return;
    }
    unawaited(failPeer(normalizedPeerId, message));
  }

  void markVoiceCallReconnectingForPeer(
    String peerId, {
    required String Function(String) normalizeUsername,
    required VoiceCallState currentState,
    required VoiceCallSession? currentSession,
    required VoiceCallRuntimeEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(VoiceCallState) eventContext,
    required void Function(VoiceCallState) setVoiceCallState,
    required void Function(VoiceCallState) armReconnectGrace,
    required String reconnectingDetail,
    required int nowMs,
  }) {
    final normalizedPeerId = normalizeUsername(peerId);
    if (!_matchesLivePeer(currentState, normalizedPeerId)) {
      return;
    }
    recordRuntimeEvent(
      category: 'call',
      name: 'media_reconnecting_started',
      severity: 'warning',
      context: eventContext(currentState),
    );
    final session = currentSession;
    if (session != null && session.callId == currentState.callId) {
      session.markMediaReconnecting(detail: reconnectingDetail);
    }
    setVoiceCallState(
      currentState.copyWith(
        mediaReconnecting: true,
        reconnectingSince: currentState.reconnectingSince ?? nowMs,
        detail: reconnectingDetail,
        updatedAt: nowMs,
        clearError: true,
      ),
    );
    armReconnectGrace(currentState.copyWith(updatedAt: nowMs));
  }

  void clearVoiceCallReconnectingForPeer(
    String peerId, {
    required String Function(String) normalizeUsername,
    required VoiceCallState currentState,
    required VoiceCallSession? currentSession,
    required VoiceCallRuntimeEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(VoiceCallState) eventContext,
    required void Function(VoiceCallState) setVoiceCallState,
    required void Function() cancelReconnectGrace,
    required int nowMs,
  }) {
    if (currentState.peerId != normalizeUsername(peerId) ||
        !currentState.mediaReconnecting) {
      return;
    }
    recordRuntimeEvent(
      category: 'call',
      name: 'media_reconnecting_cleared',
      context: eventContext(currentState),
    );
    final session = currentSession;
    if (session != null && session.callId == currentState.callId) {
      session.clearMediaReconnecting();
    }
    cancelReconnectGrace();
    setVoiceCallState(
      currentState.copyWith(
        mediaReconnecting: false,
        detail: 'Voice call connected.',
        updatedAt: nowMs,
        clearReconnectingSince: true,
        clearError: true,
      ),
    );
  }

  void armVoiceCallReconnectGrace(
    VoiceCallState call, {
    required Duration gracePeriod,
    required Timer? reconnectGraceTimer,
    required void Function(Timer?) setReconnectGraceTimer,
    required VoiceCallState Function() currentState,
    required Future<void> Function(String peerId, String message) failPeer,
    required String networkLostMessage,
  }) {
    final callId = call.callId;
    final peerId = call.peerId;
    if (callId == null || peerId == null || gracePeriod <= Duration.zero) {
      return;
    }
    reconnectGraceTimer?.cancel();
    final sessionEpoch = call.sessionEpoch;
    setReconnectGraceTimer(
      Timer(gracePeriod, () {
        final current = currentState();
        if (current.callId != callId ||
            current.peerId != peerId ||
            current.sessionEpoch != sessionEpoch ||
            !current.mediaReconnecting ||
            current.phase != VoiceCallPhase.active) {
          return;
        }
        unawaited(failPeer(peerId, networkLostMessage));
      }),
    );
  }

  void cancelVoiceCallReconnectGrace({
    required Timer? reconnectGraceTimer,
    required void Function(Timer?) setReconnectGraceTimer,
  }) {
    reconnectGraceTimer?.cancel();
    setReconnectGraceTimer(null);
  }

  bool _matchesLivePeer(VoiceCallState state, String normalizedPeerId) {
    return state.peerId == normalizedPeerId &&
        state.phase != VoiceCallPhase.idle &&
        state.phase != VoiceCallPhase.failed &&
        state.phase != VoiceCallPhase.ending;
  }
}
