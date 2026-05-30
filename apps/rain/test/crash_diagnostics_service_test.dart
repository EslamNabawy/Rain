import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_diagnostics.dart';
import 'package:rain/infrastructure/services/crash_diagnostics_service.dart';

void main() {
  test('records and loads the latest crash details', () async {
    final temp = await Directory.systemTemp.createTemp(
      'rain-crash-diagnostics-test-',
    );
    addTearDown(() => temp.delete(recursive: true));

    final service = CrashDiagnosticsService(
      directoryProvider: () async => temp,
      appInfoProvider: () async => const CrashDiagnosticsAppInfo(
        appName: 'Rain',
        packageName: 'com.example.rain',
        version: '0.7.0',
        buildNumber: '7',
      ),
      clock: () => DateTime.utc(2026, 5, 22, 1, 2, 3),
    );

    await service.initialize();
    service.recordErrorSync(
      StateError('connect failed'),
      StackTrace.fromString('stack-line-1'),
      source: 'test',
      fatal: true,
    );

    final record = await service.loadLastCrash();
    expect(record, isNotNull);
    expect(record!.recordedAt, DateTime.utc(2026, 5, 22, 1, 2, 3));
    expect(record.source, 'test');
    expect(record.fatal, isTrue);
    expect(record.error, contains('connect failed'));
    expect(record.stackTrace, contains('stack-line-1'));
    expect(record.appInfo.version, '0.7.0');
  });

  test(
    'exports a diagnostics JSON file with crash and event history',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'rain-crash-diagnostics-export-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final exportPath = _join(temp.path, 'exported-diagnostics.json');

      final service = CrashDiagnosticsService(
        directoryProvider: () async => temp,
        appInfoProvider: () async => const CrashDiagnosticsAppInfo(
          appName: 'Rain',
          packageName: 'com.example.rain',
          version: '0.7.0',
          buildNumber: '7',
        ),
        clock: () => DateTime.utc(2026, 5, 22, 1, 2, 3),
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
              expect(dialogTitle, 'Export Rain diagnostics');
              expect(fileName, startsWith('rain-diagnostics-'));
              expect(type, FileType.custom);
              expect(allowedExtensions, contains('json'));
              expect(lockParentWindow, isTrue);
              return exportPath;
            },
      );

      await service.initialize();
      service.recordEventSync(
        category: 'call',
        name: 'state_changed',
        context: <String, Object?>{
          'peerId': 'bob',
          'callId': 'call-1',
          'phase': 'connectingMedia',
          'sdp': List<String>.filled(900, 'x').join(),
        },
      );
      service.recordErrorSync(
        ArgumentError('bad route'),
        StackTrace.fromString('stack-line-2'),
        source: 'flutter',
        fatal: false,
      );

      final result = await service.exportDiagnostics();

      expect(result.saved, isTrue);
      expect(result.path, exportPath);
      final decoded =
          jsonDecode(await File(exportPath).readAsString())
              as Map<String, dynamic>;
      expect(decoded['exportedAt'], '2026-05-22T01:02:03.000Z');
      expect(decoded['lastCrash'], isA<Map<String, dynamic>>());
      expect(decoded['events'], isA<List<dynamic>>());
      final events = decoded['events'] as List<dynamic>;
      expect(events, isNotEmpty);
      final appEvent = events.cast<Map<String, dynamic>>().firstWhere(
        (event) => event['kind'] == 'app_event',
      );
      expect(appEvent['category'], 'call');
      expect(appEvent['name'], 'state_changed');
      expect(
        ((appEvent['context'] as Map<String, dynamic>)['sdp'] as String).length,
        lessThan(600),
      );
    },
  );

  test('app event recorder buffers events until async flush', () async {
    final temp = await Directory.systemTemp.createTemp(
      'rain-crash-diagnostics-buffer-test-',
    );
    addTearDown(() => temp.delete(recursive: true));

    final service = CrashDiagnosticsService(
      directoryProvider: () async => temp,
      eventFlushInterval: const Duration(minutes: 1),
    );

    await service.initialize();
    service.recordEventSync(category: 'connection', name: 'connect_requested');

    final eventLog = File(
      _join(_join(temp.path, 'rain_diagnostics'), 'events.jsonl'),
    );
    expect(eventLog.existsSync(), isFalse);

    await service.flushEvents();

    expect(eventLog.existsSync(), isTrue);
    expect(await eventLog.readAsString(), contains('connect_requested'));
  });

  test('app event recorder coalesces noisy repeated events', () async {
    final temp = await Directory.systemTemp.createTemp(
      'rain-crash-diagnostics-coalesce-test-',
    );
    addTearDown(() => temp.delete(recursive: true));

    final service = CrashDiagnosticsService(
      directoryProvider: () async => temp,
      eventFlushInterval: const Duration(minutes: 1),
      clock: () => DateTime.utc(2026, 5, 22, 1, 2, 3),
    );

    await service.initialize();
    for (var index = 0; index < 25; index += 1) {
      service.recordEventSync(
        category: 'connection',
        name: 'session_changed',
        context: <String, Object?>{'peerId': 'bob', 'index': index},
      );
    }
    await service.flushEvents();

    final eventLog = File(
      _join(_join(temp.path, 'rain_diagnostics'), 'events.jsonl'),
    );
    final lines = await eventLog.readAsLines();
    expect(lines, hasLength(1));
    expect(lines.single, contains('"index":24'));
  });

  test(
    'coalesces repeated voice lock events without losing newest context',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'rain-crash-diagnostics-lock-coalesce-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final exportPath = _join(temp.path, 'lock-diagnostics.json');

      final service = CrashDiagnosticsService(
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

      await service.initialize();
      service.recordEventSync(
        category: 'call',
        name: 'voice_lock_claim_blocked',
        severity: 'warning',
        context: const <String, Object?>{
          'peerId': 'bob',
          'callId': 'call-1',
          'pairId': 'alice:bob',
          'lockExpiresAt': 1,
        },
      );
      service.recordEventSync(
        category: 'call',
        name: 'voice_lock_claim_blocked',
        severity: 'warning',
        context: const <String, Object?>{
          'peerId': 'bob',
          'callId': 'call-1',
          'pairId': 'alice:bob',
          'lockExpiresAt': 2,
        },
      );

      await service.exportDiagnostics();

      final decoded =
          jsonDecode(await File(exportPath).readAsString())
              as Map<String, dynamic>;
      final events = decoded['events'] as List<dynamic>;
      expect(events, hasLength(1));
      final event = events.single as Map<String, dynamic>;
      expect(event['name'], 'voice_lock_claim_blocked');
      expect(event['count'], 2);
      final context = event['context'] as Map<String, dynamic>;
      expect(context['lockExpiresAt'], 2);
      expect(context['pairId'], 'alice:bob');
    },
  );

  test('app event log is bounded when exported', () async {
    final temp = await Directory.systemTemp.createTemp(
      'rain-crash-diagnostics-bound-test-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final exportPath = _join(temp.path, 'bounded-diagnostics.json');
    var tick = 0;

    final service = CrashDiagnosticsService(
      directoryProvider: () async => temp,
      clock: () => DateTime.utc(2026, 5, 22, 1, 2, tick++),
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

    await service.initialize();
    for (var index = 0; index < 220; index += 1) {
      service.recordEventSync(
        category: 'connection',
        name: 'session_changed',
        context: <String, Object?>{
          'index': index,
          'payload': 'network-state-${List<String>.filled(120, 'x').join()}',
        },
      );
    }

    await service.exportDiagnostics();

    final decoded =
        jsonDecode(await File(exportPath).readAsString())
            as Map<String, dynamic>;
    final events = decoded['events'] as List<dynamic>;
    expect(events.length, lessThanOrEqualTo(200));
    expect(jsonEncode(events), contains('session_changed'));
  });

  test('voice call diagnostics include video counters', () {
    final diagnostics = VoiceCallDiagnostics(
      callId: 'call-1',
      sessionEpoch: 42,
      peerId: 'bob',
      role: 'caller',
      mediaMode: 'video',
      caller: 'alice',
      callee: 'bob',
      failureCode: 'videoFirstFrameTimeout',
      userMessage: 'Video could not connect. Try again.',
      sanitizedUiError: 'Video could not connect. Try again.',
      nativeError: 'Remote video stream did not render.',
      roomStatusTimeline: const <String>['ringing', 'negotiating', 'failed'],
      iceCandidateWriteCount: 4,
      iceCandidateReadCount: 3,
      turnReadiness: 'available',
      relayFallbackAttempted: true,
      terminalWriteOutcome: 'durable',
      cleanupOutcome: 'completed',
      presenceAgeAtStartMs: 1200,
      mediaFailureReason: 'videoFirstFrameTimeout',
      failureTaxonomy: 'media_timeout',
      localAudioTrackCount: 1,
      remoteAudioTrackCount: 1,
      localVideoTrackCount: 1,
      remoteVideoTrackCount: 1,
      remoteStreamCount: 1,
      firstLocalVideoFrameAt: '2026-05-22T01:02:04.000Z',
      firstRemoteVideoFrameAt: '2026-05-22T01:02:05.000Z',
      selectedCandidateRoute: 'direct host->srflx udp pair:pair-1',
      iceStates: const <String>['checking', 'connected'],
      cameraPermissionFailureDetail: 'Camera permission required.',
      lockClaimResult: 'peerBusy',
      lockPath: 'activeVoiceUsers/bob',
      pairId: 'alice:bob',
      callerUserLock: 'alice',
      calleeUserLock: 'bob',
      lockCallId: 'call-0',
      lockExpiresAt: 1778911256590,
      lockWasReclaimed: false,
      terminalRoomWasCleaned: false,
      corruptRoomWasRepaired: false,
      timestampRepair: false,
    );

    final encoded = diagnostics.toJson();

    expect(encoded['mediaMode'], 'video');
    expect(encoded['caller'], 'alice');
    expect(encoded['callee'], 'bob');
    expect(encoded['roomStatusTimeline'], const <String>[
      'ringing',
      'negotiating',
      'failed',
    ]);
    expect(encoded['iceCandidateWriteCount'], 4);
    expect(encoded['iceCandidateReadCount'], 3);
    expect(encoded['turnReadiness'], 'available');
    expect(encoded['relayFallbackAttempted'], isTrue);
    expect(encoded['terminalWriteOutcome'], 'durable');
    expect(encoded['cleanupOutcome'], 'completed');
    expect(encoded['presenceAgeAtStartMs'], 1200);
    expect(encoded['mediaFailureReason'], 'videoFirstFrameTimeout');
    expect(encoded['failureTaxonomy'], 'media_timeout');
    expect(encoded['localAudioTrackCount'], 1);
    expect(encoded['remoteAudioTrackCount'], 1);
    expect(encoded['localVideoTrackCount'], 1);
    expect(encoded['remoteVideoTrackCount'], 1);
    expect(encoded['firstLocalVideoFrameAt'], isNotNull);
    expect(encoded['firstRemoteVideoFrameAt'], isNotNull);
    expect(encoded['selectedCandidateRoute'], contains('direct'));
    expect(encoded['iceStateHistory'], const <String>['checking', 'connected']);
    expect(encoded['sanitizedUiError'], 'Video could not connect. Try again.');
    expect(encoded['cameraPermissionFailureDetail'], contains('Camera'));
    expect(encoded['lockClaimResult'], 'peerBusy');
    expect(encoded['lockPath'], 'activeVoiceUsers/bob');
    expect(encoded['pairId'], 'alice:bob');
    expect(encoded['callerUserLock'], 'alice');
    expect(encoded['calleeUserLock'], 'bob');
    expect(encoded['lockCallId'], 'call-0');
    expect(encoded['lockExpiresAt'], 1778911256590);
    expect(encoded['lockWasReclaimed'], isFalse);
    expect(encoded['terminalRoomWasCleaned'], isFalse);
    expect(encoded['corruptRoomWasRepaired'], isFalse);
    expect(encoded['timestampRepair'], isFalse);
  });

  test('diagnostics export preserves full native voice call error', () async {
    final temp = await Directory.systemTemp.createTemp(
      'rain-crash-diagnostics-voice-test-',
    );
    addTearDown(() => temp.delete(recursive: true));
    final exportPath = _join(temp.path, 'voice-diagnostics.json');

    final service = CrashDiagnosticsService(
      directoryProvider: () async => temp,
      clock: () => DateTime.utc(2026, 5, 22, 1, 2, 3),
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

    await service.initialize();
    service.recordErrorSync(
      const VoiceCallDiagnostics(
        callId: 'call-1',
        sessionEpoch: 42,
        peerId: 'bob',
        role: 'caller',
        mediaMode: 'video',
        failureCode: 'failed',
        userMessage: 'Video could not connect. Try again.',
        sanitizedUiError: 'Video could not connect. Try again.',
        nativeError: 'Unable to RTCRtpTransceiver::setDirection: disposed.',
      ),
      StackTrace.fromString('voice-stack'),
      source: 'voice-call-media',
      fatal: false,
    );

    final result = await service.exportDiagnostics();

    expect(result.saved, isTrue);
    final decoded =
        jsonDecode(await File(exportPath).readAsString())
            as Map<String, dynamic>;
    final encoded = jsonEncode(decoded);
    expect(encoded, contains('RTCRtpTransceiver::setDirection'));
    expect(encoded, contains('Video could not connect. Try again.'));
  });

  test(
    'diagnostics export includes call summaries and cost counters',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'rain-crash-diagnostics-call-summary-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final exportPath = _join(temp.path, 'call-summary-diagnostics.json');

      final service = CrashDiagnosticsService(
        directoryProvider: () async => temp,
        clock: () => DateTime.utc(2026, 5, 22, 1, 2, 3),
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

      await service.initialize();
      service.recordEventSync(
        category: 'call',
        name: 'firebase_room_update',
        context: const <String, Object?>{
          'callId': 'call-1',
          'peerId': 'bob',
          'mediaMode': 'video',
          'status': 'negotiating',
        },
      );
      service.recordEventSync(
        category: 'call',
        name: 'ice_candidate_batch_flushed',
        context: const <String, Object?>{
          'callId': 'call-1',
          'peerId': 'bob',
          'mediaMode': 'video',
          'writtenCount': 2,
        },
      );
      service.recordEventSync(
        category: 'call',
        name: 'firebase_frame_received',
        context: const <String, Object?>{
          'callId': 'call-1',
          'peerId': 'bob',
          'mediaMode': 'video',
          'frameType': 'candidate',
          'from': 'bob',
          'to': 'alice',
        },
      );
      service.recordEventSync(
        category: 'call',
        name: 'voice_terminal_write_durable',
        context: const <String, Object?>{
          'callId': 'call-1',
          'peerId': 'bob',
          'mediaMode': 'video',
        },
      );
      service.recordErrorSync(
        const VoiceCallDiagnostics(
          callId: 'call-1',
          sessionEpoch: 42,
          peerId: 'bob',
          role: 'caller',
          mediaMode: 'video',
          caller: 'alice',
          callee: 'bob',
          failureCode: 'iceTimeout',
          userMessage: 'Call media could not connect. Try again.',
          sanitizedUiError: 'Call media could not connect. Try again.',
          nativeError: 'ICE timeout.',
          mediaFailureReason: 'iceTimeout',
          failureTaxonomy: 'ice_failed',
        ),
        StackTrace.fromString('voice-stack'),
        source: 'voice-call-media',
        fatal: false,
      );

      final result = await service.exportDiagnostics();

      expect(result.saved, isTrue);
      final decoded =
          jsonDecode(await File(exportPath).readAsString())
              as Map<String, dynamic>;
      final summaries = decoded['callSummaries'] as List<dynamic>;
      final summary = summaries.single as Map<String, dynamic>;
      final costCounters =
          decoded['firebaseCostCounters'] as Map<String, dynamic>;
      final taxonomy = decoded['failureTaxonomy'] as Map<String, dynamic>;

      expect(summary['callId'], 'call-1');
      expect(summary['peerId'], 'bob');
      expect(summary['mediaMode'], 'video');
      expect(summary['caller'], 'alice');
      expect(summary['callee'], 'bob');
      expect(summary['roomStatusTimeline'], const <String>['negotiating']);
      expect(summary['iceCandidateWriteCount'], 2);
      expect(summary['iceCandidateReadCount'], 1);
      expect(summary['terminalWriteOutcome'], 'durable');
      expect(summary['mediaFailureReason'], 'iceTimeout');
      expect(summary['failureTaxonomy'], 'ice_failed');
      expect(costCounters['signalingReads'], 2);
      expect(costCounters['signalingWrites'], greaterThanOrEqualTo(3));
      expect(costCounters['iceCandidateWrites'], 2);
      expect(taxonomy['ice_failed'], 1);
    },
  );

  test('export can be canceled without writing a file', () async {
    final temp = await Directory.systemTemp.createTemp(
      'rain-crash-diagnostics-cancel-test-',
    );
    addTearDown(() => temp.delete(recursive: true));

    final service = CrashDiagnosticsService(
      directoryProvider: () async => temp,
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
            return null;
          },
    );

    await service.initialize();
    final result = await service.exportDiagnostics();

    expect(result.saved, isFalse);
    expect(result.path, isNull);
  });
}

String _join(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}
