import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/services/crash_diagnostics_service.dart';
import 'package:rain/infrastructure/services/rain_debug_log_service.dart';
import 'package:rain/infrastructure/signaling/debug_signaling_adapter.dart';

void main() {
  test(
    'debug facade records recursively sanitized events and errors',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'rain-debug-log-service-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final exportPath = _join(temp.path, 'debug-export.json');
      final diagnostics = _diagnosticsService(temp, exportPath);
      await diagnostics.initialize();
      final debugLog = CrashDiagnosticsDebugLogService(
        diagnostics: diagnostics,
        enabled: true,
      );

      debugLog.event(
        category: 'call',
        name: 'unit_event',
        context: const <String, Object?>{
          'peerId': 'bob',
          'token': 'secret-token',
          'nested': <String, Object?>{
            'candidate': 'candidate:1 1 udp raw',
            'messageText': 'hello',
            'safe': 'kept',
          },
        },
      );
      debugLog.error(
        StateError('boom'),
        StackTrace.fromString('debug-stack'),
        source: 'unit-test',
        context: const <String, Object?>{'password': 'pw', 'phase': 'start'},
      );

      await diagnostics.exportDiagnostics();
      final encoded = await File(exportPath).readAsString();
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(encoded, isNot(contains('secret-token')));
      expect(encoded, isNot(contains('candidate:1 1 udp raw')));
      expect(encoded, isNot(contains('hello')));
      expect(encoded, isNot(contains('"pw"')));
      expect(encoded, contains('[redacted]'));
      expect(encoded, contains('unit-test'));
      expect(decoded['debugEventSummary'], isA<Map<String, dynamic>>());
    },
  );

  test(
    'disabled service drops nonfatal details but keeps fatal errors',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'rain-debug-log-disabled-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final exportPath = _join(temp.path, 'disabled-export.json');
      final diagnostics = _diagnosticsService(temp, exportPath);
      await diagnostics.initialize();
      final debugLog = CrashDiagnosticsDebugLogService(
        diagnostics: diagnostics,
        enabled: false,
      );

      debugLog.event(category: 'call', name: 'dropped_event');
      debugLog.error(
        StateError('dropped-error'),
        StackTrace.current,
        source: 'nonfatal',
        fatal: false,
      );
      debugLog.error(
        StateError('fatal-error'),
        StackTrace.fromString('fatal-stack'),
        source: 'fatal-source',
        fatal: true,
      );

      await diagnostics.exportDiagnostics();
      final encoded = await File(exportPath).readAsString();

      expect(encoded, isNot(contains('dropped_event')));
      expect(encoded, isNot(contains('dropped-error')));
      expect(encoded, contains('fatal-error'));
      expect(encoded, contains('fatal-source'));
    },
  );

  test(
    'provider observer logs type summaries without serializing values',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'rain-debug-log-provider-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final exportPath = _join(temp.path, 'provider-export.json');
      final diagnostics = _diagnosticsService(temp, exportPath);
      await diagnostics.initialize();
      final debugLog = CrashDiagnosticsDebugLogService(
        diagnostics: diagnostics,
        enabled: true,
      );
      final provider = NotifierProvider<_StringNotifier, String>(
        _StringNotifier.new,
        name: 'secretText',
      );
      final container = ProviderContainer(
        observers: <ProviderObserver>[RainDebugProviderObserver(debugLog)],
      );
      addTearDown(container.dispose);

      expect(container.read(provider), 'initial');
      container.read(provider.notifier).setValue('raw-user-message');

      await diagnostics.exportDiagnostics();
      final encoded = await File(exportPath).readAsString();
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;

      expect(encoded, contains('secretText'));
      expect(encoded, contains('String'));
      expect(encoded, isNot(contains('raw-user-message')));
      expect(decoded['uiStateSummary'], isA<Map<String, dynamic>>());
    },
  );

  test('signaling decorator logs metadata without raw SDP', () async {
    final temp = await Directory.systemTemp.createTemp(
      'rain-debug-log-signaling-test-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final exportPath = _join(temp.path, 'signaling-export.json');
    final diagnostics = _diagnosticsService(temp, exportPath);
    await diagnostics.initialize();
    final debugLog = CrashDiagnosticsDebugLogService(
      diagnostics: diagnostics,
      enabled: true,
    );
    final fake = _FakeSignalingAdapter();
    final adapter = wrapSignalingAdapterWithDebugLogging(fake, debugLog);

    await adapter.writeOffer(
      'room-1',
      SDPPayload(
        sdp: RTCSessionDescription('RAW-SDP-SHOULD-NOT-BE-LOGGED', 'offer'),
        ts: 1,
      ),
    );
    await adapter.writeICE(
      'room-1',
      IceRole.caller,
      RTCIceCandidate('candidate:1 1 udp raw', '0', 0),
    );
    fake.writeIceError = StateError('permission denied');
    await expectLater(
      adapter.writeICE(
        'room-1',
        IceRole.caller,
        RTCIceCandidate('candidate:2 1 udp raw', '0', 0),
      ),
      throwsStateError,
    );

    await diagnostics.exportDiagnostics();
    final encoded = await File(exportPath).readAsString();
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    final lastCrash = decoded['lastCrash'] as Map<String, dynamic>;
    final lastCrashContext = lastCrash['context'] as Map<String, dynamic>;

    expect(encoded, contains('writeOffer'));
    expect(encoded, contains('writeICE'));
    expect(encoded, contains('rooms/{roomId}/callerICE/{candidateId}'));
    expect(encoded, contains('sdpLength'));
    expect(encoded, isNot(contains('RAW-SDP-SHOULD-NOT-BE-LOGGED')));
    expect(encoded, isNot(contains('candidate:1 1 udp raw')));
    expect(encoded, isNot(contains('candidate:2 1 udp raw')));
    expect(
      lastCrashContext['pathTemplate'],
      'rooms/{roomId}/callerICE/{candidateId}',
    );
    expect(decoded['networkTraceSummary'], isA<Map<String, dynamic>>());
  });
}

CrashDiagnosticsService _diagnosticsService(Directory temp, String exportPath) {
  return CrashDiagnosticsService(
    directoryProvider: () async => temp,
    eventFlushInterval: const Duration(minutes: 1),
    saveFile:
        ({
          String? dialogTitle,
          String? fileName,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Uint8List? bytes,
          bool lockParentWindow = false,
        }) async {
          return exportPath;
        },
  );
}

String _join(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

final class _FakeSignalingAdapter implements SignalingAdapter {
  Object? writeIceError;

  @override
  Future<void> reauthenticate(String username, String password) async {}

  @override
  Future<void> deleteAccount(String username) async {}

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {}

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    RTCIceCandidate candidate,
  ) async {
    final error = writeIceError;
    if (error != null) {
      throw error;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _StringNotifier extends Notifier<String> {
  @override
  String build() => 'initial';

  void setValue(String value) {
    state = value;
  }
}
