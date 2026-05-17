import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

typedef TurnCredentialFetcher = Future<TurnCredentialFetchResult> Function();

class TurnCredentialService {
  TurnCredentialService({
    required List<Map<String, dynamic>> baseIceServers,
    required String brokerUrl,
    Future<String?> Function()? idTokenProvider,
    HttpClient? httpClient,
    DateTime Function()? now,
    TurnCredentialFetcher? credentialFetcher,
  }) : _baseIceServers = _cloneIceServers(baseIceServers),
       _brokerUrl = brokerUrl.trim(),
       _idTokenProvider = idTokenProvider ?? _defaultFirebaseIdTokenProvider,
       _httpClient = httpClient ?? HttpClient(),
       _now = now ?? DateTime.now,
       _credentialFetcher = credentialFetcher;

  final List<Map<String, dynamic>> _baseIceServers;
  final String _brokerUrl;
  final Future<String?> Function() _idTokenProvider;
  final HttpClient _httpClient;
  final DateTime Function() _now;
  final TurnCredentialFetcher? _credentialFetcher;

  TurnCredentialFetchResult? _cache;
  TurnCredentialDiagnostics _diagnostics = const TurnCredentialDiagnostics();

  TurnCredentialDiagnostics get diagnostics => _diagnostics;

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
        lastError: brokerError,
      );
      if (requireTurn) {
        throw StateError(
          '${_sentence(brokerError)} Relay fallback unavailable.',
        );
      }
      return _cloneIceServers(_baseIceServers);
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
      throw HttpException('TURN broker returned ${response.statusCode}');
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

String _turnBrokerError(Object error) {
  if (error is TimeoutException || error is SocketException) {
    return 'TURN broker unreachable.';
  }
  final raw = error.toString().trim();
  if (raw.isEmpty) {
    return 'TURN broker unreachable.';
  }
  const prefixes = <String>['Exception: ', 'HttpException: ', 'StateError: '];
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }
  }
  return raw;
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
