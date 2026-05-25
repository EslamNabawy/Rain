import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import 'package:rain/application/runtime/app_exit_coordinator.dart';

class DesktopShellController with WindowListener {
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
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
  }

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}
