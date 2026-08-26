/// # app_bootstrap.dart
///
/// [AppBootstrapper] orchestrates Rain's startup sequence: initializes Firebase
/// (Realtime Database, Remote Config), opens the local Drift database, selects
/// the signaling adapter, and wires up the [ForceUpdateService]. Produces an
/// [AppBootstrapState] consumed by Riverpod providers.
///
/// **Key types:** [AppBootstrapper], [AppBootstrapState]
///
/// **Depends on:** Firebase, rain_core, protocol_brain, infrastructure services
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/firebase/firebase_options.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/services/rain_debug_log_service.dart';
import 'package:rain/infrastructure/signaling/debug_signaling_adapter.dart';
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
  AppBootstrapper({RainDebugLogService? debugLogService})
    : _debugLogService = debugLogService;

  final RainDebugLogService? _debugLogService;

  Future<AppBootstrapState> bootstrap(AppEnvironment environment) async {
    final effectiveEnvironment = kReleaseMode
        ? environment.sanitizedForRelease()
        : environment;
    if (kReleaseMode) {
      effectiveEnvironment.validateForRelease();
    }

    final database = RainDatabase();
    try {
      FirebaseRemoteConfig? remoteConfig;
      FirebaseDatabase? firebaseDatabase;
      if (effectiveEnvironment.backend == RainBackend.firebase &&
          effectiveEnvironment.supportsFirebasePlatform) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        remoteConfig = FirebaseRemoteConfig.instance;
        await remoteConfig.setConfigSettings(
          RemoteConfigSettings(
            fetchTimeout: const Duration(seconds: 10),
            minimumFetchInterval: const Duration(minutes: 1),
          ),
        );
        firebaseDatabase = FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: effectiveEnvironment.firebaseDatabaseUrl,
        );
      }

      final signalingCipher = SignalingCipher.fromKeyMaterial(
        effectiveEnvironment.signalingEncryptionKey,
      );
      final rawAdapter = effectiveEnvironment.shouldUseFallbackAdapter
          ? NoopSignalingAdapter()
          : switch (effectiveEnvironment.backend) {
              RainBackend.firebase => FirebaseSignalingAdapter(
                database: firebaseDatabase!,
                signalingCipher: signalingCipher,
              ),
              RainBackend.noop => NoopSignalingAdapter(),
            };
      final debugLogService = _debugLogService;
      final adapter = debugLogService == null
          ? rawAdapter
          : wrapSignalingAdapterWithDebugLogging(rawAdapter, debugLogService);

      if (effectiveEnvironment.shouldSmokeAutoprovision) {
        await _seedSmokeIdentity(
          environment: effectiveEnvironment,
          database: database,
          adapter: adapter,
        );
      }

      return AppBootstrapState(
        environment: effectiveEnvironment,
        database: database,
        adapter: adapter,
        firebaseDatabase: firebaseDatabase,
        forceUpdateService: ForceUpdateService(
          remoteConfig: remoteConfig,
          updateUrl: effectiveEnvironment.forceUpdateUrl,
          updateChannel: AppUpdateChannel.parse(
            effectiveEnvironment.updateChannel,
          ),
        ),
      );
    } catch (_) {
      await database.close();
      rethrow;
    }
  }
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
