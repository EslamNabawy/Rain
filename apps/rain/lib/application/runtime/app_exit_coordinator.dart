/// # app_exit_coordinator.dart
///
/// [AppExitCoordinator] manages ordered shutdown handlers for Rain's window
/// close / lifecycle detach / logout flows. Critical handlers (e.g. signaling
/// teardown) run synchronously and block close; best-effort handlers run in
/// the background after the window is destroyed.
///
/// **Key types:** [AppExitCoordinator], [AppExitReason], [AppExitPriority], [AppExitRegistration]
///
/// **Depends on:** application runtime lifecycle
library;

import 'dart:async';

enum AppExitReason { windowClose, lifecycleDetached, providerDispose, logout }

typedef AppExitHandler = Future<void> Function(AppExitReason reason);

final class AppExitRegistration {
  AppExitRegistration(this._unregister);

  final void Function() _unregister;
  bool _active = true;

  void unregister() {
    if (!_active) {
      return;
    }
    _active = false;
    _unregister();
  }
}

/// Priority for exit handlers.
///
/// [critical] handlers run first and block window close until complete
/// (up to the caller's budget).
///
/// [bestEffort] handlers run in the background after window destruction.
enum AppExitPriority { critical, bestEffort }

final class _PrioritizedHandler {
  const _PrioritizedHandler(this.handler, this.priority);

  final AppExitHandler handler;
  final AppExitPriority priority;
}

final class AppExitCoordinator {
  AppExitCoordinator({
    this.timeout = const Duration(seconds: 8),
    this.criticalTimeout = const Duration(seconds: 3),
  });

  static final AppExitCoordinator instance = AppExitCoordinator();

  /// Overall timeout for all handlers (used by best-effort phase).
  final Duration timeout;

  /// Timeout for critical handlers only.
  final Duration criticalTimeout;

  final List<_PrioritizedHandler> _handlers = <_PrioritizedHandler>[];
  Future<void>? _shutdownFuture;

  AppExitRegistration register(
    AppExitHandler handler, {
    AppExitPriority priority = AppExitPriority.bestEffort,
  }) {
    final entry = _PrioritizedHandler(handler, priority);
    _handlers.add(entry);
    return AppExitRegistration(() {
      _handlers.remove(entry);
    });
  }

  Future<void> shutdown(AppExitReason reason) {
    final existing = _shutdownFuture;
    if (existing != null) {
      return existing;
    }
    final future = _runShutdown(reason);
    _shutdownFuture = future;
    return future;
  }

  /// Runs only critical handlers with the critical timeout.
  Future<void> shutdownCritical(AppExitReason reason) async {
    final critical = _handlers
        .where((h) => h.priority == AppExitPriority.critical)
        .map((h) => h.handler)
        .toList();
    if (critical.isEmpty) {
      return;
    }
    final futures = critical.map(
      (h) => Future<void>(() => h(reason)).catchError((_) {}),
    );
    try {
      await Future.wait(futures).timeout(criticalTimeout);
    } on TimeoutException {
      // Best-effort: critical phase exceeded budget, proceed anyway.
    }
  }

  Future<void> _runShutdown(AppExitReason reason) async {
    final handlers = _handlers.map((h) => h.handler).toList();
    if (handlers.isEmpty) {
      return;
    }
    final futures = handlers.map(
      (h) => Future<void>(() => h(reason)).catchError((_) {}),
    );
    try {
      await Future.wait(futures).timeout(timeout);
    } on TimeoutException {
      // Best-effort: shutdown exceeded budget, proceed anyway.
    }
  }
}
