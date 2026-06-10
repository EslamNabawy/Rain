import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/voice_call/voice_call_terminal_reconciler.dart';
import 'package:rain/application/runtime/voice_call_state.dart';

void main() {
  test('allows session state when terminal room is not latched', () {
    final decision = VoiceCallTerminalReconciler.sessionStateDecision(
      terminalLatched: false,
      current: const VoiceCallState(
        phase: VoiceCallPhase.active,
        callId: 'call-1',
        sessionEpoch: 1,
      ),
      callId: 'call-1',
      sessionEpoch: 1,
      incomingPhase: VoiceCallSessionPhase.active,
    );

    expect(decision.shouldApply, isTrue);
  });

  test('keeps failed terminal state authoritative over session idle', () {
    final decision = VoiceCallTerminalReconciler.sessionStateDecision(
      terminalLatched: true,
      current: const VoiceCallState(
        phase: VoiceCallPhase.failed,
        callId: 'call-1',
        sessionEpoch: 1,
      ),
      callId: 'call-1',
      sessionEpoch: 1,
      incomingPhase: VoiceCallSessionPhase.idle,
    );

    expect(decision.shouldApply, isFalse);
    expect(decision.ignoredReason, contains('after terminal failure'));
  });

  test('ignores non-idle session state after terminal room latch', () {
    final decision = VoiceCallTerminalReconciler.sessionStateDecision(
      terminalLatched: true,
      current: const VoiceCallState(
        phase: VoiceCallPhase.ended,
        callId: 'call-1',
        sessionEpoch: 1,
      ),
      callId: 'call-1',
      sessionEpoch: 1,
      incomingPhase: VoiceCallSessionPhase.active,
    );

    expect(decision.shouldApply, isFalse);
    expect(decision.ignoredReason, contains('after terminal room'));
  });

  test('allows idle cleanup after non-failed terminal room latch', () {
    final decision = VoiceCallTerminalReconciler.sessionStateDecision(
      terminalLatched: true,
      current: const VoiceCallState(
        phase: VoiceCallPhase.ended,
        callId: 'call-1',
        sessionEpoch: 1,
      ),
      callId: 'call-1',
      sessionEpoch: 1,
      incomingPhase: VoiceCallSessionPhase.idle,
    );

    expect(decision.shouldApply, isTrue);
  });
}
