/// # voice_call_runtime_media_path_test.dart
///
/// Contract tests verifying that voice call runtime uses dedicated media connections for app calls, avoids legacy SessionManager methods, and attaches Firebase watchers in the correct order after room creation.
///
/// **Key types:** (no top-level declarations — source-inspection tests)
///
/// **Depends on:** dart:io for source file reading and regex analysis
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice call runtime uses dedicated media connections for app calls', () {
    final source =
        '${_readRuntimeSource()}\n${_readVoiceCallSourceFile('voice_call_media_coordinator.dart')}';

    expect(
      source,
      contains('manager.createCallMediaConnection(peerId)'),
      reason: 'Video calls must use the dedicated call media peer connection.',
    );
    expect(
      source,
      contains('_createAudioVoiceMediaConnection('),
      reason:
          'Audio calls must use the same hardened call media core as video.',
    );

    final forbiddenManagerCalls = <String>[
      'startLocalAudio',
      'stopLocalAudio',
      'createVoiceMediaConnection',
      'createMediaOffer',
      'applyMediaOffer',
      'applyMediaAnswer',
    ];
    for (final method in forbiddenManagerCalls) {
      final legacyCall = RegExp(r'\b(?:brain|manager)\.' + method + r'\s*\(');
      expect(
        legacyCall.hasMatch(source),
        isFalse,
        reason:
            'Voice/video runtime must not call SessionManager.$method; '
            'use VoiceMediaConnection or CallMediaConnection instead.',
      );
    }
  });

  test('outgoing calls attach Firebase watchers after invite room creation', () {
    final source = _readRuntimeSource();
    final startCall = _sourceBetween(
      source,
      'Future<void> _startCall',
      'Future<VoiceCallSession> _createVoiceCallSession',
    );
    final startOutgoing = startCall.indexOf('await session.startOutgoing();');
    final watchOutgoing = startCall.indexOf(
      '_watchFirebaseVoiceCall(',
      startOutgoing,
    );

    expect(startOutgoing, isNonNegative);
    expect(
      watchOutgoing,
      greaterThan(startOutgoing),
      reason:
          'Outgoing calls must create the Firebase call room through '
          'session.startOutgoing() before room/offer/answer/ICE watchers are '
          'attached. Attaching watchers first causes Windows caller permission '
          'denials when the room does not exist yet.',
    );

    final createSession = _sourceBetween(
      source,
      'Future<VoiceCallSession> _createVoiceCallSession',
      'Future<void> _watchFirebaseVoiceCall',
    );
    expect(
      createSession,
      contains('if (!isOutgoing)'),
      reason:
          'Incoming calls can watch immediately because the room already '
          'exists; outgoing calls must wait until the invite writes the room.',
    );
  });
}

String _readRuntimeSource() {
  final candidates = <File>[
    File('lib/application/runtime/voice_call_runtime.dart'),
    File('apps/rain/lib/application/runtime/voice_call_runtime.dart'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.readAsStringSync();
    }
  }
  fail('Could not locate voice_call_runtime.dart from ${Directory.current}.');
}

String _readVoiceCallSourceFile(String fileName) {
  final candidates = <File>[
    File('lib/application/runtime/voice_call/$fileName'),
    File('apps/rain/lib/application/runtime/voice_call/$fileName'),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.readAsStringSync();
    }
  }
  fail('Could not locate $fileName from ${Directory.current}.');
}

String _sourceBetween(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  if (startIndex < 0) {
    fail('Could not locate "$start" in voice_call_runtime.dart.');
  }
  final endIndex = source.indexOf(end, startIndex + start.length);
  if (endIndex < 0) {
    fail('Could not locate "$end" after "$start" in voice_call_runtime.dart.');
  }
  return source.substring(startIndex, endIndex);
}
