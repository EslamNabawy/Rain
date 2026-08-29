import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain/infrastructure/services/rain_debug_log_service.dart';

/// Drops noisy provider updates where value equality hasn't changed.
/// Wraps existing RainDebugProviderObserver logic with distinct + debounce.

final class ThrottledProviderObserver extends ProviderObserver {
  ThrottledProviderObserver(this.log);
  final RainDebugLogService log;

  final Map<String, Object?> _lastValueHash = {};
  final Map<String, DateTime> _lastEmit = {};

  static const _debounce = Duration(milliseconds: 200);
  static const _noisyProviders = {
    'Provider<ConnectionDiagnostics>',
    'NotifierProvider<PeerConnectivityController, Map<String, PeerConnectivitySnapshot>>',
  };

  @override
  void didUpdateProvider(ProviderObserverContext context, Object? previousValue, Object? newValue) {
    final key = context.provider.name ?? context.provider.runtimeType.toString();
    final hash = _hashValue(newValue);

    // Distinct check: if hash same as last, skip
    if (_lastValueHash[key] == hash) return;

    // Debounce noisy providers
    if (_noisyProviders.contains(key)) {
      final last = _lastEmit[key];
      if (last != null && DateTime.now().difference(last) < _debounce) return;
      _lastEmit[key] = DateTime.now();
    }

    _lastValueHash[key] = hash;

    // Delegate to original logging (copy of RainDebugProviderObserver._record)
    if (!log.enabled) return;
    log.event(
      category: 'ui_state',
      name: 'provider_updated',
      severity: RainDebugSeverity.debug,
      context: {
        'provider': key,
        'hash': hash,
        // only include diff-relevant fields, not full type churn
      },
    );
  }

  Object? _hashValue(Object? value) {
    if (value == null) return null;
    // Use structural hash: for AsyncData/ConnectionDiagnostics rely on == if implemented
    // Fallback to runtimeType + toString length
    try {
      return value.hashCode;
    } catch (_) {
      return value.runtimeType.toString();
    }
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    // keep as-is
    if (!log.enabled) return;
    log.event(
      category: 'ui_state',
      name: 'provider_added',
      severity: RainDebugSeverity.debug,
      context: {'provider': context.provider.name ?? context.provider.runtimeType.toString()},
    );
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _lastValueHash.remove(context.provider.name ?? context.provider.runtimeType.toString());
    _lastEmit.remove(context.provider.name ?? context.provider.runtimeType.toString());
    if (!log.enabled) return;
    log.event(
      category: 'ui_state',
      name: 'provider_disposed',
      severity: RainDebugSeverity.debug,
      context: {'provider': context.provider.name ?? context.provider.runtimeType.toString()},
    );
  }
}
