import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('late voice signaling frames are diagnostics, not crash errors', () {
    final runtimeSource = File(
      'lib/application/runtime/voice_call_runtime.dart',
    ).readAsStringSync();
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
}

String _sliceFunction(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);
  if (start < 0 || end < 0 || end <= start) {
    throw StateError('Could not slice $startMarker from runtime source.');
  }
  return source.substring(start, end);
}
