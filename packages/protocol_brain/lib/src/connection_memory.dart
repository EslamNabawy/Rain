import 'package:flutter_webrtc/flutter_webrtc.dart';

const maxCacheFailures = 3;
const cacheExpiryMs = 24 * 60 * 60 * 1000;
const retryDelays = <int>[0, 2000, 5000, 15000, 30000];
const maxRetries = 5;
const cachedIceAttempts = 2;

class ConnectionMemory {
  const ConnectionMemory({
    required this.peerId,
    required this.lastConnectedAt,
    required this.cachedIce,
    required this.fingerprint,
    required this.consecutiveFailures,
  });

  final String peerId;
  final int lastConnectedAt;
  final List<RTCIceCandidate> cachedIce;
  final String fingerprint;
  final int consecutiveFailures;

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch - lastConnectedAt > cacheExpiryMs;

  bool get isUsable =>
      !isExpired && consecutiveFailures < maxCacheFailures && cachedIce.isNotEmpty;

  ConnectionMemory copyWith({
    int? lastConnectedAt,
    List<RTCIceCandidate>? cachedIce,
    String? fingerprint,
    int? consecutiveFailures,
  }) {
    return ConnectionMemory(
      peerId: peerId,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      cachedIce: cachedIce ?? this.cachedIce,
      fingerprint: fingerprint ?? this.fingerprint,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    );
  }
}

abstract class ConnectionMemoryStore {
  Future<ConnectionMemory?> read(String peerId);
  Future<void> write(ConnectionMemory memory);
  Future<void> delete(String peerId);
}

