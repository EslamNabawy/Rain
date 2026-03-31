import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'platform_bridge.dart';

enum PeerState {
  idle,
  ready,
  offering,
  answering,
  connecting,
  connected,
  reconnecting,
  failed,
}

final class PeerChannels {
  static const chat = 'rain.chat';
  static const control = 'rain.ctrl';
  static const file = 'rain.file';

  const PeerChannels._();
}

class PeerConfig {
  const PeerConfig({
    required this.iceServers,
    required this.platform,
    this.ordered = true,
    this.maxRetransmits,
  });

  final List<Map<String, dynamic>> iceServers;
  final PlatformBridge platform;
  final bool ordered;
  final int? maxRetransmits;

  Map<String, dynamic> toRtcConfiguration() {
    return <String, dynamic>{'iceServers': iceServers};
  }

  RTCDataChannelInit defaultChannelOptions() {
    final options = RTCDataChannelInit()..ordered = ordered;
    if (maxRetransmits != null) {
      options.maxRetransmits = maxRetransmits!;
    }
    return options;
  }
}

class PeerMessage {
  const PeerMessage({
    required this.channelId,
    required this.data,
    required this.receivedAt,
    this.peerId,
  });

  final String channelId;
  final Object? data;
  final DateTime receivedAt;
  final String? peerId;

  String? get text => data is String ? data! as String : null;
  Uint8List? get binary => data is Uint8List ? data! as Uint8List : null;
}

abstract class PeerCore {
  Future<void> init(PeerConfig config);
  Future<void> destroy();

  Future<RTCSessionDescription> createOffer();
  Future<RTCSessionDescription> setOffer(RTCSessionDescription offer);
  Future<void> setAnswer(RTCSessionDescription answer);
  Future<void> addIceCandidate(RTCIceCandidate candidate);
  List<RTCIceCandidate> getLocalCandidates();

  void send(String channelId, dynamic data);
  Future<void> openChannel(String channelId, {RTCDataChannelInit? opts});
  Future<void> closeChannel(String channelId);

  Stream<RTCIceCandidate> get onIceCandidate;
  Stream<void> get onConnected;
  Stream<void> get onDisconnected;
  Stream<PeerMessage> get onMessage;
  Stream<String> get onChannelOpen;
  Stream<String> get onChannelClose;
  Stream<PeerState> get onStateChange;

  PeerState get state;
}

typedef PeerCoreFactory = PeerCore Function();
