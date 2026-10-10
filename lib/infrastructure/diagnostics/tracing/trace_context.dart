import 'dart:async';
import 'dart:math';

/// TraceContext: lightweight OpenTelemetry-lite.
/// One traceId per user flow (register, call, heartbeat cycle).
/// Propagated via Zone and Riverpod override. No external dep.
class TraceContext {
  TraceContext._(this.traceId, this.spanId, this.parentSpanId);

  final String traceId;
  final String spanId;
  final String? parentSpanId;

  static const _traceKey = #traceContext;

  static TraceContext create({String? parentTraceId}) {
    final traceId = parentTraceId ?? 'tr_${_rand(8)}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    return TraceContext._(traceId, 'sp_${_rand(6)}', null);
  }

  TraceContext childSpan() => TraceContext._(traceId, 'sp_${_rand(6)}', spanId);

  static TraceContext? get current => Zone.current[_traceKey] as TraceContext?;

  static T run<T>(TraceContext ctx, T Function() fn) {
    return runZoned(fn, zoneValues: {_traceKey: ctx});
  }

  static Future<T> runAsync<T>(TraceContext ctx, Future<T> Function() fn) {
    return runZoned(fn, zoneValues: {_traceKey: ctx});
  }

  static String _rand(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(len, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Map<String, Object?> toContext() => {
        'traceId': traceId,
        'spanId': spanId,
        if (parentSpanId != null) 'parentSpanId': parentSpanId,
      };
}

/// Helper to run any async op with trace, logging start/complete automatically.
/// Usage: await traced('createOutgoingCall', kind: 'voice_write', traceId: ctx.traceId, action: () => adapter.create(...))
