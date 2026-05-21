part of 'protocol_brain_impl.dart';

typedef PeerConfigProvider =
    Future<PeerConfig> Function(PeerIceTransportPolicy policy);

String _normalizedPeerId(String peerId) => peerId.trim().toLowerCase();

String roomId(String a, String b) {
  final sorted = <String>[_normalizedPeerId(a), _normalizedPeerId(b)]..sort();
  return sorted.join(':');
}

const Duration _routeRefreshDelay = Duration(milliseconds: 850);
