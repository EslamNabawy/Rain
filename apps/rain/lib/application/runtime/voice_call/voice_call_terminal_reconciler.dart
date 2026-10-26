/// # voice_call_terminal_reconciler.dart
///
/// [VoiceCallTerminalReconciler] decides whether an incoming terminal session
/// state should be applied or ignored (e.g. ignored after a terminal failure
/// or after the room has already been cleaned up). Prevents stale state from
/// overwriting terminal call conclusions.
///
/// **Key types:** [VoiceCallTerminalReconciler], [VoiceCallTerminalSessionDecision]
///
/// **Depends on:** protocol_brain, voice call state
library;

import 'package:protocol_brain/protocol_brain.dart';

import '../voice_call_state.dart';

final class VoiceCallTerminalSessionDecision {
  const VoiceCallTerminalSessionDecision.apply() : ignoredReason = null;

  const VoiceCallTerminalSessionDecision.ignore(this.ignoredReason);

  final String? ignoredReason;

  bool get shouldApply => ignoredReason == null;
}

final class VoiceCallTerminalReconciler {
  const VoiceCallTerminalReconciler._();

  static VoiceCallTerminalSessionDecision sessionStateDecision({
    required bool terminalLatched,
    required VoiceCallState current,
    required String callId,
    required int sessionEpoch,
    required VoiceCallSessionPhase incomingPhase,
  }) {
    if (!terminalLatched) {
      return const VoiceCallTerminalSessionDecision.apply();
    }
    final sameCall =
        current.callId == callId && current.sessionEpoch == sessionEpoch;
    if (sameCall && current.phase == VoiceCallPhase.failed) {
      return VoiceCallTerminalSessionDecision.ignore(
        'ignored ${incomingPhase.name} state after terminal failure',
      );
    }
    if (incomingPhase != VoiceCallSessionPhase.idle) {
      return VoiceCallTerminalSessionDecision.ignore(
        'ignored ${incomingPhase.name} state after terminal room',
      );
    }
    return const VoiceCallTerminalSessionDecision.apply();
  }
}
