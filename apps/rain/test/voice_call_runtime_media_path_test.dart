import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice call runtime uses dedicated media connections for app calls', () {
    final source = _readRuntimeSource();

    expect(
      source,
      contains('manager.createVoiceMediaConnection(peerId)'),
      reason: 'Audio calls must use the dedicated voice media peer connection.',
    );
    expect(
      source,
      contains('manager.createCallMediaConnection(peerId)'),
      reason: 'Video calls must use the dedicated call media peer connection.',
    );

    final forbiddenManagerCalls = <String>[
      'startLocalAudio',
      'stopLocalAudio',
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
