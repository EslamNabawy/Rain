import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crash_diagnostics_service.dart';
import 'diagnostics_sanitizer.dart';

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
      context: context,
    );
    _diagnostics.recordEventSync(
      category: 'debug_error',
      name: source.trim().isEmpty ? 'unknown_error' : source.trim(),
      severity: fatal
          ? RainDebugSeverity.fatal.name
          : RainDebugSeverity.error.name,
      message: DiagnosticsSanitizer.sanitizeString(
        error.toString(),
        key: 'error',
      ),
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
    return DiagnosticsSanitizer.sanitizeMap(context);
  }
}

/// Module-level logging sink for code paths that do not have Riverpod/provider
/// access (e.g. low-level services, error handlers). Mirrors the
/// `RainDebugLogService` contract but without requiring dependency injection:
/// callers use [RainDebugLog.event] / [RainDebugLog.error], and bootstrap wires
/// the real [RainDebugLogService] via [service] (defaults to a noop).
///
/// TASK-018: replaces raw `debugPrint(` in `lib/` so logging is centralized and
/// sanitized. CI fails if raw `debugPrint(` remains in `lib/`.
final class RainDebugLog {
  RainDebugLog._();

  /// Active sink. Set by bootstrap (see `main.dart`). Null/never-set → noop.
  static RainDebugLogService? service;

  static void event({
    required String category,
    required String name,
    RainDebugSeverity severity = RainDebugSeverity.info,
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    service?.event(
      category: category,
      name: name,
      severity: severity,
      message: message,
      context: context,
    );
  }

  static void error(
    Object error,
    StackTrace? stackTrace, {
    required String source,
    bool fatal = false,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    service?.error(
      error,
      stackTrace,
      source: source,
      fatal: fatal,
      context: context,
    );
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
