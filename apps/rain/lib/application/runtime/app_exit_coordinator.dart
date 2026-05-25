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

final class AppExitCoordinator {
  AppExitCoordinator({this.timeout = const Duration(seconds: 8)});

  static final AppExitCoordinator instance = AppExitCoordinator();

  final Duration timeout;
  final Set<AppExitHandler> _handlers = <AppExitHandler>{};
  Future<void>? _shutdownFuture;

  AppExitRegistration register(AppExitHandler handler) {
    _handlers.add(handler);
    return AppExitRegistration(() {
      _handlers.remove(handler);
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

  Future<void> _runShutdown(AppExitReason reason) async {
    final handlers = List<AppExitHandler>.of(_handlers);
    if (handlers.isEmpty) {
      return;
    }

    final waitForHandlers = Future.wait<void>(<Future<void>>[
      for (final handler in handlers)
        Future<void>(() => handler(reason)).catchError((_) {}),
    ]).then<void>((_) {});
    await waitForHandlers.timeout(timeout, onTimeout: () {});
  }
}
