import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:protocol_brain/protocol_brain.dart'
    show ConnectionRequestBackendMode;

import 'runtime_environment.dart';

enum RainBackend { noop, firebase }

class AppEnvironment {
  const AppEnvironment({
    required this.backend,
    required this.connectionRequestBackendMode,
    required this.iceServers,
    required this.forceUpdateUrl,
    required this.updateChannel,
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
    required this.signalingEncryptionKey,
    required this.turnBrokerUrl,
  });

  final RainBackend backend;
  final ConnectionRequestBackendMode connectionRequestBackendMode;
  final List<Map<String, dynamic>> iceServers;
  final String forceUpdateUrl;
  final String updateChannel;
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
      connectionRequestBackendMode: ConnectionRequestBackendMode.parse(
        readString(
          'CONNECTION_REQUEST_BACKEND_MODE',
          compileTimeValue: const String.fromEnvironment(
            'CONNECTION_REQUEST_BACKEND_MODE',
          ),
          defaultValue: 'rtdbOnly',
        ),
      ),
      iceServers: iceServers,
      forceUpdateUrl: readString(
        'RAIN_UPDATE_URL',
        compileTimeValue: const String.fromEnvironment('RAIN_UPDATE_URL'),
        defaultValue: 'https://github.com/EslamNabawy/Rain/releases',
      ),
      updateChannel: readString(
        'RAIN_UPDATE_CHANNEL',
        compileTimeValue: const String.fromEnvironment('RAIN_UPDATE_CHANNEL'),
        defaultValue: 'stable',
      ).toLowerCase(),
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

  bool get shouldUseFallbackAdapter {
    return switch (backend) {
      RainBackend.noop => true,
      RainBackend.firebase => !isFirebaseConfigured,
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

  bool get usesDemoSignalingEncryptionKey =>
      signalingEncryptionKey == demoSignalingEncryptionKey;

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
    final releaseSafeIceServers = _windowsReleaseSafeIceServers(iceServers);
    if (allowPublicTurn) {
      if (_sameIceServerUrls(releaseSafeIceServers, iceServers)) {
        return this;
      }
      return AppEnvironment(
        backend: backend,
        connectionRequestBackendMode: connectionRequestBackendMode,
        iceServers: releaseSafeIceServers,
        forceUpdateUrl: forceUpdateUrl,
        updateChannel: updateChannel,
        backgroundHeartbeatSeconds: backgroundHeartbeatSeconds,
        allowPublicTurn: true,
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
        signalingEncryptionKey: signalingEncryptionKey,
        turnBrokerUrl: turnBrokerUrl,
      );
    }

    final safeIceServers = releaseSafeIceServers
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
      connectionRequestBackendMode: connectionRequestBackendMode,
      iceServers: nextIceServers,
      forceUpdateUrl: forceUpdateUrl,
      updateChannel: updateChannel,
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
      signalingEncryptionKey: signalingEncryptionKey,
      turnBrokerUrl: turnBrokerUrl,
    );
  }

  void validateForRelease() {
    if (usesDemoSignalingEncryptionKey && !allowPublicTurn) {
      throw StateError(
        'Production release builds must not use the demo signaling encryption key.',
      );
    }
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
  };

  String get fallbackReason => switch (backend) {
    RainBackend.noop =>
      'Running with the local demo adapter. Identities, friends, and queues work locally, but peer signaling is disabled until Firebase is configured.',
    RainBackend.firebase =>
      !supportsFirebasePlatform
          ? 'Firebase signaling is configured only for Android, macOS, and Windows in this build, so Rain is using the local demo adapter on this platform.'
          : 'Firebase is selected, but FIREBASE_DATABASE_URL is missing, so Rain is using the local demo adapter until the Realtime Database instance is configured.',
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

List<Map<String, dynamic>> _windowsReleaseSafeIceServers(
  List<Map<String, dynamic>> servers,
) {
  if (!kReleaseMode || defaultTargetPlatform != TargetPlatform.windows) {
    return servers.map(_cloneIceServer).toList(growable: false);
  }

  String? selectedStunUrl;
  final relayServers = <Map<String, dynamic>>[];
  for (final server in servers) {
    final turnUrls = <String>[];
    for (final url in _serverUrls(server)) {
      final normalized = url.trim().toLowerCase();
      if (normalized.startsWith('stun:')) {
        selectedStunUrl ??= url;
      } else if (normalized.startsWith('turn:') ||
          normalized.startsWith('turns:')) {
        turnUrls.add(url);
      }
    }
    if (turnUrls.isNotEmpty) {
      relayServers.add(_copyIceServerWithUrls(server, turnUrls));
    }
  }

  return <Map<String, dynamic>>[
    <String, dynamic>{
      'urls': selectedStunUrl ?? 'stun:stun.l.google.com:19302',
    },
    ...relayServers,
  ];
}

Map<String, dynamic> _copyIceServerWithUrls(
  Map<String, dynamic> server,
  List<String> urls,
) {
  final copy = _cloneIceServer(server);
  copy['urls'] = urls.length == 1 ? urls.single : urls;
  return copy;
}

bool _sameIceServerUrls(
  List<Map<String, dynamic>> first,
  List<Map<String, dynamic>> second,
) {
  final firstUrls = first.expand(_serverUrls).toList(growable: false);
  final secondUrls = second.expand(_serverUrls).toList(growable: false);
  if (firstUrls.length != secondUrls.length) {
    return false;
  }
  for (var index = 0; index < firstUrls.length; index += 1) {
    if (firstUrls[index] != secondUrls[index]) {
      return false;
    }
  }
  return true;
}

const testedPublicStunIceServers = <Map<String, dynamic>>[
  <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun2.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun3.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun4.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun.voipstunt.com:3478'},
  <String, dynamic>{'urls': 'stun:stun.voipbuster.com:3478'},
  <String, dynamic>{'urls': 'stun:stun.sipgate.net:10000'},
  <String, dynamic>{'urls': 'stun:stun.schlund.de:3478'},
  <String, dynamic>{'urls': 'stun:stun.1und1.de:3478'},
];

const releaseDefaultIceServers = <Map<String, dynamic>>[
  ...testedPublicStunIceServers,
];

const demoSignalingEncryptionKey =
    'rain-demo-signaling-encryption-key-v1-change-me';

const defaultIceServers = <Map<String, dynamic>>[
  ...testedPublicStunIceServers,
  <String, dynamic>{
    'urls': <String>[
      'turn:openrelay.metered.ca:80?transport=udp',
      'turn:openrelay.metered.ca:80?transport=tcp',
      'turn:openrelay.metered.ca:443?transport=tcp',
      'turns:openrelay.metered.ca:443?transport=tcp',
    ],
    'username': 'openrelayproject',
    'credential': 'openrelayproject',
  },
];
