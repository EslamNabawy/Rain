/// # ice_candidate_policy.dart — protocol_brain package
///
/// Shared peer configuration provider and room ID canonicalization logic used by ProtocolBrainImpl. Defines PeerConfigProvider typedef, normalizes peer IDs, generates deterministic room IDs, and provides route-refresh delay constants.
///
/// **Key types:** PeerConfigProvider (typedef), roomId(), _normalizedPeerId()
///
/// **Package:** protocol_brain
///
/// **Depends on:** protocol_brain_impl.dart (part), peer_core
part of 'protocol_brain_impl.dart';

typedef PeerConfigProvider =
    Future<PeerConfig> Function(PeerIceTransportPolicy policy);

String _normalizedPeerId(String peerId) => peerId.trim().toLowerCase();

String roomId(String a, String b) {
  final sorted = <String>[_normalizedPeerId(a), _normalizedPeerId(b)]..sort();
  return sorted.join(':');
}

const Duration _routeRefreshDelay = Duration(milliseconds: 850);
