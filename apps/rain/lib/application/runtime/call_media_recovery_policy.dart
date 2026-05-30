enum CallMediaRecoveryDecision {
  wait,
  iceRestart,
  fullReoffer,
  terminalFailure,
}

final class CallMediaRecoveryPolicy {
  const CallMediaRecoveryPolicy({
    this.disconnectedGrace = const Duration(seconds: 8),
    this.iceRestartTimeout = const Duration(seconds: 12),
    this.fullReofferTimeout = const Duration(seconds: 20),
  });

  final Duration disconnectedGrace;
  final Duration iceRestartTimeout;
  final Duration fullReofferTimeout;
}
