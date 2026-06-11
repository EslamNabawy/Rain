/// # call_media_recovery_policy.dart
///
/// Defines [CallMediaRecoveryDecision] (wait, iceRestart, fullReoffer,
/// terminalFailure) and the [CallMediaRecoveryPolicy] value object that holds
/// the timeout budgets for each recovery phase when WebRTC media degrades.
///
/// **Key types:** [CallMediaRecoveryDecision], [CallMediaRecoveryPolicy]
///
/// **Depends on:** voice call media recovery

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
