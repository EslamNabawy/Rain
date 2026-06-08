import 'package:protocol_brain/protocol_brain.dart';

import '../runtime_interaction_guard.dart';
import '../voice_call_state.dart';

typedef VoiceCallPreflightEventRecorder =
    void Function({
      required String category,
      required String name,
      String severity,
      String? message,
      Map<String, Object?> context,
    });

typedef VoiceCallPreflightErrorRecorder =
    void Function(
      Object error,
      StackTrace? stackTrace, {
      required String source,
      required bool fatal,
    });

typedef VoiceCallBoundedCleanup =
    Future<bool> Function(
      String step,
      Future<void> Function() cleanup, {
      Map<String, Object?> context,
    });

final class VoiceCallPeerPresence {
  const VoiceCallPeerPresence({
    required this.online,
    required this.diagnostics,
  });

  final bool online;
  final Map<String, Object?> diagnostics;
}

final class VoiceCallStartPresenceSnapshot {
  const VoiceCallStartPresenceSnapshot({
    required this.peerOnline,
    required this.diagnostics,
  });

  final bool? peerOnline;
  final Map<String, Object?> diagnostics;
}

/// Coordinates voice-call start/retry preflight checks without owning runtime
/// state or private runtime types.
final class VoiceCallPreflightCoordinator {
  const VoiceCallPreflightCoordinator();

  static const VoiceCallPreflightCoordinator instance =
      VoiceCallPreflightCoordinator();

  void assertVoiceCallCanStart({required bool peerConnectionAvailable}) {
    if (!peerConnectionAvailable) {
      throw StateError('Peer connection is unavailable right now.');
    }
  }

  Future<void> assertVoiceCallPeerIsFriend(
    String peerId, {
    required Future<bool> Function(String peerId) isAcceptedFriend,
    required Future<void> Function(String peerId) syncRelationships,
  }) async {
    if (await isAcceptedFriend(peerId)) {
      return;
    }
    await syncRelationships(peerId);
    if (!await isAcceptedFriend(peerId)) {
      throw StateError('Only accepted friends can call.');
    }
  }

  Future<VoiceCallStartPresenceSnapshot> fetchVoiceCallPeerPresence(
    String peerId, {
    required CallMediaMode mediaMode,
    required String Function(String) normalizeUsername,
    required Future<VoiceCallPeerPresence?> Function(
      String peerId, {
      required String action,
    })
    fetchPresence,
    required VoiceCallPreflightEventRecorder recordRuntimeEvent,
    required VoiceCallPreflightErrorRecorder? errorRecorder,
  }) async {
    final normalizedPeerId = normalizeUsername(peerId);
    VoiceCallPeerPresence? presence;
    try {
      presence = await fetchPresence(normalizedPeerId, action: 'callStart');
    } catch (error, stackTrace) {
      final decision = RuntimeInteractionGuard.presenceUnknown(
        peerId: normalizedPeerId,
      );
      recordRuntimeEvent(
        category: 'call',
        name: 'call_start_presence_unknown',
        severity: 'warning',
        message: decision.userMessage,
        context: <String, Object?>{
          'peerId': normalizedPeerId,
          'mediaMode': mediaMode.name,
          'reasonCode': decision.reasonCode.name,
          'presenceSource': 'backend',
          'error': error.toString(),
        },
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'voice-call-presence',
        fatal: false,
      );
      return VoiceCallStartPresenceSnapshot(
        peerOnline: null,
        diagnostics: <String, Object?>{
          'presenceSource': 'backend',
          'presenceError': error.toString(),
        },
      );
    }

    if (presence == null) {
      final decision = RuntimeInteractionGuard.presenceUnknown(
        peerId: normalizedPeerId,
      );
      recordRuntimeEvent(
        category: 'call',
        name: 'call_start_presence_unknown',
        severity: 'warning',
        message: decision.userMessage,
        context: <String, Object?>{
          'peerId': normalizedPeerId,
          'mediaMode': mediaMode.name,
          'reasonCode': decision.reasonCode.name,
          'presenceSource': 'backend',
        },
      );
      return const VoiceCallStartPresenceSnapshot(
        peerOnline: null,
        diagnostics: <String, Object?>{'presenceSource': 'backend'},
      );
    }

    if (!presence.online) {
      final decision = RuntimeInteractionGuard.peerOffline(
        peerId: normalizedPeerId,
      );
      recordRuntimeEvent(
        category: 'call',
        name: 'call_start_blocked_offline',
        severity: 'warning',
        message: decision.userMessage,
        context: <String, Object?>{
          'peerId': normalizedPeerId,
          'mediaMode': mediaMode.name,
          'reasonCode': decision.reasonCode.name,
          ...presence.diagnostics,
        },
      );
      return VoiceCallStartPresenceSnapshot(
        peerOnline: false,
        diagnostics: presence.diagnostics,
      );
    }

    recordRuntimeEvent(
      category: 'call',
      name: 'call_start_presence_confirmed',
      context: <String, Object?>{
        'peerId': normalizedPeerId,
        'mediaMode': mediaMode.name,
        ...presence.diagnostics,
      },
    );
    return VoiceCallStartPresenceSnapshot(
      peerOnline: true,
      diagnostics: presence.diagnostics,
    );
  }

  bool canReplaceVoiceCallWithRetry(VoiceCallState current) {
    return !current.isOutgoing &&
        current.phase == VoiceCallPhase.incomingRinging;
  }

  Future<void> replaceStaleVoiceCallForRetry(
    VoiceCallState current, {
    required VoiceCallSession? currentSession,
    required VoiceCallBoundedCleanup runBoundedCleanupStep,
    required Future<void> Function({
      required String peerId,
      required String callId,
      required String reason,
    })
    sendHangupFrame,
    required Future<void> Function() disposeCurrentVoiceCallSession,
    required void Function(VoiceCallState) setVoiceCallState,
  }) async {
    final peerId = current.peerId;
    if (peerId == null) {
      await disposeCurrentVoiceCallSession();
      setVoiceCallState(const VoiceCallState.idle());
      return;
    }

    final session = currentSession;
    if (session != null && current.callId == session.callId) {
      await runBoundedCleanupStep(
        'voice_call_stale_retry_hangup',
        () => session.hangUp(reason: 'Replaced by newer voice call invite.'),
        context: <String, Object?>{
          'peerId': session.remotePeerId,
          'callId': session.callId,
          'sessionEpoch': session.sessionEpoch,
        },
      );
    } else if (current.callId != null) {
      await sendHangupFrame(
        peerId: peerId,
        callId: current.callId!,
        reason: 'Replaced by newer voice call invite.',
      );
    }
    await disposeCurrentVoiceCallSession();
    setVoiceCallState(const VoiceCallState.idle());
  }
}
