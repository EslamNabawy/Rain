import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crash_diagnostics_service.dart';

enum RainDebugSeverity { debug, info, warning, error, fatal }

abstract interface class RainDebugLogService {
  bool get enabled;

  void event({
    required String category,
    required String name,
    RainDebugSeverity severity = RainDebugSeverity.info,
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  });

  void error(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  });

  Future<void> flush();
}

final class NoopRainDebugLogService implements RainDebugLogService {
  const NoopRainDebugLogService();

  @override
  bool get enabled => false;

  @override
  void event({
    required String category,
    required String name,
    RainDebugSeverity severity = RainDebugSeverity.info,
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  }) {}

  @override
  void error(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) {}

  @override
  Future<void> flush() async {}
}

final class CrashDiagnosticsDebugLogService implements RainDebugLogService {
  const CrashDiagnosticsDebugLogService({
    required CrashDiagnosticsService diagnostics,
    required this.enabled,
  }) : _diagnostics = diagnostics;

  final CrashDiagnosticsService _diagnostics;

  @override
  final bool enabled;

  @override
  void event({
    required String category,
    required String name,
    RainDebugSeverity severity = RainDebugSeverity.info,
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    if (!enabled && severity != RainDebugSeverity.fatal) {
      return;
    }
    _diagnostics.recordEventSync(
      category: category,
      name: name,
      severity: severity.name,
      message: message,
      context: sanitizeContext(context),
    );
  }

  @override
  void error(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    if (!enabled && !fatal) {
      return;
    }
    _diagnostics.recordErrorSync(
      error,
      stackTrace,
      source: source,
      fatal: fatal,
    );
    _diagnostics.recordEventSync(
      category: 'debug_error',
      name: source.trim().isEmpty ? 'unknown_error' : source.trim(),
      severity: fatal
          ? RainDebugSeverity.fatal.name
          : RainDebugSeverity.error.name,
      message: error.toString(),
      context: sanitizeContext(<String, Object?>{
        'source': source,
        'fatal': fatal,
        ...context,
      }),
    );
  }

  @override
  Future<void> flush() => _diagnostics.flushEvents();

  static Map<String, Object?> sanitizeContext(Map<String, Object?> context) {
    return _sanitizeMap(context, depth: 0);
  }

  static Map<String, Object?> _sanitizeMap(
    Map<String, Object?> value, {
    required int depth,
  }) {
    if (depth >= 4) {
      return const <String, Object?>{};
    }
    final sanitized = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      if (_isSensitiveKey(key)) {
        sanitized[key] = '[redacted]';
        continue;
      }
      sanitized[key] = _sanitizeValue(entry.value, depth: depth + 1);
    }
    return sanitized;
  }

  static Object? _sanitizeValue(Object? value, {required int depth}) {
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Enum) {
      return value.name;
    }
    if (value is String) {
      return _trim(value);
    }
    if (value is Iterable) {
      if (depth >= 4) {
        return const <Object?>[];
      }
      return value
          .take(20)
          .map((Object? item) => _sanitizeValue(item, depth: depth + 1))
          .toList(growable: false);
    }
    if (value is Map) {
      if (depth >= 4) {
        return const <String, Object?>{};
      }
      return _sanitizeMap(
        value.map<String, Object?>(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
        depth: depth,
      );
    }
    return _trim(value.toString());
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.trim().toLowerCase();
    if (normalized.contains('password') ||
        normalized.contains('token') ||
        normalized.contains('credential') ||
        normalized.contains('secret')) {
      return true;
    }
    return normalized == 'sdp' ||
        normalized == 'candidate' ||
        normalized == 'ciphertext' ||
        normalized == 'nonce' ||
        normalized == 'mac' ||
        normalized == 'messagetext' ||
        normalized == 'filebytes';
  }

  static String _trim(String value) {
    const max = 512;
    if (value.length <= max) {
      return value;
    }
    return '${value.substring(0, max)}...';
  }
}

final class RainDebugProviderObserver extends ProviderObserver {
  RainDebugProviderObserver(this._log);

  final RainDebugLogService _log;

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    _record(name: 'provider_added', context: context, value: value);
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    _record(
      name: 'provider_updated',
      context: context,
      previousValue: previousValue,
      value: newValue,
    );
  }

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final eventContext = _providerContext(context);
    _log.error(
      error,
      stackTrace,
      source: 'riverpod-provider',
      fatal: false,
      context: eventContext,
    );
    _log.event(
      category: 'ui_state',
      name: 'provider_failed',
      severity: RainDebugSeverity.error,
      message: error.toString(),
      context: eventContext,
    );
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _record(name: 'provider_disposed', context: context);
  }

  void _record({
    required String name,
    required ProviderObserverContext context,
    Object? previousValue,
    Object? value,
  }) {
    if (!_log.enabled) {
      return;
    }
    _log.event(
      category: 'ui_state',
      name: name,
      severity: RainDebugSeverity.debug,
      context: <String, Object?>{
        ..._providerContext(context),
        if (previousValue != null) 'previous': _valueSummary(previousValue),
        if (value != null) 'next': _valueSummary(value),
      },
    );
  }

  Map<String, Object?> _providerContext(ProviderObserverContext context) {
    final provider = context.provider;
    return <String, Object?>{
      'provider': provider.name ?? provider.runtimeType.toString(),
      'providerType': provider.runtimeType.toString(),
      if (context.mutation != null) 'mutation': context.mutation.toString(),
    };
  }

  Map<String, Object?> _valueSummary(Object? value) {
    if (value == null) {
      return const <String, Object?>{'type': 'null'};
    }
    if (value is AsyncValue) {
      return <String, Object?>{
        'type': value.runtimeType.toString(),
        'isLoading': value.isLoading,
        'hasValue': value.hasValue,
        'hasError': value.hasError,
        if (value.hasError) 'errorType': value.error?.runtimeType.toString(),
        if (value.hasError) 'error': value.error?.toString(),
        if (value.hasValue) 'valueType': _asyncValueType(value),
        if (value.hasValue) ..._knownIds(value.asData?.value),
      };
    }
    return <String, Object?>{
      'type': value.runtimeType.toString(),
      ..._knownIds(value),
    };
  }

  String? _asyncValueType(AsyncValue value) {
    final data = value.asData?.value;
    return data?.runtimeType.toString();
  }

  Map<String, Object?> _knownIds(Object? value) {
    if (value == null) {
      return const <String, Object?>{};
    }
    final result = <String, Object?>{};
    for (final field in const <String>[
      'peerId',
      'callId',
      'requestId',
      'transferId',
      'username',
      'phase',
      'state',
    ]) {
      final read = _tryReadField(value, field);
      if (read != null) {
        result[field] = read;
      }
    }
    return result;
  }

  Object? _tryReadField(Object value, String field) {
    try {
      final dynamic dynamicValue = value;
      return switch (field) {
        'peerId' => dynamicValue.peerId,
        'callId' => dynamicValue.callId,
        'requestId' => dynamicValue.requestId,
        'transferId' => dynamicValue.transferId,
        'username' => dynamicValue.username,
        'phase' => dynamicValue.phase,
        'state' => dynamicValue.state,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}
