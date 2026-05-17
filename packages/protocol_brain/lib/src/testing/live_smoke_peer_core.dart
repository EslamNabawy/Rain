import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

PeerCore createLiveSmokePeerCore() => _LiveSmokePeerCore();

class _LiveSmokePeerCore implements PeerCore {
  _LiveSmokePeerCore({
    Duration connectDelay = const Duration(milliseconds: 800),
  }) : _connectDelay = connectDelay;

  final Duration _connectDelay;

  final StreamController<RTCIceCandidate> _iceController =
      StreamController<RTCIceCandidate>.broadcast();
  final StreamController<void> _connectedController =
      StreamController<void>.broadcast();
  final StreamController<void> _disconnectedController =
      StreamController<void>.broadcast();
  final StreamController<PeerMessage> _messageController =
      StreamController<PeerMessage>.broadcast();
  final StreamController<String> _channelOpenController =
      StreamController<String>.broadcast();
  final StreamController<String> _channelCloseController =
      StreamController<String>.broadcast();
  final StreamController<PeerState> _stateController =
      StreamController<PeerState>.broadcast();

  Timer? _connectTimer;
  PeerState _state = PeerState.idle;
  bool _connectedFired = false;

  @override
  Stream<RTCIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<void> get onConnected => _connectedController.stream;

  @override
  Stream<void> get onDisconnected => _disconnectedController.stream;

  @override
  Stream<PeerMessage> get onMessage => _messageController.stream;

  @override
  Stream<String> get onChannelOpen => _channelOpenController.stream;

  @override
  Stream<String> get onChannelClose => _channelCloseController.stream;

  @override
  Stream<PeerState> get onStateChange => _stateController.stream;

  @override
  PeerState get state => _state;

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {}

  @override
  Future<void> closeChannel(String channelId) async {}

  @override
  Future<int> bufferedAmount(String channelId) async => 0;

  @override
  bool isChannelOpen(String channelId) => true;

  @override
  Future<RTCSessionDescription> createOffer() async {
    _transition(PeerState.offering);
    return RTCSessionDescription('fake-offer', 'offer');
  }

  @override
  Future<void> destroy() async {
    _connectTimer?.cancel();
    _connectTimer = null;
    if (_state != PeerState.idle) {
      _transition(PeerState.idle);
    }
  }

  @override
  List<RTCIceCandidate> getLocalCandidates() => const <RTCIceCandidate>[];

  @override
  Future<void> init(PeerConfig config) async {
    _connectedFired = false;
    _transition(PeerState.ready);
  }

  @override
  Future<void> openChannel(
    String channelId, {
    RTCDataChannelInit? opts,
  }) async {}

  @override
  void send(String channelId, dynamic data) {}

  @override
  Future<void> setAnswer(RTCSessionDescription answer) async {
    _transition(PeerState.connecting);
    _connectTimer?.cancel();
    _connectTimer = Timer(_connectDelay, () {
      if (_connectedFired || _state == PeerState.idle) {
        return;
      }
      _transition(PeerState.connected);
      _connectedFired = true;
      _connectedController.add(null);
    });
  }

  @override
  Future<RTCSessionDescription> setOffer(RTCSessionDescription offer) async {
    _transition(PeerState.answering);
    return RTCSessionDescription('fake-answer', 'answer');
  }

  void _transition(PeerState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    _stateController.add(next);
  }
}
