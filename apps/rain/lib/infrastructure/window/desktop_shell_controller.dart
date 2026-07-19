import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'package:rain/application/runtime/app_exit_coordinator.dart';
import 'package:rain/infrastructure/services/rain_debug_log_service.dart';

class DesktopShellController with WindowListener {
  static const Duration _closeStepTimeout = Duration(seconds: 2);
  static const Duration _criticalCloseBudget = Duration(milliseconds: 1500);

  bool _initialized = false;
  bool _closing = false;

  Future<void> initializeBeforeRunApp() async {
    if (_initialized || !_isDesktop) {
      return;
    }
    _initialized = true;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    unawaited(
      windowManager.waitUntilReadyToShow(
        const WindowOptions(backgroundColor: Color(0xFF061017), title: 'Rain'),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
    );
  }

  @override
  Future<void> onWindowClose() async {
    if (_closing) {
      return;
    }
    _closing = true;

    final totalStopwatch = Stopwatch()..start();

    try {
      // Critical phase: presence offline + terminal state publish.
      // These are the minimum writes needed to leave the app in a clean state.
      await _runCriticalClosePhase(totalStopwatch);
    } finally {
      // Destroy window after critical phase or budget, whichever comes first.
      final elapsed = totalStopwatch.elapsed;
      if (elapsed < _criticalCloseBudget) {
        final remaining = _criticalCloseBudget - elapsed;
        await Future<void>.delayed(remaining);
      }

      await _runBoundedCloseStep(() => windowManager.setPreventClose(false));
      await _runBoundedCloseStep(() => windowManager.destroy());

      // Best-effort cleanup runs in parallel — session disposal,
      // listener unregister, subscription cancellation.
      // This does NOT block window destruction.
      unawaited(_runBestEffortCleanup());

      if (Platform.isWindows) {
        exit(0);
      }
    }
  }

  Future<void> _runCriticalClosePhase(Stopwatch totalStopwatch) async {
    final criticalStopwatch = Stopwatch()..start();
    try {
      // Run AppExitCoordinator handlers but only wait for the critical budget.
      // This covers presence offline write and terminal state publish.
      await AppExitCoordinator.instance
          .shutdown(AppExitReason.windowClose)
          .timeout(
            _criticalCloseBudget,
            onTimeout: () {
              if (kDebugMode) {
                RainDebugLog.event(
                  category: 'desktop_shell',
                  name: 'critical_close_budget_exceeded',
                  severity: RainDebugSeverity.warning,
                  message: '[DesktopShellController] Critical close budget '
                      'exceeded after ${criticalStopwatch.elapsedMilliseconds}ms',
                );
              }
            },
          );
    } catch (error) {
      if (kDebugMode) {
        RainDebugLog.event(
          category: 'desktop_shell',
          name: 'critical_close_phase_error',
          severity: RainDebugSeverity.warning,
          message: '[DesktopShellController] Critical close phase error: $error',
        );
      }
    } finally {
      criticalStopwatch.stop();
      if (kDebugMode) {
        RainDebugLog.event(
          category: 'desktop_shell',
          name: 'critical_close_phase_completed',
          severity: RainDebugSeverity.debug,
          message: '[DesktopShellController] Critical close phase completed in '
              '${criticalStopwatch.elapsedMilliseconds}ms '
              '(total: ${totalStopwatch.elapsedMilliseconds}ms)',
        );
      }
    }
  }

  Future<void> _runBestEffortCleanup() async {
    final cleanupStopwatch = Stopwatch()..start();
    try {
      // Allow any remaining AppExitCoordinator work to finish.
      // Best-effort: no blocking, bounded by a generous timeout.
      await AppExitCoordinator.instance
          .shutdown(AppExitReason.windowClose)
          .timeout(const Duration(seconds: 10), onTimeout: () {});
    } catch (_) {
      // Best-effort cleanup must never crash.
    } finally {
      cleanupStopwatch.stop();
      if (kDebugMode) {
        RainDebugLog.event(
          category: 'desktop_shell',
          name: 'best_effort_cleanup_completed',
          severity: RainDebugSeverity.debug,
          message: '[DesktopShellController] Best-effort cleanup completed in '
              '${cleanupStopwatch.elapsedMilliseconds}ms',
        );
      }
    }
  }

  Future<void> _runBoundedCloseStep(Future<void> Function() action) async {
    try {
      await action().timeout(_closeStepTimeout, onTimeout: () {});
    } catch (_) {
      // The user has already requested process exit; close remains best effort.
    }
  }

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
