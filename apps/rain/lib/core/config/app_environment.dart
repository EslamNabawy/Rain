import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'runtime_environment.dart';

enum RainBackend { noop, firebase, supabase }

class AppEnvironment {
  const AppEnvironment({
    required this.backend,
    required this.iceServers,
    required this.forceUpdateUrl,
    required this.backgroundHeartbeatSeconds,
    required this.allowPublicTurn,
    required this.smokeMode,
    required this.smokeUsername,
    required this.smokePassword,
    required this.smokeDisplayName,
    required this.firebaseApiKey,
    required this.firebaseAppId,
    required this.firebaseMessagingSenderId,
    required this.firebaseProjectId,
    required this.firebaseDatabaseUrl,
    required this.firebaseStorageBucket,
    required this.firebaseAuthDomain,
    required this.firebaseMeasurementId,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.signalingEncryptionKey,
    required this.turnBrokerUrl,
  });

  final RainBackend backend;
  final List<Map<String, dynamic>> iceServers;
  final String forceUpdateUrl;
  final int backgroundHeartbeatSeconds;
  final bool allowPublicTurn;
  final bool smokeMode;
  final String smokeUsername;
  final String smokePassword;
  final String smokeDisplayName;
  final String firebaseApiKey;
  final String firebaseAppId;
  final String firebaseMessagingSenderId;
  final String firebaseProjectId;
  final String firebaseDatabaseUrl;
  final String firebaseStorageBucket;
  final String firebaseAuthDomain;
  final String firebaseMeasurementId;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final String signalingEncryptionKey;
  final String turnBrokerUrl;

  factory AppEnvironment.fromEnvironment({
    Map<String, String>? runtimeEnvironment,
  }) {
    final environment = runtimeEnvironment ?? currentProcessEnvironment();

    String readString(
      String name, {
      required String compileTimeValue,
      String defaultValue = '',
    }) {
      if (compileTimeValue.isNotEmpty) {
        return compileTimeValue;
      }
      final runtimeValue = environment[name]?.trim();
      if (runtimeValue != null && runtimeValue.isNotEmpty) {
        return runtimeValue;
      }
      return defaultValue;
    }

    int readInt(
      String name, {
      required String compileTimeValue,
      required int defaultValue,
    }) {
      final rawValue = readString(name, compileTimeValue: compileTimeValue);
      return int.tryParse(rawValue) ?? defaultValue;
    }

    bool readBool(
      String name, {
      required String compileTimeValue,
      required bool defaultValue,
    }) {
      final rawValue = readString(
        name,
        compileTimeValue: compileTimeValue,
      ).toLowerCase();
      if (rawValue.isEmpty) {
        return defaultValue;
      }
      switch (rawValue) {
        case '1':
        case 'true':
        case 'yes':
        case 'on':
          return true;
        case '0':
        case 'false':
        case 'no':
        case 'off':
          return false;
        default:
          return defaultValue;
      }
    }

    final backend = switch (readString(
      'RAIN_BACKEND',
      compileTimeValue: const String.fromEnvironment('RAIN_BACKEND'),
      defaultValue: 'firebase',
    )) {
      'firebase' => RainBackend.firebase,
      'supabase' => RainBackend.supabase,
      _ => RainBackend.noop,
    };

    final rawIceServers = readString(
      'RAIN_ICE_SERVERS',
      compileTimeValue: const String.fromEnvironment('RAIN_ICE_SERVERS'),
    );
    final iceServers = rawIceServers.isEmpty
        ? defaultIceServers
        : List<Map<String, dynamic>>.from(
            (jsonDecode(rawIceServers) as List<dynamic>)
                .cast<Map<String, dynamic>>(),
          );

    return AppEnvironment(
      backend: backend,
      iceServers: iceServers,
      forceUpdateUrl: readString(
        'RAIN_UPDATE_URL',
        compileTimeValue: const String.fromEnvironment('RAIN_UPDATE_URL'),
        defaultValue: 'https://github.com/EslamNabawy/Rain/releases',
      ),
      backgroundHeartbeatSeconds: readInt(
        'RAIN_BACKGROUND_HEARTBEAT_SECONDS',
        compileTimeValue: const String.fromEnvironment(
          'RAIN_BACKGROUND_HEARTBEAT_SECONDS',
        ),
        defaultValue: 30,
      ),
      allowPublicTurn: readBool(
        'RAIN_ALLOW_PUBLIC_TURN',
        compileTimeValue: const String.fromEnvironment(
          'RAIN_ALLOW_PUBLIC_TURN',
        ),
        defaultValue: false,
      ),
      smokeMode: readBool(
        'RAIN_SMOKE_MODE',
        compileTimeValue: const String.fromEnvironment('RAIN_SMOKE_MODE'),
        defaultValue: false,
      ),
      smokeUsername: readString(
        'RAIN_SMOKE_USERNAME',
        compileTimeValue: const String.fromEnvironment('RAIN_SMOKE_USERNAME'),
      ),
      smokePassword: readString(
        'RAIN_SMOKE_PASSWORD',
        compileTimeValue: const String.fromEnvironment('RAIN_SMOKE_PASSWORD'),
      ),
      smokeDisplayName: readString(
        'RAIN_SMOKE_DISPLAY_NAME',
        compileTimeValue: const String.fromEnvironment(
          'RAIN_SMOKE_DISPLAY_NAME',
        ),
      ),
      firebaseApiKey: readString(
        'FIREBASE_API_KEY',
        compileTimeValue: const String.fromEnvironment('FIREBASE_API_KEY'),
      ),
      firebaseAppId: readString(
        'FIREBASE_APP_ID',
        compileTimeValue: const String.fromEnvironment('FIREBASE_APP_ID'),
      ),
      firebaseMessagingSenderId: readString(
        'FIREBASE_MESSAGING_SENDER_ID',
        compileTimeValue: const String.fromEnvironment(
          'FIREBASE_MESSAGING_SENDER_ID',
        ),
      ),
      firebaseProjectId: readString(
        'FIREBASE_PROJECT_ID',
        compileTimeValue: const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      ),
      firebaseDatabaseUrl: readString(
        'FIREBASE_DATABASE_URL',
        compileTimeValue: const String.fromEnvironment('FIREBASE_DATABASE_URL'),
        defaultValue: 'https://rain-8fb4b-default-rtdb.firebaseio.com',
      ),
      firebaseStorageBucket: readString(
        'FIREBASE_STORAGE_BUCKET',
        compileTimeValue: const String.fromEnvironment(
          'FIREBASE_STORAGE_BUCKET',
        ),
      ),
      firebaseAuthDomain: readString(
        'FIREBASE_AUTH_DOMAIN',
        compileTimeValue: const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
      ),
      firebaseMeasurementId: readString(
        'FIREBASE_MEASUREMENT_ID',
        compileTimeValue: const String.fromEnvironment(
          'FIREBASE_MEASUREMENT_ID',
        ),
      ),
      supabaseUrl: readString(
        'SUPABASE_URL',
        compileTimeValue: const String.fromEnvironment('SUPABASE_URL'),
      ),
      supabaseAnonKey: readString(
        'SUPABASE_ANON_KEY',
        compileTimeValue: const String.fromEnvironment('SUPABASE_ANON_KEY'),
      ),
      signalingEncryptionKey: readString(
        'RAIN_SIGNALING_ENCRYPTION_KEY',
        compileTimeValue: const String.fromEnvironment(
          'RAIN_SIGNALING_ENCRYPTION_KEY',
        ),
        defaultValue: demoSignalingEncryptionKey,
      ),
      turnBrokerUrl: readString(
        'RAIN_TURN_BROKER_URL',
        compileTimeValue: const String.fromEnvironment('RAIN_TURN_BROKER_URL'),
      ),
    );
  }

  bool get supportsFirebasePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  bool get isFirebaseConfigured =>
      supportsFirebasePlatform && firebaseDatabaseUrl.isNotEmpty;

  bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool get shouldUseFallbackAdapter {
    return switch (backend) {
      RainBackend.noop => true,
      RainBackend.firebase => !isFirebaseConfigured,
      RainBackend.supabase => !isSupabaseConfigured,
    };
  }

  bool get hasSmokeIdentity =>
      smokeUsername.isNotEmpty && smokePassword.isNotEmpty;

  bool get shouldSmokeAutoprovision =>
      smokeMode && hasSmokeIdentity && !shouldUseFallbackAdapter;

  bool get usesPublicOpenRelay => iceServers.any((server) {
    return _serverUrls(
      server,
    ).any((url) => url.contains('openrelay.metered.ca'));
  });

  bool get hasProjectOwnedTurn => iceServers.any((server) {
    if (_serverUrls(
      server,
    ).any((url) => url.contains('openrelay.metered.ca'))) {
      return false;
    }
    return _serverUrls(server).any((url) {
      final normalized = url.toLowerCase();
      return normalized.startsWith('turn:') || normalized.startsWith('turns:');
    });
  });

  bool get allTurnServersHaveCredentials {
    final turnServers = iceServers
        .where(_serverHasTurnUrl)
        .toList(growable: false);
    return turnServers.isNotEmpty && turnServers.every(_serverHasCredentials);
  }

  bool get hasTurnUdpEndpoint =>
      _iceUrls.any((url) => _isTurnUrl(url) && _hasTransport(url, 'udp'));

  bool get hasTurnTcpEndpoint =>
      _iceUrls.any((url) => _isTurnUrl(url) && _hasTransport(url, 'tcp'));

  bool get hasTurnsTcpEndpoint =>
      _iceUrls.any((url) => _isTurnsUrl(url) && _hasTransport(url, 'tcp'));

  bool get hasProductionTurnCoverage =>
      hasTurnBroker ||
      (hasProjectOwnedTurn &&
          allTurnServersHaveCredentials &&
          hasTurnUdpEndpoint &&
          hasTurnTcpEndpoint &&
          hasTurnsTcpEndpoint);

  bool get hasTurnBroker => turnBrokerUrl.trim().isNotEmpty;

  Iterable<String> get _iceUrls sync* {
    for (final server in iceServers) {
      yield* _serverUrls(server);
    }
  }

  bool get releaseRelayIsLimited => !hasProductionTurnCoverage;

  String get releaseRelayWarning =>
      'Managed TURN fallback is not fully configured. Rain will start with '
      'direct peer routes; add project-owned UDP/TCP/TLS TURN servers for '
      'reliable release connections.';

  AppEnvironment sanitizedForRelease() {
    if (allowPublicTurn) {
      return this;
    }

    final safeIceServers = iceServers
        .where((server) {
          return !_serverUrls(
            server,
          ).any((url) => url.contains('openrelay.metered.ca'));
        })
        .map(_cloneIceServer)
        .toList(growable: false);

    final nextIceServers = safeIceServers.isEmpty
        ? releaseDefaultIceServers
        : safeIceServers;
    if (!usesPublicOpenRelay && nextIceServers.length == iceServers.length) {
      return this;
    }

    return AppEnvironment(
      backend: backend,
      iceServers: nextIceServers,
      forceUpdateUrl: forceUpdateUrl,
      backgroundHeartbeatSeconds: backgroundHeartbeatSeconds,
      allowPublicTurn: false,
      smokeMode: smokeMode,
      smokeUsername: smokeUsername,
      smokePassword: smokePassword,
      smokeDisplayName: smokeDisplayName,
      firebaseApiKey: firebaseApiKey,
      firebaseAppId: firebaseAppId,
      firebaseMessagingSenderId: firebaseMessagingSenderId,
      firebaseProjectId: firebaseProjectId,
      firebaseDatabaseUrl: firebaseDatabaseUrl,
      firebaseStorageBucket: firebaseStorageBucket,
      firebaseAuthDomain: firebaseAuthDomain,
      firebaseMeasurementId: firebaseMeasurementId,
      supabaseUrl: supabaseUrl,
      supabaseAnonKey: supabaseAnonKey,
      signalingEncryptionKey: signalingEncryptionKey,
      turnBrokerUrl: turnBrokerUrl,
    );
  }

  void validateForRelease() {
    if (!allowPublicTurn && usesPublicOpenRelay) {
      throw StateError('Release builds require project-owned TURN servers.');
    }
  }

  void validateProductionIceConfig() {
    if (usesPublicOpenRelay) {
      throw StateError(
        'Production release builds must not use OpenRelay/public TURN servers.',
      );
    }
    if (hasTurnBroker) {
      return;
    }
    if (!hasProjectOwnedTurn) {
      throw StateError(
        'Release builds require RAIN_TURN_BROKER_URL or at least one project-owned TURN/TURNS URL in RAIN_ICE_SERVERS.',
      );
    }
    if (!allTurnServersHaveCredentials) {
      throw StateError(
        'Every production TURN/TURNS server entry must include username and credential.',
      );
    }
    if (!hasTurnUdpEndpoint) {
      throw StateError(
        'Production RAIN_ICE_SERVERS must include a turn: UDP endpoint.',
      );
    }
    if (!hasTurnTcpEndpoint) {
      throw StateError(
        'Production RAIN_ICE_SERVERS must include a turn: TCP endpoint.',
      );
    }
    if (!hasTurnsTcpEndpoint) {
      throw StateError(
        'Production RAIN_ICE_SERVERS must include a turns: TCP/TLS endpoint.',
      );
    }
  }

  Duration get heartbeatInterval => Duration(
    seconds: backgroundHeartbeatSeconds > 0 ? backgroundHeartbeatSeconds : 30,
  );

  String get backendLabel => switch (backend) {
    RainBackend.noop => 'Local Demo',
    RainBackend.firebase => 'Firebase',
    RainBackend.supabase => 'Supabase',
  };

  String get fallbackReason => switch (backend) {
    RainBackend.noop =>
      'Running with the local demo adapter. Identities, friends, and queues work locally, but peer signaling is disabled until you choose Firebase or Supabase.',
    RainBackend.firebase =>
      !supportsFirebasePlatform
          ? 'Firebase signaling is configured only for Android, macOS, and Windows in this build, so Rain is using the local demo adapter on this platform.'
          : 'Firebase is selected, but FIREBASE_DATABASE_URL is missing, so Rain is using the local demo adapter until the Realtime Database instance is configured.',
    RainBackend.supabase =>
      'Supabase is selected but SUPABASE_URL and SUPABASE_ANON_KEY are missing, so Rain is using the local demo adapter.',
  };
}

Iterable<String> _serverUrls(Map<String, dynamic> server) sync* {
  final urls = server['urls'];
  if (urls is Iterable) {
    for (final url in urls) {
      yield url.toString();
    }
    return;
  }
  yield urls.toString();
}

Map<String, dynamic> _cloneIceServer(Map<String, dynamic> server) {
  return Map<String, dynamic>.fromEntries(
    server.entries.map((entry) {
      final value = entry.value;
      return MapEntry<String, dynamic>(
        entry.key,
        value is List ? List<dynamic>.from(value) : value,
      );
    }),
  );
}

bool _serverHasTurnUrl(Map<String, dynamic> server) {
  return _serverUrls(server).any((url) => _isTurnUrl(url) || _isTurnsUrl(url));
}

bool _serverHasCredentials(Map<String, dynamic> server) {
  final username = server['username']?.toString().trim() ?? '';
  final credential = server['credential']?.toString().trim() ?? '';
  return username.isNotEmpty && credential.isNotEmpty;
}

bool _isTurnUrl(String url) {
  return url.trim().toLowerCase().startsWith('turn:');
}

bool _isTurnsUrl(String url) {
  return url.trim().toLowerCase().startsWith('turns:');
}

bool _hasTransport(String url, String transport) {
  final normalized = url.trim().toLowerCase();
  final expected = 'transport=${transport.toLowerCase()}';
  return normalized.contains('?$expected') || normalized.contains('&$expected');
}

const releaseDefaultIceServers = <Map<String, dynamic>>[
  <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
];

const demoSignalingEncryptionKey =
    'rain-demo-signaling-encryption-key-v1-change-me';

const defaultIceServers = <Map<String, dynamic>>[
  <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
  <String, dynamic>{
    'urls': 'turn:openrelay.metered.ca:80',
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
];
