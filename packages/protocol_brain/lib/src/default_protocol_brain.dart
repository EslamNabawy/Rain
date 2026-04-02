import 'package:peer_core/peer_core.dart';

import '../adapters/signaling_adapter.dart';
import 'connection_memory.dart';
import 'protocol_brain_impl.dart';
import 'session_manager.dart';

ProtocolBrain createDefaultProtocolBrain({
  required String selfUsername,
  required SignalingAdapter adapter,
  required List<Map<String, dynamic>> iceServers,
  required ConnectionMemoryStore connectionMemoryStore,
  PlatformBridge? platformBridge,
  PeerCoreFactory? peerFactory,
  bool ordered = true,
  int? maxRetransmits,
}) {
  return ProtocolBrainImpl(
    selfUsername: selfUsername,
    adapter: adapter,
    peerConfig: PeerConfig(
      iceServers: iceServers,
      platform: platformBridge ?? FlutterWebRTCBridge(),
      ordered: ordered,
      maxRetransmits: maxRetransmits,
    ),
    peerFactory: peerFactory ?? DefaultPeerCore.new,
    connectionMemoryStore: connectionMemoryStore,
  );
}
