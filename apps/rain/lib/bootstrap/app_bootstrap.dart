import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../config/app_environment.dart';
import '../firebase_options.dart';
import '../services/background_services.dart';
import '../services/force_update_service.dart';
import '../services/noop_signaling_adapter.dart';

class AppBootstrapState {
  const AppBootstrapState({
    required this.environment,
    required this.database,
    required this.adapter,
    required this.forceUpdateService,
  });

  final AppEnvironment environment;
  final RainDatabase database;
  final SignalingAdapter adapter;
  final ForceUpdateService forceUpdateService;
}

class AppBootstrapper {
  Future<AppBootstrapState> bootstrap(AppEnvironment environment) async {
    final database = RainDatabase();

    FirebaseRemoteConfig? remoteConfig;
    if (environment.backend == RainBackend.firebase &&
        environment.supportsFirebasePlatform) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      remoteConfig = FirebaseRemoteConfig.instance;
    }

    if (environment.backend == RainBackend.supabase &&
        environment.isSupabaseConfigured) {
      await Supabase.initialize(
        url: environment.supabaseUrl,
        anonKey: environment.supabaseAnonKey,
      );
    }

    await BackgroundServices().initialize();
    await _DesktopShellController().initialize();

    final adapter = environment.shouldUseFallbackAdapter
        ? NoopSignalingAdapter()
        : switch (environment.backend) {
            RainBackend.firebase => FirebaseSignalingAdapter(
                database: FirebaseDatabase.instanceFor(
                  app: Firebase.app(),
                  databaseURL: environment.firebaseDatabaseUrl,
                ),
              ),
            RainBackend.supabase => SupabaseSignalingAdapter(),
            RainBackend.noop => NoopSignalingAdapter(),
          };

    return AppBootstrapState(
      environment: environment,
      database: database,
      adapter: adapter,
      forceUpdateService: ForceUpdateService(
        remoteConfig: remoteConfig,
        updateUrl: environment.forceUpdateUrl,
      ),
    );
  }
}

class _DesktopShellController with WindowListener, TrayListener {
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return;
    }
    _initialized = true;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);

    if (Platform.isWindows) {
      const iconPath = 'windows/runner/resources/app_icon.ico';
      if (File(iconPath).existsSync()) {
        trayManager.addListener(this);
        await trayManager.setIcon(iconPath);
        await trayManager.setToolTip('Rain');
        await trayManager.setContextMenu(
          Menu(
            items: <MenuItem>[
              MenuItem(key: 'show', label: 'Show Rain'),
              MenuItem.separator(),
              MenuItem(key: 'exit', label: 'Exit'),
            ],
          ),
        );
      }
    }
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'show':
        await windowManager.show();
        await windowManager.focus();
      case 'exit':
        await windowManager.destroy();
        exit(0);
    }
  }

  @override
  Future<void> onWindowClose() async {
    await windowManager.hide();
  }
}
