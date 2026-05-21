import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:protocol_brain/protocol_brain.dart';

typedef TurnCredentialFetcher = Future<TurnCredentialFetchResult> Function();

class TurnCredentialService {
  TurnCredentialService({
    required List<Map<String, dynamic>> baseIceServers,
    required String brokerUrl,
    bool enableExperimentalRelay = false,
    IceMetricsStore? metricsStore,
    Future<String?> Function()? idTokenProvider,
    HttpClient? httpClient,
    DateTime Function()? now,
    TurnCredentialFetcher? credentialFetcher,
  }) : _baseIceServers = _cloneIceServers(baseIceServers),
       _brokerUrl = brokerUrl.trim(),
       _enableExperimentalRelay = enableExperimentalRelay,
       _metricsStore = metricsStore ?? MemoryIceMetricsStore(),
       _idTokenProvider = idTokenProvider ?? _defaultFirebaseIdTokenProvider,
       _httpClient = httpClient ?? HttpClient(),
       _now = now ?? DateTime.now,
       _credentialFetcher = credentialFetcher;

  final List<Map<String, dynamic>> _baseIceServers;
  final String _brokerUrl;
  final bool _enableExperimentalRelay;
  final IceMetricsStore _metricsStore;
  final Future<String?> Function() _idTokenProvider;
  final HttpClient _httpClient;
  final DateTime Function() _now;
  final TurnCredentialFetcher? _credentialFetcher;

  TurnCredentialFetchResult? _cache;
  TurnCredentialDiagnostics _diagnostics = const TurnCredentialDiagnostics();

  TurnCredentialDiagnostics get diagnostics => _diagnostics;

  void recordAttemptResult(IceAttemptResult result) {
    _metricsStore.record(result);
  }

  Future<List<Map<String, dynamic>>> iceServersForAttempt(
    IceAttemptDescriptor attempt,
  ) async {
    switch (attempt.stage) {
      case IceAttemptStage.directStunOnly:
        return _stunPoolServers();
      case IceAttemptStage.primaryRelay:
        return _primaryRelayServers();
      case IceAttemptStage.backupRelay:
        return _backupRelayServers(requireRelay: true);
      case IceAttemptStage.experimentalRelay:
        if (!_enableExperimentalRelay) {
          throw StateError('Experimental relay tier is disabled.');
        }
        return _experimentalRelayServers();
      case IceAttemptStage.fullRestart:
        return _fullRestartServers();
    }
  }

  Future<List<Map<String, dynamic>>> iceServers({
    bool requireTurn = false,
  }) async {
    if (_brokerUrl.isEmpty) {
      final baseServers = _cloneIceServers(_baseIceServers);
      _diagnostics = TurnCredentialDiagnostics.fromIceServers(
        brokerConfigured: false,
        provider: 'static',
        iceServers: baseServers,
      );
      if (requireTurn && !baseServers.any(_hasTurnUrl)) {
        throw StateError(
          'Direct path blocked. No TURN relay is configured for this build.',
        );
      }
      return baseServers;
    }
    final cached = _cache;
    if (cached != null && cached.isUsable(_now())) {
      _diagnostics = TurnCredentialDiagnostics.fromIceServers(
        brokerConfigured: true,
        provider: cached.provider,
        iceServers: cached.iceServers,
        expiresAt: cached.expiresAt,
      );
      return _mergeIceServers(cached.iceServers);
    }
    try {
      final fetched = _credentialFetcher == null
          ? await _fetchBrokerCredentials()
          : await _credentialFetcher();
      _cache = fetched;
      _diagnostics = TurnCredentialDiagnostics.fromIceServers(
        brokerConfigured: true,
        provider: fetched.provider,
        iceServers: fetched.iceServers,
        expiresAt: fetched.expiresAt,
      );
      return _mergeIceServers(fetched.iceServers);
    } catch (error) {
      final brokerError = _turnBrokerError(error);
      _diagnostics = TurnCredentialDiagnostics(
        brokerConfigured: true,
        provider: 'unknown',
        turnUrlCount: 0,
        lastError: brokerError.message,
        errorCode: brokerError.code,
      );
      if (requireTurn) {
        throw StateError(
          '${_sentence(brokerError.message)} Relay fallback unavailable.',
        );
      }
      return _cloneIceServers(_baseIceServers);
    }
  }

  Future<List<Map<String, dynamic>>> _primaryRelayServers() async {
    _throwIfCoolingDown('primary-relay');
    if (_brokerUrl.isEmpty) {
      throw StateError('Relay credentials unavailable.');
    }
    final servers = await iceServers(requireTurn: true);
    final turnServers = servers.where(_hasTurnUrl).toList(growable: false);
    if (turnServers.isEmpty) {
      throw StateError('Relay credentials unavailable.');
    }
    return <Map<String, dynamic>>[
      ..._stunPoolServers(),
      ...turnServers.map(_cloneIceServer),
    ];
  }

  List<Map<String, dynamic>> _backupRelayServers({required bool requireRelay}) {
    _throwIfCoolingDown('backup-relay');
    final servers = <Map<String, dynamic>>[
      ..._stunPoolServers(),
      ..._openRelayServersFromBase(),
    ];
    if (requireRelay && !servers.any(_hasTurnUrl)) {
      throw StateError('Relay provider unavailable.');
    }
    _diagnostics = TurnCredentialDiagnostics.fromIceServers(
      brokerConfigured: _brokerUrl.isNotEmpty,
      provider: 'openRelay',
      iceServers: servers,
    );
    return _cloneIceServers(servers);
  }

  List<Map<String, dynamic>> _experimentalRelayServers() {
    _throwIfCoolingDown('experimental-relay');
    final servers = <Map<String, dynamic>>[
      ..._stunPoolServers(),
      ..._experimentalRelayServersStatic,
    ];
    _diagnostics = TurnCredentialDiagnostics.fromIceServers(
      brokerConfigured: _brokerUrl.isNotEmpty,
      provider: 'experimental',
      iceServers: servers,
    );
    return _cloneIceServers(servers);
  }

  Future<List<Map<String, dynamic>>> _fullRestartServers() async {
    _throwIfCoolingDown('full-restart');
    final servers = <Map<String, dynamic>>[
      ..._stunPoolServers(),
      ..._openRelayServersFromBase(),
    ];
    try {
      final primary = await iceServers(requireTurn: false);
      for (final server in primary.where(_hasTurnUrl)) {
        servers.add(_cloneIceServer(server));
      }
    } catch (_) {
      // Final restart is best-effort: backup relay is still useful if present.
    }
    if (_enableExperimentalRelay) {
      servers.addAll(_experimentalRelayServersStatic.map(_cloneIceServer));
    }
    final unique = _uniqueIceServers(servers);
    if (!unique.any(_hasTurnUrl)) {
      throw StateError('All connection routes failed.');
    }
    _diagnostics = TurnCredentialDiagnostics.fromIceServers(
      brokerConfigured: _brokerUrl.isNotEmpty,
      provider: 'fullRestart',
      iceServers: unique,
    );
    return unique;
  }

  void _throwIfCoolingDown(String providerId) {
    if (_metricsStore.isCoolingDown(providerId, now: _now())) {
      throw StateError('Relay provider unavailable.');
    }
  }

  Future<TurnCredentialFetchResult> _fetchBrokerCredentials() async {
    final uri = Uri.parse(_brokerUrl);
    final request = await _httpClient
        .postUrl(uri)
        .timeout(const Duration(seconds: 8));
    request.headers.contentType = ContentType.json;
    final token = await _idTokenProvider();
    if (token != null && token.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    request.write(jsonEncode(<String, Object?>{'client': 'rain'}));
    final response = await request.close().timeout(const Duration(seconds: 8));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TurnCredentialException.fromStatus(response.statusCode);
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('TURN broker response must be an object.');
    }
    return parseTurnCredentialResponse(decoded, _now());
  }

  List<Map<String, dynamic>> _mergeIceServers(
    List<Map<String, dynamic>> brokerIceServers,
  ) {
    final stunServers = _baseIceServers
        .where((Map<String, dynamic> server) => _urls(server).any(_isStunUrl))
        .map(_cloneIceServer)
        .toList(growable: false);
    final next = <Map<String, dynamic>>[
      ...stunServers,
      ...brokerIceServers.map(_cloneIceServer),
    ];
    return next.isEmpty ? _cloneIceServers(_baseIceServers) : next;
  }

  List<Map<String, dynamic>> _stunPoolServers() {
    final baseStun = _baseIceServers
        .where((Map<String, dynamic> server) => _urls(server).any(_isStunUrl))
        .map(_cloneIceServer);
    return _uniqueIceServers(<Map<String, dynamic>>[
      ...baseStun,
      ..._defaultStunPool.map(_cloneIceServer),
    ]);
  }

  List<Map<String, dynamic>> _openRelayServersFromBase() {
    return _baseIceServers
        .where((Map<String, dynamic> server) {
          return _urls(
            server,
          ).any((String url) => url.contains('openrelay.metered.ca'));
        })
        .where(_hasTurnUrl)
        .map(_cloneIceServer)
        .toList(growable: false);
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}

TurnCredentialFetchResult parseTurnCredentialResponse(
  Map<String, dynamic> decoded,
  DateTime now,
) {
  final rawIceServers = decoded['iceServers'] ?? decoded['ice_servers'];
  if (rawIceServers is! List) {
    throw const FormatException('TURN broker response is missing iceServers.');
  }
  final iceServers = rawIceServers
      .whereType<Map>()
      .map((Map<dynamic, dynamic> item) {
        return Map<String, dynamic>.fromEntries(
          item.entries.map(
            (MapEntry<dynamic, dynamic> entry) =>
                MapEntry<String, dynamic>(entry.key.toString(), entry.value),
          ),
        );
      })
      .where(_hasIceUrls)
      .toList(growable: false);
  if (!iceServers.any(_hasTurnUrl)) {
    throw const FormatException('TURN broker response has no TURN URLs.');
  }
  return TurnCredentialFetchResult(
    provider: decoded['provider']?.toString().trim() ?? 'unknown',
    iceServers: iceServers,
    expiresAt: _parseExpiresAt(decoded, now),
  );
}

class TurnCredentialFetchResult {
  const TurnCredentialFetchResult({
    required this.provider,
    required this.iceServers,
    required this.expiresAt,
  });

  final String provider;
  final List<Map<String, dynamic>> iceServers;
  final DateTime expiresAt;

  bool isUsable(DateTime now) {
    return expiresAt.difference(now) > const Duration(minutes: 2);
  }
}

class TurnCredentialDiagnostics {
  const TurnCredentialDiagnostics({
    this.brokerConfigured = false,
    this.provider = 'none',
    this.turnUrlCount = 0,
    this.expiresAt,
    this.lastError,
    this.errorCode,
  });

  factory TurnCredentialDiagnostics.fromIceServers({
    required bool brokerConfigured,
    required String provider,
    required List<Map<String, dynamic>> iceServers,
    DateTime? expiresAt,
  }) {
    return TurnCredentialDiagnostics(
      brokerConfigured: brokerConfigured,
      provider: provider.trim().isEmpty ? 'unknown' : provider.trim(),
      turnUrlCount: _turnUrlCount(iceServers),
      expiresAt: expiresAt,
    );
  }

  final bool brokerConfigured;
  final String provider;
  final int turnUrlCount;
  final DateTime? expiresAt;
  final String? lastError;
  final TurnCredentialErrorCode? errorCode;
}

enum TurnCredentialErrorCode {
  brokerUnreachable('broker-unreachable'),
  brokerAuthFailed('broker-auth-failed'),
  brokerRateLimited('broker-rate-limited'),
  brokerRejected('broker-rejected'),
  invalidBrokerResponse('invalid-broker-response'),
  relayUnavailable('relay-unavailable');

  const TurnCredentialErrorCode(this.label);

  final String label;
}

class TurnCredentialException implements Exception {
  const TurnCredentialException(this.code, this.message);

  factory TurnCredentialException.fromStatus(int statusCode) {
    if (statusCode == 401 || statusCode == 403) {
      return const TurnCredentialException(
        TurnCredentialErrorCode.brokerAuthFailed,
        'Relay authorization failed. Sign in again.',
      );
    }
    if (statusCode == 429) {
      return const TurnCredentialException(
        TurnCredentialErrorCode.brokerRateLimited,
        'Relay is rate limited. Try again later.',
      );
    }
    if (statusCode >= 500) {
      return const TurnCredentialException(
        TurnCredentialErrorCode.brokerUnreachable,
        'Relay unavailable. Direct connection only.',
      );
    }
    return const TurnCredentialException(
      TurnCredentialErrorCode.brokerRejected,
      'Relay request was rejected.',
    );
  }

  final TurnCredentialErrorCode code;
  final String message;

  @override
  String toString() => message;
}

Future<String?> _defaultFirebaseIdTokenProvider() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return null;
  }
  return user.getIdToken(false);
}

DateTime _parseExpiresAt(Map<String, dynamic> decoded, DateTime now) {
  final rawExpiresAt = decoded['expiresAt'];
  if (rawExpiresAt is num) {
    final value = rawExpiresAt.toInt();
    final millis = value < 10000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
  if (rawExpiresAt is String) {
    final parsed = DateTime.tryParse(rawExpiresAt);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  final ttlSeconds = (decoded['ttlSeconds'] as num?)?.toInt() ?? 1200;
  return now.toUtc().add(Duration(seconds: ttlSeconds));
}

bool _hasIceUrls(Map<String, dynamic> server) => _urls(server).isNotEmpty;

bool _hasTurnUrl(Map<String, dynamic> server) => _urls(server).any(_isTurnUrl);

bool _isStunUrl(String url) => url.trim().toLowerCase().startsWith('stun:');

bool _isTurnUrl(String url) {
  final normalized = url.trim().toLowerCase();
  return normalized.startsWith('turn:') || normalized.startsWith('turns:');
}

Iterable<String> _urls(Map<String, dynamic> server) sync* {
  final urls = server['urls'];
  if (urls is Iterable) {
    for (final url in urls) {
      yield url.toString();
    }
    return;
  }
  if (urls != null) {
    yield urls.toString();
  }
}

List<Map<String, dynamic>> _cloneIceServers(
  List<Map<String, dynamic>> servers,
) {
  return servers.map(_cloneIceServer).toList(growable: false);
}

List<Map<String, dynamic>> _uniqueIceServers(
  Iterable<Map<String, dynamic>> servers,
) {
  final seen = <String>{};
  final unique = <Map<String, dynamic>>[];
  for (final server in servers) {
    final key = jsonEncode(_cloneIceServer(server));
    if (seen.add(key)) {
      unique.add(_cloneIceServer(server));
    }
  }
  return unique;
}

Map<String, dynamic> _cloneIceServer(Map<String, dynamic> server) {
  return Map<String, dynamic>.fromEntries(
    server.entries.map((MapEntry<String, dynamic> entry) {
      final value = entry.value;
      return MapEntry<String, dynamic>(
        entry.key,
        value is List ? List<dynamic>.from(value) : value,
      );
    }),
  );
}

int _turnUrlCount(List<Map<String, dynamic>> iceServers) {
  var count = 0;
  for (final server in iceServers) {
    count += _urls(server).where(_isTurnUrl).length;
  }
  return count;
}

({TurnCredentialErrorCode code, String message}) _turnBrokerError(
  Object error,
) {
  if (error is TurnCredentialException) {
    return (code: error.code, message: error.message);
  }
  if (error is TimeoutException || error is SocketException) {
    return (
      code: TurnCredentialErrorCode.brokerUnreachable,
      message: 'Relay unavailable. Direct connection only.',
    );
  }
  if (error is FormatException) {
    return (
      code: TurnCredentialErrorCode.invalidBrokerResponse,
      message: 'Relay configuration is invalid.',
    );
  }
  final raw = error.toString().trim();
  if (raw.isEmpty) {
    return (
      code: TurnCredentialErrorCode.brokerUnreachable,
      message: 'Relay unavailable. Direct connection only.',
    );
  }
  const prefixes = <String>['Exception: ', 'HttpException: ', 'StateError: '];
  var normalized = raw;
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) {
      normalized = normalized.substring(prefix.length).trim();
      break;
    }
  }
  final lower = normalized.toLowerCase();
  if (lower.contains('401') ||
      lower.contains('403') ||
      lower.contains('missing_auth') ||
      lower.contains('invalid_auth')) {
    return (
      code: TurnCredentialErrorCode.brokerAuthFailed,
      message: 'Relay authorization failed. Sign in again.',
    );
  }
  if (lower.contains('429') || lower.contains('rate_limited')) {
    return (
      code: TurnCredentialErrorCode.brokerRateLimited,
      message: 'Relay is rate limited. Try again later.',
    );
  }
  if (lower.contains('503') ||
      lower.contains('502') ||
      lower.contains('500') ||
      lower.contains('timeout') ||
      lower.contains('unreachable')) {
    return (
      code: TurnCredentialErrorCode.brokerUnreachable,
      message: 'Relay unavailable. Direct connection only.',
    );
  }
  return (
    code: TurnCredentialErrorCode.brokerRejected,
    message: 'Relay request was rejected.',
  );
}

String _sentence(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'TURN broker unreachable.';
  }
  if (trimmed.endsWith('.') || trimmed.endsWith('!') || trimmed.endsWith('?')) {
    return trimmed;
  }
  return '$trimmed.';
}

const _defaultStunPool = <Map<String, dynamic>>[
  <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun1.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun2.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun3.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun4.l.google.com:19302'},
  <String, dynamic>{'urls': 'stun:stun.services.mozilla.com:3478'},
  <String, dynamic>{'urls': 'stun:stun.nextcloud.com:3478'},
];

const _experimentalRelayServersStatic = <Map<String, dynamic>>[
  <String, dynamic>{
    'urls': 'turn:freestun.net:3478',
    'username': 'free',
    'credential': 'free',
  },
];
