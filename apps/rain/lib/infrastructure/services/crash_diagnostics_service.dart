import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

typedef CrashDiagnosticsDirectoryProvider = Future<Directory> Function();
typedef CrashDiagnosticsClock = DateTime Function();
typedef CrashDiagnosticsAppInfoProvider =
    Future<CrashDiagnosticsAppInfo> Function();
typedef CrashDiagnosticsSaveFile =
    Future<String?> Function({
      String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow,
    });

class CrashDiagnosticsAppInfo {
  const CrashDiagnosticsAppInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  const CrashDiagnosticsAppInfo.unknown()
    : appName = 'Rain',
      packageName = 'unknown',
      version = 'unknown',
      buildNumber = 'unknown';

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  Map<String, Object> toJson() => <String, Object>{
    'appName': appName,
    'packageName': packageName,
    'version': version,
    'buildNumber': buildNumber,
  };
}

class CrashDiagnosticsRecord {
  const CrashDiagnosticsRecord({
    required this.recordedAt,
    required this.source,
    required this.fatal,
    required this.error,
    required this.stackTrace,
    required this.appInfo,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.dartVersion,
    this.flutterLibrary,
    this.flutterContext,
  });

  factory CrashDiagnosticsRecord.fromJson(Map<String, Object?> json) {
    final appJson = CrashDiagnosticsService._stringMap(json['app']);
    return CrashDiagnosticsRecord(
      recordedAt:
          DateTime.tryParse((json['recordedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      source: (json['source'] ?? 'unknown').toString(),
      fatal: json['fatal'] == true,
      error: (json['error'] ?? '').toString(),
      stackTrace: (json['stackTrace'] ?? '').toString(),
      appInfo: CrashDiagnosticsAppInfo(
        appName: (appJson['appName'] ?? 'Rain').toString(),
        packageName: (appJson['packageName'] ?? 'unknown').toString(),
        version: (appJson['version'] ?? 'unknown').toString(),
        buildNumber: (appJson['buildNumber'] ?? 'unknown').toString(),
      ),
      operatingSystem: (json['operatingSystem'] ?? 'unknown').toString(),
      operatingSystemVersion: (json['operatingSystemVersion'] ?? 'unknown')
          .toString(),
      dartVersion: (json['dartVersion'] ?? 'unknown').toString(),
      flutterLibrary: json['flutterLibrary']?.toString(),
      flutterContext: json['flutterContext']?.toString(),
    );
  }

  final DateTime recordedAt;
  final String source;
  final bool fatal;
  final String error;
  final String stackTrace;
  final CrashDiagnosticsAppInfo appInfo;
  final String operatingSystem;
  final String operatingSystemVersion;
  final String dartVersion;
  final String? flutterLibrary;
  final String? flutterContext;

  Map<String, Object?> toJson() => <String, Object?>{
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'source': source,
    'fatal': fatal,
    'error': error,
    'stackTrace': stackTrace,
    'app': appInfo.toJson(),
    'operatingSystem': operatingSystem,
    'operatingSystemVersion': operatingSystemVersion,
    'dartVersion': dartVersion,
    if (flutterLibrary != null) 'flutterLibrary': flutterLibrary,
    if (flutterContext != null) 'flutterContext': flutterContext,
  };
}

class CrashDiagnosticsExportResult {
  const CrashDiagnosticsExportResult._({required this.saved, this.path});

  const CrashDiagnosticsExportResult.saved(String path)
    : this._(saved: true, path: path);
  const CrashDiagnosticsExportResult.canceled()
    : this._(saved: false, path: null);

  final bool saved;
  final String? path;
}

class CrashDiagnosticsService {
  CrashDiagnosticsService({
    CrashDiagnosticsDirectoryProvider? directoryProvider,
    CrashDiagnosticsAppInfoProvider? appInfoProvider,
    CrashDiagnosticsClock? clock,
    CrashDiagnosticsSaveFile? saveFile,
  }) : _directoryProvider = directoryProvider ?? _defaultDirectoryProvider,
       _appInfoProvider = appInfoProvider ?? _defaultAppInfoProvider,
       _clock = clock ?? DateTime.now,
       _saveFile = saveFile ?? FilePicker.saveFile;

  static final CrashDiagnosticsService instance = CrashDiagnosticsService();
  static const int _maxEventLogBytes = 1024 * 1024;
  static const int _maxEventLogLines = 1000;
  static const int _maxEventContextStringLength = 512;

  final CrashDiagnosticsDirectoryProvider _directoryProvider;
  final CrashDiagnosticsAppInfoProvider _appInfoProvider;
  final CrashDiagnosticsClock _clock;
  final CrashDiagnosticsSaveFile _saveFile;

  Directory? _directory;
  CrashDiagnosticsAppInfo _appInfo = const CrashDiagnosticsAppInfo.unknown();
  Future<void>? _initializeFuture;

  Future<void> initialize() {
    return _initializeFuture ??= _initialize();
  }

  void installGlobalHandlers() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      recordFlutterError(details, fatal: false);
    };
    ui.PlatformDispatcher.instance.onError =
        (Object error, StackTrace stackTrace) {
          recordErrorSync(
            error,
            stackTrace,
            source: 'platform-dispatcher',
            fatal: true,
          );
          return true;
        };
  }

  void recordFlutterError(FlutterErrorDetails details, {required bool fatal}) {
    recordErrorSync(
      details.exception,
      details.stack,
      source: 'flutter',
      fatal: fatal,
      flutterLibrary: details.library,
      flutterContext: details.context?.toDescription(),
    );
  }

  void recordErrorSync(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    required bool fatal,
    String? flutterLibrary,
    String? flutterContext,
  }) {
    final directory = _directory;
    if (directory == null) {
      debugPrint('Rain diagnostics not initialized: $error');
      return;
    }

    final record = CrashDiagnosticsRecord(
      recordedAt: _clock(),
      source: source,
      fatal: fatal,
      error: error.toString(),
      stackTrace: (stackTrace ?? StackTrace.current).toString(),
      appInfo: _appInfo,
      operatingSystem: Platform.operatingSystem,
      operatingSystemVersion: Platform.operatingSystemVersion,
      dartVersion: Platform.version,
      flutterLibrary: flutterLibrary,
      flutterContext: flutterContext,
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(record.toJson());

    try {
      _lastCrashFile(directory).writeAsStringSync(encoded, flush: true);
      _appendEventRecordSync(directory, <String, Object?>{
        'kind': 'error',
        'record': record.toJson(),
      });
    } on FileSystemException catch (fileError) {
      debugPrint('Rain diagnostics write failed: $fileError');
    }
  }

  void recordEventSync({
    required String category,
    required String name,
    String severity = 'info',
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    final directory = _directory;
    if (directory == null) {
      return;
    }
    final normalizedCategory = category.trim();
    final normalizedName = name.trim();
    if (normalizedCategory.isEmpty || normalizedName.isEmpty) {
      return;
    }

    try {
      _appendEventRecordSync(directory, <String, Object?>{
        'kind': 'app_event',
        'recordedAt': _clock().toUtc().toIso8601String(),
        'category': normalizedCategory,
        'name': normalizedName,
        'severity': severity.trim().isEmpty ? 'info' : severity.trim(),
        if (message != null && message.trim().isNotEmpty)
          'message': _trimDiagnosticString(message),
        if (context.isNotEmpty)
          'context': _sanitizeDiagnosticMap(context, depth: 0),
      });
    } on FileSystemException catch (fileError) {
      debugPrint('Rain diagnostics event write failed: $fileError');
    }
  }

  Future<CrashDiagnosticsRecord?> loadLastCrash() async {
    await initialize();
    final directory = _requireDirectory();
    final file = _lastCrashFile(directory);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      final recordJson = _stringMap(decoded);
      if (recordJson.isNotEmpty) {
        return CrashDiagnosticsRecord.fromJson(recordJson);
      }
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
    return null;
  }

  Future<CrashDiagnosticsExportResult> exportDiagnostics() async {
    await initialize();
    final directory = _requireDirectory();
    final exportedAt = _clock().toUtc();
    final payload = <String, Object?>{
      'exportedAt': exportedAt.toIso8601String(),
      'app': _appInfo.toJson(),
      'platform': <String, Object>{
        'operatingSystem': Platform.operatingSystem,
        'operatingSystemVersion': Platform.operatingSystemVersion,
        'dartVersion': Platform.version,
      },
      'lastCrash': (await loadLastCrash())?.toJson(),
      'events': await _readRecentEvents(directory, limit: 200),
    };
    final content = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = Uint8List.fromList(utf8.encode(content));
    final fileName = _diagnosticsFileName(exportedAt);

    final destinationPath = await _saveFile(
      dialogTitle: 'Export Rain diagnostics',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      bytes: bytes,
      lockParentWindow: true,
    );
    if (destinationPath == null || destinationPath.isEmpty) {
      return const CrashDiagnosticsExportResult.canceled();
    }

    final destination = File(destinationPath);
    try {
      if (!await destination.exists() || await destination.length() == 0) {
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(bytes, flush: true);
      }
    } on FileSystemException {
      throw StateError(
        'Could not export diagnostics. Choose another location.',
      );
    }
    return CrashDiagnosticsExportResult.saved(destination.path);
  }

  Future<void> _initialize() async {
    final base = await _directoryProvider();
    final directory = Directory(_join(base.path, 'rain_diagnostics'));
    await directory.create(recursive: true);
    _directory = directory;
    try {
      _appInfo = await _appInfoProvider();
    } catch (_) {
      _appInfo = const CrashDiagnosticsAppInfo.unknown();
    }
  }

  Directory _requireDirectory() {
    final directory = _directory;
    if (directory == null) {
      throw StateError('Crash diagnostics are not initialized.');
    }
    return directory;
  }

  Future<List<Map<String, Object?>>> _readRecentEvents(
    Directory directory, {
    required int limit,
  }) async {
    final file = _eventLogFile(directory);
    if (!await file.exists()) {
      return const <Map<String, Object?>>[];
    }
    try {
      final lines = await file.readAsLines();
      final start = lines.length > limit ? lines.length - limit : 0;
      return lines
          .skip(start)
          .map((line) {
            try {
              final decoded = _stringMap(jsonDecode(line));
              return decoded.isEmpty ? null : decoded;
            } on FormatException {
              return null;
            }
          })
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
    } on FileSystemException {
      return const <Map<String, Object?>>[];
    }
  }

  void _appendEventRecordSync(
    Directory directory,
    Map<String, Object?> record,
  ) {
    final file = _eventLogFile(directory);
    file.writeAsStringSync(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
    _trimEventLogSync(file);
  }

  void _trimEventLogSync(File file) {
    if (!file.existsSync() || file.lengthSync() <= _maxEventLogBytes) {
      return;
    }
    final lines = file.readAsLinesSync();
    final start = lines.length > _maxEventLogLines
        ? lines.length - _maxEventLogLines
        : 0;
    final trimmed = lines.skip(start).join('\n');
    file.writeAsStringSync(trimmed.isEmpty ? '' : '$trimmed\n', flush: true);
  }

  static Future<Directory> _defaultDirectoryProvider() {
    return getApplicationSupportDirectory();
  }

  static Future<CrashDiagnosticsAppInfo> _defaultAppInfoProvider() async {
    final info = await PackageInfo.fromPlatform();
    return CrashDiagnosticsAppInfo(
      appName: info.appName,
      packageName: info.packageName,
      version: info.version,
      buildNumber: info.buildNumber,
    );
  }

  static File _lastCrashFile(Directory directory) {
    return File(_join(directory.path, 'last_crash.json'));
  }

  static File _eventLogFile(Directory directory) {
    return File(_join(directory.path, 'events.jsonl'));
  }

  static String _diagnosticsFileName(DateTime exportedAt) {
    final safeStamp = exportedAt
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '-');
    return 'rain-diagnostics-$safeStamp.json';
  }

  static String _join(String parent, String child) {
    if (parent.endsWith(Platform.pathSeparator)) {
      return '$parent$child';
    }
    return '$parent${Platform.pathSeparator}$child';
  }

  static Map<String, Object?> _stringMap(Object? value) {
    if (value is! Map) {
      return const <String, Object?>{};
    }
    return value.map<String, Object?>(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  static Map<String, Object?> _sanitizeDiagnosticMap(
    Map<String, Object?> value, {
    required int depth,
  }) {
    if (depth >= 3) {
      return const <String, Object?>{};
    }
    final sanitized = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      sanitized[key] = _sanitizeDiagnosticValue(entry.value, depth: depth + 1);
    }
    return sanitized;
  }

  static Object? _sanitizeDiagnosticValue(Object? value, {required int depth}) {
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is String) {
      return _trimDiagnosticString(value);
    }
    if (value is Enum) {
      return value.name;
    }
    if (value is Iterable) {
      if (depth >= 3) {
        return const <Object?>[];
      }
      return value
          .take(20)
          .map((Object? item) {
            return _sanitizeDiagnosticValue(item, depth: depth + 1);
          })
          .toList(growable: false);
    }
    if (value is Map) {
      if (depth >= 3) {
        return const <String, Object?>{};
      }
      return _sanitizeDiagnosticMap(
        value.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
        depth: depth,
      );
    }
    return _trimDiagnosticString(value.toString());
  }

  static String _trimDiagnosticString(String value) {
    if (value.length <= _maxEventContextStringLength) {
      return value;
    }
    return '${value.substring(0, _maxEventContextStringLength)}...';
  }
}
