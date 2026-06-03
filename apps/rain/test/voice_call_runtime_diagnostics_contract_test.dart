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

    expect(lateFrameHandler, contains("_recordRuntimeEvent("));
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
    final sessionHangupIndex = endForPeer.indexOf('await session.hangUp');

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
    final runtimeSource = _runtimeSource();
    final finalizeFailure = _sliceFunction(
      runtimeSource,
      'Future<void> _finalizeFailedVoiceCallSession',
      'VoiceCallPhase _mapVoiceCallSessionPhase',
    );

    final terminalWriteIndex = finalizeFailure.indexOf(
      '_writeTerminalRoomBeforeSessionHangup',
    );
    final disposeIndex = finalizeFailure.indexOf(
      'await _disposeVoiceCallSession(session)',
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

  test('already-terminal Firebase errors are treated as durable cleanup', () {
    final runtimeSource = _runtimeSource();
    final terminalWrite = _sliceFunction(
      runtimeSource,
      'Future<_TerminalRoomWriteResult> _writeTerminalRoomBeforeSessionHangup',
      'VoiceCallState _voiceCallStateAfterTerminalWriteFailure',
    );

    expect(terminalWrite, contains('_isDurableVoiceCallTerminalStateError'));
    expect(terminalWrite, contains("'cleanupResult': 'alreadyCompleted'"));
    expect(terminalWrite, contains('_TerminalRoomWriteResult.durable()'));
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

String _sliceFunction(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);
  if (start < 0 || end < 0 || end <= start) {
    throw StateError('Could not slice $startMarker from runtime source.');
  }
  return source.substring(start, end);
}
