/// # default_protocol_brain.dart — protocol_brain package
///
/// Factory function createDefaultProtocolBrain that wires up and returns a fully configured ProtocolBrainImpl instance given a username, signaling adapter, ICE servers, and optional platform/peer overrides. This is the primary entry point for consumers of the protocol_brain package.
///
/// **Key types:** createDefaultProtocolBrain (function)
///
/// **Package:** protocol_brain
///
/// **Depends on:** peer_core, signaling_adapter, connection_memory, protocol_brain_impl, session_manager
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
  PeerConfigProvider? peerConfigProvider,
  Future<List<Map<String, dynamic>>> Function()? iceServersProvider,
  Future<String?> Function()? selectedAudioInputDeviceIdProvider,
  Future<String?> Function()? selectedVideoInputDeviceIdProvider,
  Future<CallMediaProcessingConfig> Function()?
  callMediaProcessingConfigProvider,
  PeerDebugEventSink? debugEventSink,
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
      selectedAudioInputDeviceIdProvider: selectedAudioInputDeviceIdProvider,
      selectedVideoInputDeviceIdProvider: selectedVideoInputDeviceIdProvider,
      callMediaProcessingConfigProvider: callMediaProcessingConfigProvider,
      debugEventSink: debugEventSink,
    ),
    peerConfigProvider:
        peerConfigProvider ??
        (iceServersProvider == null
            ? null
            : (PeerIceTransportPolicy policy) async {
                return PeerConfig(
                  iceServers: await iceServersProvider(),
                  platform: bridge,
                  ordered: ordered,
                  maxRetransmits: maxRetransmits,
                  iceTransportPolicy: policy,
                  selectedAudioInputDeviceIdProvider:
                      selectedAudioInputDeviceIdProvider,
                  selectedVideoInputDeviceIdProvider:
                      selectedVideoInputDeviceIdProvider,
                  callMediaProcessingConfigProvider:
                      callMediaProcessingConfigProvider,
                  debugEventSink: debugEventSink,
                );
              }),
    peerFactory: peerFactory ?? DefaultPeerCore.new,
    connectionMemoryStore: connectionMemoryStore,
  );
}
