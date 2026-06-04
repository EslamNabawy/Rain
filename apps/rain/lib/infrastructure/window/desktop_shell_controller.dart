import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import 'package:rain/application/runtime/app_exit_coordinator.dart';

class DesktopShellController with WindowListener {
  static const Duration _closeStepTimeout = Duration(seconds: 2);

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
    try {
      await AppExitCoordinator.instance.shutdown(AppExitReason.windowClose);
    } finally {
      await _runBoundedCloseStep(() => windowManager.setPreventClose(false));
      await _runBoundedCloseStep(() => windowManager.destroy());
      if (Platform.isWindows) {
        exit(0);
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
