import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(decoded['events'] as List<dynamic>, isNotEmpty);
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
