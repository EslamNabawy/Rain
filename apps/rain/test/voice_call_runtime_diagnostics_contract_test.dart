import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('late voice signaling frames are diagnostics, not crash errors', () {
    final runtimeSource = _runtimeSource();
    final lateFrameHandler = _sliceFunction(
      runtimeSource,
      'void _recordLateVoiceFrame',
      'Map<String, Object?> _voiceCallEventContext',
    );

    expect(lateFrameHandler, contains("recordRuntimeEvent("));
    expect(
      lateFrameHandler,
      isNot(contains('errorRecorder?.call')),
      reason:
          'Expected terminal races should not replace the latest real Flutter '
          'error in exported diagnostics.',
    );
  });

  test('local hangup writes terminal room before best-effort session frame', () {
    final runtimeSource = _runtimeSource();
    final endForPeer = _sliceFunction(
      runtimeSource,
      'Future<void> _endVoiceCallForPeer',
      'Future<_TerminalRoomWriteResult> _writeTerminalRoomBeforeSessionHangup',
    );

    final terminalWriteIndex = endForPeer.indexOf(
      '_writeTerminalRoomBeforeSessionHangup',
    );
    final sessionHangupIndex = endForPeer.indexOf(
      "'voice_call_session_hangup'",
    );

    expect(terminalWriteIndex, greaterThanOrEqualTo(0));
    expect(sessionHangupIndex, greaterThanOrEqualTo(0));
    expect(
      terminalWriteIndex,
      lessThan(sessionHangupIndex),
      reason:
          'Firebase terminal room state must be durable before any best-effort '
          'data-channel/session hangup frame. Otherwise the remote voice side '
          'can stay active when the frame fails.',
    );
  });

  test('failed media sessions write terminal room before disposal', () {
    final sessionStateSource = _sourceFile(
      'voice_call_session_state_coordinator.dart',
    );
    final finalizeFailure = _sliceFunction(
      sessionStateSource,
      'Future<void> finalizeFailedVoiceCallSession',
      'void recordVoiceCallSessionFailure',
    );

    final terminalWriteIndex = finalizeFailure.indexOf(
      'writeTerminalRoomBeforeSessionHangup',
    );
    final disposeIndex = finalizeFailure.indexOf(
      'await disposeVoiceCallSession(session)',
    );

    expect(terminalWriteIndex, greaterThanOrEqualTo(0));
    expect(disposeIndex, greaterThanOrEqualTo(0));
    expect(terminalWriteIndex, lessThan(disposeIndex));
    expect(
      finalizeFailure,
      contains('failed_session_terminal_write_not_durable'),
      reason:
          'A failed media setup must leave a diagnostic when terminal Firebase '
          'state cannot be written, instead of silently sticking the peer.',
    );
  });

  test('terminal failure state is published before session cleanup', () {
    final runtimeSource = _runtimeSource();
    final settleTerminal = _sliceFunction(
      runtimeSource,
      'Future<void> _settleVoiceCallAfterTerminalRace',
      'Future<void> _endVoiceCallForPeer',
    );

    final failureBranchIndex = settleTerminal.indexOf(
      'if (failureReason != null)',
    );
    final publishFailedIndex = settleTerminal.indexOf(
      '_setVoiceCallState(failedState)',
      failureBranchIndex,
    );
    final disposeIndex = settleTerminal.indexOf(
      'await _disposeVoiceCallSession(session)',
      failureBranchIndex,
    );

    expect(failureBranchIndex, greaterThanOrEqualTo(0));
    expect(publishFailedIndex, greaterThanOrEqualTo(0));
    expect(disposeIndex, greaterThanOrEqualTo(0));
    expect(
      publishFailedIndex,
      lessThan(disposeIndex),
      reason:
          'A terminal Firebase failure must unblock file transfer and call '
          'retry state before WebRTC cleanup can stall.',
    );
  });

  test('voice call cleanup is bounded during terminal disposal', () {
    final cleanupSource = _sourceFile(
      'voice_call_signaling_cleanup_coordinator.dart',
    );
    final cleanupStep = _sliceFunction(
      cleanupSource,
      'Future<bool> runBoundedVoiceCleanupStep',
      'Future<void> disposeVoiceIceCandidateBatcher',
    );
    final disposeSession = _sliceFunction(
      cleanupSource,
      'Future<void> disposeVoiceCallSession',
      'Future<bool> runBoundedVoiceCleanupStep',
    );

    expect(cleanupStep, contains('cleanupStepTimeout'));
    expect(cleanupStep, contains('.timeout('));
    expect(cleanupStep, contains("name: '\${step}_timeout'"));
    expect(disposeSession, contains("runBoundedCleanupStep("));
    expect(disposeSession, contains("'voice_call_session_dispose'"));
  });

  test('local hangup publishes terminal state before session hangup', () {
    final runtimeSource = _runtimeSource();
    final endForPeer = _sliceFunction(
      runtimeSource,
      'Future<void> _endVoiceCallForPeer',
      'Future<_TerminalRoomWriteResult> _writeTerminalRoomBeforeSessionHangup',
    );

    final terminalStateIndex = endForPeer.indexOf(
      '_voiceCallStateAfterLocalEnd',
    );
    final sessionHangupIndex = endForPeer.indexOf(
      "'voice_call_session_hangup'",
    );

    expect(terminalStateIndex, greaterThanOrEqualTo(0));
    expect(sessionHangupIndex, greaterThanOrEqualTo(0));
    expect(
      terminalStateIndex,
      lessThan(sessionHangupIndex),
      reason:
          'The UI state must leave active/ending before best-effort media '
          'session hangup can block cleanup.',
    );
  });

  test('already-terminal Firebase errors are treated as durable cleanup', () {
    final cleanupSource = _sourceFile(
      'voice_call_signaling_cleanup_coordinator.dart',
    );
    final terminalWrite = _sourceFrom(
      cleanupSource,
      'writeTerminalRoomBeforeSessionHangup',
    );

    expect(terminalWrite, contains('isDurableTerminalStateError'));
    expect(terminalWrite, contains("'cleanupResult': 'alreadyCompleted'"));
    expect(
      terminalWrite,
      contains('VoiceCallSignalingTerminalWriteOutcome.durable()'),
    );
  });

  test('terminal room preflight runs before media signaling writes', () {
    final cleanupSource = _sourceFile(
      'voice_call_signaling_cleanup_coordinator.dart',
    );
    final sendFrame = _sliceFunction(
      cleanupSource,
      'Future<void> sendVoiceFrameObject',
      'Future<bool> shouldSkipTerminalSensitiveVoiceFrame',
    );
    final terminalPreflightIndex = sendFrame.indexOf(
      'shouldSkipTerminalSensitiveVoiceFrame',
    );
    final writeOfferIndex = sendFrame.indexOf('writeVoiceOffer');
    final writeAnswerIndex = sendFrame.indexOf('writeVoiceAnswer');
    final acceptIndex = sendFrame.indexOf('acceptCall');

    expect(terminalPreflightIndex, greaterThanOrEqualTo(0));
    expect(writeOfferIndex, greaterThanOrEqualTo(0));
    expect(writeAnswerIndex, greaterThanOrEqualTo(0));
    expect(acceptIndex, greaterThanOrEqualTo(0));
    expect(terminalPreflightIndex, lessThan(writeOfferIndex));
    expect(terminalPreflightIndex, lessThan(writeAnswerIndex));
    expect(terminalPreflightIndex, lessThan(acceptIndex));

    final terminalPreflight = _sliceFunction(
      cleanupSource,
      'Future<bool> shouldSkipTerminalSensitiveVoiceFrame',
      'bool requiresTerminalVoiceRoomPreflight',
    );
    expect(terminalPreflight, contains('voiceAdapter.fetchCall(frame.callId)'));
    expect(
      terminalPreflight,
      contains('voice_late_media_frame_ignored_after_terminal'),
    );
    expect(terminalPreflight, contains('reconcileTerminalVoiceRoom'));
    expect(
      terminalPreflight,
      isNot(contains('errorRecorder?.call')),
      reason:
          'Terminal room races during late media signaling are expected cleanup '
          'events and must not replace the latest real diagnostics error.',
    );
  });
}

String _runtimeSource() {
  for (final path in <String>[
    'lib/application/runtime/voice_call_runtime.dart',
    'apps/rain/lib/application/runtime/voice_call_runtime.dart',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  throw StateError('Could not locate voice_call_runtime.dart.');
}

String _sourceFile(String fileName) {
  for (final path in <String>[
    'lib/application/runtime/voice_call/$fileName',
    'apps/rain/lib/application/runtime/voice_call/$fileName',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  throw StateError('Could not locate $fileName.');
}

String _sliceFunction(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);
  if (start < 0 || end < 0 || end <= start) {
    throw StateError('Could not slice $startMarker from runtime source.');
  }
  return source.substring(start, end);
}

String _sourceFrom(String source, String startMarker) {
  final start = source.indexOf(startMarker);
  if (start < 0) {
    throw StateError('Could not slice $startMarker from source.');
  }
  return source.substring(start);
}
