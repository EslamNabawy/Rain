import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:peer_core/peer_core.dart'
    show PeerIceTransportPolicy, TurnReadiness, TurnReadinessResult;

class TurnCredentialService {
  TurnCredentialService({
    required List<Map<String, dynamic>> baseIceServers,
    required String brokerUrl,
    Future<String?> Function()? idTokenProvider,
    HttpClient? httpClient,
    DateTime Function()? now,
  }) : _baseIceServers = _windowsReleaseSafeIceServers(
         _cloneIceServers(baseIceServers),
       ),
       _brokerUrl = brokerUrl.trim(),
       _idTokenProvider = idTokenProvider ?? _defaultFirebaseIdTokenProvider,
       _httpClient = httpClient ?? HttpClient(),
       _now = now ?? DateTime.now;

  final List<Map<String, dynamic>> _baseIceServers;
  final String _brokerUrl;
  final Future<String?> Function() _idTokenProvider;
  final HttpClient _httpClient;
  final DateTime Function() _now;

  _TurnCredentialCache? _cache;
  TurnReadinessResult _lastReadiness = const TurnReadinessResult(
    readiness: TurnReadiness.notRequiredForCurrentPolicy,
    hasRelayServer: false,
  );

  TurnReadinessResult get lastReadiness => _lastReadiness;

  Future<List<Map<String, dynamic>>> iceServers() async {
    if (_brokerUrl.isEmpty) {
      final servers = _cloneIceServers(_baseIceServers);
      _lastReadiness = _readinessForServers(
        servers,
        PeerIceTransportPolicy.all,
      );
      return servers;
    }
    final cached = _cache;
    if (cached != null && cached.isUsable(_now())) {
      final servers = _mergeIceServers(cached.iceServers);
      _lastReadiness = _readinessForServers(
        servers,
        PeerIceTransportPolicy.all,
      );
      return servers;
    }
    try {
      final fetched = await _fetchBrokerCredentials();
      _cache = fetched;
      final servers = _mergeIceServers(fetched.iceServers);
      _lastReadiness = _readinessForServers(
        servers,
        PeerIceTransportPolicy.all,
      );
      return servers;
    } catch (error) {
      final servers = _cloneIceServers(_baseIceServers);
      _lastReadiness = _readinessForServers(
        servers,
        PeerIceTransportPolicy.all,
        error: error,
      );
      return servers;
    }
  }

  Future<TurnReadinessResult> turnReadiness(
    PeerIceTransportPolicy policy,
  ) async {
    if (_brokerUrl.isEmpty) {
      return _readinessForServers(_baseIceServers, policy);
    }
    final cached = _cache;
    if (cached != null && cached.isUsable(_now())) {
      return _readinessForServers(_mergeIceServers(cached.iceServers), policy);
    }
    try {
      final fetched = await _fetchBrokerCredentials();
      _cache = fetched;
      return _readinessForServers(_mergeIceServers(fetched.iceServers), policy);
    } catch (error) {
      return _readinessForServers(_baseIceServers, policy, error: error);
    }
  }

  Future<_TurnCredentialCache> _fetchBrokerCredentials() async {
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
    final rawIceServers = decoded['iceServers'];
    if (rawIceServers is! List) {
      throw const FormatException(
        'TURN broker response is missing iceServers.',
      );
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
    return _TurnCredentialCache(
      iceServers: iceServers,
      expiresAt: _parseExpiresAt(decoded, _now()),
    );
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
    return _windowsReleaseSafeIceServers(
      next.isEmpty ? _cloneIceServers(_baseIceServers) : next,
    );
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}

Future<String?> _defaultFirebaseIdTokenProvider() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return null;
  }
  return user.getIdToken(false);
}

class _TurnCredentialCache {
  const _TurnCredentialCache({
    required this.iceServers,
    required this.expiresAt,
  });

  final List<Map<String, dynamic>> iceServers;
  final DateTime expiresAt;

  bool isUsable(DateTime now) {
    return expiresAt.difference(now) > const Duration(minutes: 2);
  }
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

TurnReadinessResult _readinessForServers(
  List<Map<String, dynamic>> servers,
  PeerIceTransportPolicy policy, {
  Object? error,
}) {
  final hasRelay = servers.any(_hasTurnUrl);
  if (hasRelay) {
    return TurnReadinessResult(
      readiness: TurnReadiness.available,
      hasRelayServer: true,
      error: error,
    );
  }
  if (policy != PeerIceTransportPolicy.relayOnly) {
    return TurnReadinessResult(
      readiness: error == null
          ? TurnReadiness.notRequiredForCurrentPolicy
          : TurnReadiness.unavailableBrokerFailed,
      hasRelayServer: false,
      error: error,
    );
  }
  return TurnReadinessResult(
    readiness: error == null
        ? TurnReadiness.unavailableNoRelayServer
        : TurnReadiness.unavailableBrokerFailed,
    hasRelayServer: false,
    error: error,
  );
}

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

List<Map<String, dynamic>> _windowsReleaseSafeIceServers(
  List<Map<String, dynamic>> servers,
) {
  if (!kReleaseMode || !Platform.isWindows) {
    return _cloneIceServers(servers);
  }

  String? selectedStunUrl;
  final relayServers = <Map<String, dynamic>>[];
  for (final server in servers) {
    final turnUrls = <String>[];
    for (final url in _urls(server)) {
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
