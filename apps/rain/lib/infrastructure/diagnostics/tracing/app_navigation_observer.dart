import 'package:flutter/widgets.dart';
import 'package:rain/infrastructure/services/rain_debug_log_service.dart';

import 'trace_context.dart';

/// Logs every navigation push/pop/replace. Attach to MaterialApp.navigatorObservers.
class AppNavigationObserver extends NavigatorObserver {
  AppNavigationObserver(this.log);
  final RainDebugLogService log;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('push', previousRoute, route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log('pop', route, previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _log('replace', oldRoute, newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  void _log(String action, Route<dynamic>? from, Route<dynamic>? to) {
    final trace = TraceContext.current;
    log.event(
      category: 'interaction',
      name: 'navigation',
      severity: RainDebugSeverity.debug,
      context: {
        'action': action,
        'from': from?.settings.name ?? 'null',
        'to': to?.settings.name ?? 'null',
        if (trace != null) ...trace.toContext(),
      },
    );
  }
}
