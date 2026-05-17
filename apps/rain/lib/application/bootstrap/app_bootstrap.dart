import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/firebase/firebase_options.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';

class AppBootstrapState {
  const AppBootstrapState({
    required this.environment,
    required this.database,
    required this.adapter,
    required this.forceUpdateService,
    this.firebaseDatabase,
  });

  final AppEnvironment environment;
  final RainDatabase database;
  final SignalingAdapter adapter;
  final ForceUpdateService forceUpdateService;
  final FirebaseDatabase? firebaseDatabase;
}

class AppBootstrapper {
  Future<AppBootstrapState> bootstrap(AppEnvironment environment) async {
    final effectiveEnvironment = kReleaseMode
        ? environment.sanitizedForRelease()
        : environment;
    if (kReleaseMode) {
      effectiveEnvironment.validateForRelease();
    }

    final database = RainDatabase();
    try {
      ForceUpdateConfigLoader? forceUpdateConfigLoader;

      FirebaseRemoteConfig? remoteConfig;
      FirebaseDatabase? firebaseDatabase;
      if (effectiveEnvironment.backend == RainBackend.firebase &&
          effectiveEnvironment.supportsFirebasePlatform) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        remoteConfig = FirebaseRemoteConfig.instance;
        firebaseDatabase = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: effectiveEnvironment.firebaseDatabaseUrl,
        );
      }

      if (effectiveEnvironment.backend == RainBackend.supabase &&
          effectiveEnvironment.isSupabaseConfigured) {
        await Supabase.initialize(
          url: effectiveEnvironment.supabaseUrl,
          anonKey: effectiveEnvironment.supabaseAnonKey,
        );
        forceUpdateConfigLoader = _loadSupabaseForceUpdateConfig;
      }

      final signalingCipher = SignalingCipher.fromKeyMaterial(
        effectiveEnvironment.signalingEncryptionKey,
      );
      final adapter = effectiveEnvironment.shouldUseFallbackAdapter
          ? NoopSignalingAdapter()
          : switch (effectiveEnvironment.backend) {
              RainBackend.firebase => FirebaseSignalingAdapter(
                database: firebaseDatabase!,
                signalingCipher: signalingCipher,
              ),
              RainBackend.supabase => SupabaseSignalingAdapter(
                projectUrl: effectiveEnvironment.supabaseUrl,
                signalingCipher: signalingCipher,
              ),
              RainBackend.noop => NoopSignalingAdapter(),
            };

      if (effectiveEnvironment.shouldSmokeAutoprovision) {
        await _seedSmokeIdentity(
          environment: effectiveEnvironment,
          database: database,
          adapter: adapter,
        );
      }

      await _DesktopShellController().initialize();

      return AppBootstrapState(
        environment: effectiveEnvironment,
        database: database,
        adapter: adapter,
        firebaseDatabase: firebaseDatabase,
        forceUpdateService: ForceUpdateService(
          remoteConfig: remoteConfig,
          updateUrl: effectiveEnvironment.forceUpdateUrl,
          configLoader: forceUpdateConfigLoader,
        ),
      );
    } catch (_) {
      await database.close();
      rethrow;
    }
  }
}

Future<ForceUpdateConfig?> _loadSupabaseForceUpdateConfig() async {
  final rows = await Supabase.instance.client
      .from('app_config')
      .select('min_required_version, update_url')
      .limit(1);
  final resultRows = rows as List<dynamic>;
  if (resultRows.isEmpty) {
    return null;
  }

  final row = Map<String, dynamic>.from(resultRows.first as Map);
  final minVersion = (row['min_required_version'] as String? ?? '').trim();
  final updateUrl = (row['update_url'] as String? ?? '').trim();
  if (minVersion.isEmpty && updateUrl.isEmpty) {
    return null;
  }

  return ForceUpdateConfig(minVersion: minVersion, updateUrl: updateUrl);
}

Future<void> _seedSmokeIdentity({
  required AppEnvironment environment,
  required RainDatabase database,
  required SignalingAdapter adapter,
}) async {
  final username = environment.smokeUsername.trim();
  final password = environment.smokePassword;
  final displayName = environment.smokeDisplayName.trim().isEmpty
      ? username
      : environment.smokeDisplayName.trim();

  if (username.isEmpty || password.isEmpty) {
    return;
  }

  try {
    await adapter.login(username, password);
  } catch (_) {
    await adapter.register(username, password);
  }

  final uid = await adapter.currentUid();
  final now = DateTime.now().millisecondsSinceEpoch;
  final identity = RainIdentity(
    username: username,
    displayName: displayName,
    createdAt: now,
    gender: null,
  );

  await IdentityRepository(database).saveIdentity(identity);
  await adapter.addToUserSearch(username);
  await adapter.upsertIdentity(
    BackendIdentity(
      username: username,
      uid: uid,
      displayName: displayName,
      gender: null,
      registeredAt: now,
      lastSeen: now,
      lastHeartbeat: now,
      online: true,
    ),
  );
  await adapter.setPresence(username, true);
}

class _DesktopShellController with WindowListener {
  bool _initialized = false;
  bool _closing = false;

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
    await windowManager.setPreventClose(false);
    await windowManager.waitUntilReadyToShow(const WindowOptions(), () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  Future<void> onWindowClose() async {
    if (_closing) {
      return;
    }
    _closing = true;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
