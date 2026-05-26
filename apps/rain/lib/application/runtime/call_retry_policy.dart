enum CallRetryDecisionKind {
  proceed,
  peerBusy,
  peerOffline,
  cleanedStaleState,
  cleanupInProgress,
  signalingFailed,
}

final class CallSignalingFailureSnapshot {
  const CallSignalingFailureSnapshot({
    required this.message,
    required this.lockWasReclaimed,
    required this.terminalRoomWasCleaned,
    required this.corruptRoomWasRepaired,
    this.cleanupInProgress = false,
    this.peerId,
  });

  final String message;
  final bool lockWasReclaimed;
  final bool terminalRoomWasCleaned;
  final bool corruptRoomWasRepaired;
  final bool cleanupInProgress;
  final String? peerId;
}

final class CallRetryDecision {
  const CallRetryDecision({
    required this.kind,
    required this.userMessage,
    this.canRetryImmediately = false,
  });

  final CallRetryDecisionKind kind;
  final String userMessage;
  final bool canRetryImmediately;
}

final class CallRetryPolicy {
  const CallRetryPolicy._();

  static const String staleCallCleanedMessage =
      'Old call state was cleaned. Try again.';
  static const String cleanupInProgressMessage =
      'Call state is cleaning up. Try again in a moment.';
  static const String signalingFailedMessage =
      'Call signaling failed. Try again.';

  static CallRetryDecision classifySignalingFailure(
    CallSignalingFailureSnapshot failure,
  ) {
    final message = failure.message.toLowerCase();
    final peer = _peerLabel(failure.peerId);
    if (failure.cleanupInProgress ||
        message.contains('cleanup in progress') ||
        message.contains('cleaning up')) {
      return const CallRetryDecision(
        kind: CallRetryDecisionKind.cleanupInProgress,
        userMessage: cleanupInProgressMessage,
      );
    }
    if (failure.lockWasReclaimed ||
        failure.terminalRoomWasCleaned ||
        failure.corruptRoomWasRepaired ||
        message.contains('timestamps are invalid') ||
        message.contains('old call state was cleaned') ||
        message.contains('corrupt terminal') ||
        message.contains('terminal room')) {
      return const CallRetryDecision(
        kind: CallRetryDecisionKind.cleanedStaleState,
        userMessage: staleCallCleanedMessage,
        canRetryImmediately: true,
      );
    }
    if (_isPresenceUnknownMessage(message)) {
      return CallRetryDecision(
        kind: CallRetryDecisionKind.peerOffline,
        userMessage: 'Could not confirm $peer is online. Try again.',
      );
    }
    if (isOfflineMessage(message)) {
      return CallRetryDecision(
        kind: CallRetryDecisionKind.peerOffline,
        userMessage:
            '${_peerLabel(failure.peerId)} is offline. Keep both apps open, then try again.',
      );
    }
    if (isBusyConflictMessage(message)) {
      return CallRetryDecision(
        kind: CallRetryDecisionKind.peerBusy,
        userMessage: '$peer is busy in another call.',
      );
    }
    return const CallRetryDecision(
      kind: CallRetryDecisionKind.signalingFailed,
      userMessage: signalingFailedMessage,
    );
  }

  static bool isBusyConflictMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('peer is busy') ||
        normalized == 'busy.' ||
        normalized.contains('active voice call already exists') ||
        normalized.contains('activevoicepairs') ||
        normalized.contains('active voice pair') ||
        normalized.contains('activevoiceusers') ||
        normalized.contains('active voice user');
  }

  static bool isCleanupConflictMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('timestamps are invalid') ||
        normalized.contains('old call state was cleaned') ||
        normalized.contains('corrupt terminal') ||
        normalized.contains('terminal room') ||
        normalized.contains('cleanup in progress') ||
        normalized.contains('cleaning up');
  }

  static bool isOfflineMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains(' is offline') ||
        normalized.contains('peer is offline') ||
        normalized.contains('could not confirm') ||
        normalized.contains('presence unknown') ||
        normalized.contains('callee presence');
  }

  static bool _isPresenceUnknownMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('could not confirm') ||
        normalized.contains('presence unknown') ||
        normalized.contains('callee presence');
  }

  static String _peerLabel(String? peerId) {
    final normalized = peerId?.trim().replaceFirst(RegExp(r'^@+'), '');
    if (normalized == null || normalized.isEmpty) {
      return 'Peer';
    }
    return '@$normalized';
  }
}
