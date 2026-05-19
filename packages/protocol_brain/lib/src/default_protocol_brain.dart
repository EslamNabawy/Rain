import 'package:peer_core/peer_core.dart';

import '../adapters/signaling_adapter.dart';
import 'connection_memory.dart';
import 'ice_attempt.dart';
import 'protocol_brain_impl.dart';
import 'session_manager.dart';

ProtocolBrain createDefaultProtocolBrain({
  required String selfUsername,
  required SignalingAdapter adapter,
  required List<Map<String, dynamic>> iceServers,
  required ConnectionMemoryStore connectionMemoryStore,
  PlatformBridge? platformBridge,
  PeerCoreFactory? peerFactory,
  PeerConfigProvider? peerConfigProvider,
  IceAttemptConfigProvider? iceAttemptConfigProvider,
  Future<List<Map<String, dynamic>>> Function(IceAttemptDescriptor attempt)?
  iceAttemptServersProvider,
  IceAttemptResultRecorder? iceAttemptResultRecorder,
  Future<List<Map<String, dynamic>>> Function(PeerIceTransportPolicy policy)?
  iceServersProvider,
  bool enableExperimentalRelay = false,
  bool ordered = true,
  int? maxRetransmits,
}) {
  final bridge = platformBridge ?? FlutterWebRTCBridge();
  return ProtocolBrainImpl(
    selfUsername: selfUsername,
    adapter: adapter,
    peerConfig: PeerConfig(
      iceServers: iceServers,
      platform: bridge,
      ordered: ordered,
      maxRetransmits: maxRetransmits,
    ),
    iceAttemptResultRecorder: iceAttemptResultRecorder,
    iceAttemptConfigProvider:
        iceAttemptConfigProvider ??
        (iceAttemptServersProvider == null
            ? null
            : (IceAttemptDescriptor attempt) async {
                return PeerConfig(
                  iceServers: await iceAttemptServersProvider(attempt),
                  platform: bridge,
                  ordered: ordered,
                  maxRetransmits: maxRetransmits,
                  iceTransportPolicy: attempt.policy,
                );
              }),
    peerConfigProvider:
        peerConfigProvider ??
        (iceServersProvider == null
            ? null
            : (PeerIceTransportPolicy policy) async {
                return PeerConfig(
                  iceServers: await iceServersProvider(policy),
                  platform: bridge,
                  ordered: ordered,
                  maxRetransmits: maxRetransmits,
                  iceTransportPolicy: policy,
                );
              }),
    peerFactory: peerFactory ?? DefaultPeerCore.new,
    connectionMemoryStore: connectionMemoryStore,
    enableExperimentalRelay: enableExperimentalRelay,
  );
}
