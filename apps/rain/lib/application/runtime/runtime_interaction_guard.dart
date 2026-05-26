import 'package:rain_core/rain_core.dart';

import 'voice_call_state.dart';

enum RuntimeInteractionReasonCode {
  none,
  manualDisconnectActive,
  peerConnectionUnavailable,
  activeCall,
  noIncomingCall,
  activeFileTransfer,
  peerBusy,
  staleCallCleanup,
  callCleanupInProgress,
}

final class RuntimeInteractionDecision {
  const RuntimeInteractionDecision._({
    required this.allowed,
    required this.reasonCode,
    required this.userMessage,
    this.blockingPeerId,
    this.callId,
    this.transferId,
  });

  const RuntimeInteractionDecision.allow()
    : this._(
        allowed: true,
        reasonCode: RuntimeInteractionReasonCode.none,
        userMessage: null,
      );

  const RuntimeInteractionDecision.deny({
    required RuntimeInteractionReasonCode reasonCode,
    required String userMessage,
    String? blockingPeerId,
    String? callId,
    String? transferId,
  }) : this._(
         allowed: false,
         reasonCode: reasonCode,
         userMessage: userMessage,
         blockingPeerId: blockingPeerId,
         callId: callId,
         transferId: transferId,
       );

  final bool allowed;
  final RuntimeInteractionReasonCode reasonCode;
  final String? userMessage;
  final String? blockingPeerId;
  final String? callId;
  final String? transferId;

  void throwIfDenied() {
    if (!allowed) {
      throw StateError(userMessage ?? 'Action is unavailable right now.');
    }
  }
}

final class RuntimeInteractionGuard {
  const RuntimeInteractionGuard._();

  static String peerBusyMessage(String peerId) {
    final normalized = peerId.trim().replaceFirst(RegExp(r'^@+'), '');
    if (normalized.isEmpty) {
      return 'Peer is busy in another call.';
    }
    return '@$normalized is busy in another call.';
  }

  static const String staleCallCleanedMessage =
      'Old call state was cleaned. Try again.';
  static const String cleanupInProgressMessage =
      'Call state is cleaning up. Try again in a moment.';

  static RuntimeInteractionDecision peerBusy({
    required String peerId,
    String? callId,
  }) {
    return RuntimeInteractionDecision.deny(
      reasonCode: RuntimeInteractionReasonCode.peerBusy,
      userMessage: peerBusyMessage(peerId),
      blockingPeerId: peerId,
      callId: callId,
    );
  }

  static RuntimeInteractionDecision staleCallCleanup({
    String? peerId,
    String? callId,
  }) {
    return RuntimeInteractionDecision.deny(
      reasonCode: RuntimeInteractionReasonCode.staleCallCleanup,
      userMessage: staleCallCleanedMessage,
      blockingPeerId: peerId,
      callId: callId,
    );
  }

  static RuntimeInteractionDecision callCleanupInProgress({
    String? peerId,
    String? callId,
  }) {
    return RuntimeInteractionDecision.deny(
      reasonCode: RuntimeInteractionReasonCode.callCleanupInProgress,
      userMessage: cleanupInProgressMessage,
      blockingPeerId: peerId,
      callId: callId,
    );
  }

  static RuntimeInteractionDecision canConnectPeer({
    required String peerId,
    required bool interactive,
    required Set<String> manualDisconnectedPeers,
    required bool peerConnectionAvailable,
  }) {
    if (!peerConnectionAvailable) {
      return const RuntimeInteractionDecision.deny(
        reasonCode: RuntimeInteractionReasonCode.peerConnectionUnavailable,
        userMessage: 'Peer connection is unavailable right now.',
      );
    }
    if (!interactive && manualDisconnectedPeers.contains(peerId)) {
      return RuntimeInteractionDecision.deny(
        reasonCode: RuntimeInteractionReasonCode.manualDisconnectActive,
        userMessage:
            'You disconnected @$peerId. Press Connect to open the peer lane again.',
        blockingPeerId: peerId,
      );
    }
    return const RuntimeInteractionDecision.allow();
  }

  static RuntimeInteractionDecision canAutoRecoverPeer({
    required String peerId,
    required Set<String> manualDisconnectedPeers,
  }) {
    if (manualDisconnectedPeers.contains(peerId)) {
      return RuntimeInteractionDecision.deny(
        reasonCode: RuntimeInteractionReasonCode.manualDisconnectActive,
        userMessage:
            'You disconnected @$peerId. Press Connect to open the peer lane again.',
        blockingPeerId: peerId,
      );
    }
    return const RuntimeInteractionDecision.allow();
  }

  static RuntimeInteractionDecision canStartCall({
    required String peerId,
    required CallMediaMode mediaMode,
    required VoiceCallState voiceCallState,
    FileTransferRecord? activeTransfer,
  }) {
    final callBlock = _activeCallDecision(
      voiceCallState,
      attemptedPeerId: peerId,
    );
    if (callBlock != null) {
      return callBlock;
    }
    if (activeTransfer != null) {
      return RuntimeInteractionDecision.deny(
        reasonCode: RuntimeInteractionReasonCode.activeFileTransfer,
        userMessage: 'Finish the active file transfer before starting a call.',
        blockingPeerId: activeTransfer.peerId,
        transferId: activeTransfer.id,
      );
    }
    return const RuntimeInteractionDecision.allow();
  }

  static RuntimeInteractionDecision canAcceptCall({
    required String peerId,
    required String callId,
    required VoiceCallState voiceCallState,
    FileTransferRecord? activeTransfer,
  }) {
    if (voiceCallState.phase != VoiceCallPhase.incomingRinging ||
        voiceCallState.peerId != peerId ||
        voiceCallState.callId != callId) {
      return const RuntimeInteractionDecision.deny(
        reasonCode: RuntimeInteractionReasonCode.noIncomingCall,
        userMessage: 'There is no incoming call to accept.',
      );
    }
    if (activeTransfer != null) {
      return RuntimeInteractionDecision.deny(
        reasonCode: RuntimeInteractionReasonCode.activeFileTransfer,
        userMessage: 'Finish the active file transfer before starting a call.',
        blockingPeerId: activeTransfer.peerId,
        transferId: activeTransfer.id,
      );
    }
    return const RuntimeInteractionDecision.allow();
  }

  static RuntimeInteractionDecision canStartFileTransfer({
    required String peerId,
    required VoiceCallState voiceCallState,
  }) {
    if (_callBlocksFileTransfer(voiceCallState)) {
      return RuntimeInteractionDecision.deny(
        reasonCode: RuntimeInteractionReasonCode.activeCall,
        userMessage: 'Finish the call before sending files.',
        blockingPeerId: voiceCallState.peerId,
        callId: voiceCallState.callId,
      );
    }
    return const RuntimeInteractionDecision.allow();
  }

  static RuntimeInteractionDecision canAcceptFileTransfer({
    required String peerId,
    required String transferId,
    required VoiceCallState voiceCallState,
  }) {
    if (_callBlocksFileTransfer(voiceCallState)) {
      return RuntimeInteractionDecision.deny(
        reasonCode: RuntimeInteractionReasonCode.activeCall,
        userMessage: 'Finish the call before sending files.',
        blockingPeerId: voiceCallState.peerId,
        callId: voiceCallState.callId,
        transferId: transferId,
      );
    }
    return const RuntimeInteractionDecision.allow();
  }

  static RuntimeInteractionDecision? _activeCallDecision(
    VoiceCallState state, {
    required String attemptedPeerId,
  }) {
    if (!state.hasCall || state.phase == VoiceCallPhase.failed) {
      return null;
    }
    final blockingPeerId = state.peerId;
    final message = blockingPeerId != null && blockingPeerId != attemptedPeerId
        ? 'You are already in a call with @$blockingPeerId. End it before calling @$attemptedPeerId.'
        : 'Finish the active call before starting another.';
    return RuntimeInteractionDecision.deny(
      reasonCode: RuntimeInteractionReasonCode.activeCall,
      userMessage: message,
      blockingPeerId: blockingPeerId,
      callId: state.callId,
    );
  }

  static bool _callBlocksFileTransfer(VoiceCallState state) {
    return state.phase != VoiceCallPhase.idle &&
        state.phase != VoiceCallPhase.failed;
  }
}
