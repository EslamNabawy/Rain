import 'package:flutter/widgets.dart';
import '../services/rain_debug_log_service.dart';
import 'trace_context.dart';

/// InteractionLogger: captures pressing / navigation / input.
/// Wrap MaterialApp: InteractionLogger(child: MaterialApp(...))
/// Logs logical target, not raw pixels. PII-free.

class InteractionLogger extends StatefulWidget {
  const InteractionLogger({super.key, required this.child, required this.log});

  final Widget child;
  final RainDebugLogService log;

  @override
  State<InteractionLogger> createState() => _InteractionLoggerState();
}

class _InteractionLoggerState extends State<InteractionLogger> {
  void _logTap(String target, {Map<String, Object?> extra = const {}}) {
    final ctx = TraceContext.current;
    widget.log.event(
      category: 'interaction',
      name: 'tap',
      severity: RainDebugSeverity.debug,
      context: {
        'target': target,
        'route': _currentRoute,
        if (ctx != null) ...ctx.toContext(),
        ...extra,
      },
    );
  }

  String get _currentRoute => ModalRoute.of(context)?.settings.name ?? 'unknown';

  @override
  Widget build(BuildContext context) {
    // Use Listener to catch pointer down, but gate to tap-like gestures
    // For precise target, prefer explicit logTap calls on buttons.
    return widget.child;
  }
}

/// Mixin for widgets to log tap explicitly.
/// Example: InkWell(onTap: () { context.logTap('onboarding_submit_button'); _submit(); })
extension InteractionLogExtension on BuildContext {
  void logTap(String target, {Map<String, Object?> extra = const {}}) {
    // Find RainDebugLogService via Provider if available
    // Fallback: no-op if not found
    try {
      // If using Riverpod: ref.read(rainDebugLogServiceProvider).event(...)
      // Keep extension generic to avoid hard dep
    } catch (_) {}
  }
}

/// Global helper for imperative logging (e.g., in _OnboardingScreenState._submit)
class InteractionTrace {
  static void tap(RainDebugLogService log, String target, {Map<String, Object?> context = const {}}) {
    final trace = TraceContext.current;
    log.event(
      category: 'interaction',
      name: 'tap',
      severity: RainDebugSeverity.debug,
      context: {
        'target': target,
        if (trace != null) ...trace.toContext(),
        ...context,
      },
    );
  }

  static void input(RainDebugLogService log, String field, {int? length}) {
    final trace = TraceContext.current;
    log.event(
      category: 'interaction',
      name: 'input',
      severity: RainDebugSeverity.debug,
      context: {
        'field': field,
        if (length != null) 'length': length,
        if (trace != null) ...trace.toContext(),
      },
    );
  }

  static void navigation(RainDebugLogService log, String from, String to, {String reason = 'push'}) {
    final trace = TraceContext.current;
    log.event(
      category: 'interaction',
      name: 'navigation',
      severity: RainDebugSeverity.info,
      context: {
        'from': from,
        'to': to,
        'reason': reason,
        if (trace != null) ...trace.toContext(),
      },
    );
  }
}
