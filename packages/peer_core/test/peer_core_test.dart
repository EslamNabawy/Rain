import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

void main() {
  test('peer state machine enforces happy path transitions', () {
    final machine = PeerStateMachine();

    expect(machine.state, PeerState.idle);
    machine.transition(PeerState.ready);
    machine.transition(PeerState.offering);
    machine.transition(PeerState.connecting);
    machine.transition(PeerState.connected);
    machine.transition(PeerState.reconnecting);
    machine.transition(PeerState.failed);
    machine.transition(PeerState.idle);

    expect(machine.state, PeerState.idle);
  });

  test('peer state machine rejects invalid transitions', () {
    final machine = PeerStateMachine();

    expect(() => machine.transition(PeerState.connected), throwsStateError);

    machine.transition(PeerState.ready);
    machine.transition(PeerState.offering);
    machine.transition(PeerState.connecting);

    expect(() => machine.transition(PeerState.failed), throwsStateError);
  });

  test(
    'default peer waits for chat and control channels before connected',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();
      final connectedEvents = <void>[];
      final subscription = peer.onConnected.listen(connectedEvents.add);

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));

      platform.connection.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await pumpEventQueue();

      expect(peer.state, PeerState.connecting);
      expect(connectedEvents, isEmpty);

      platform.channel(PeerChannels.chat).emitOpen();
      await pumpEventQueue();

      expect(peer.state, PeerState.connecting);
      expect(connectedEvents, isEmpty);

      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
      expect(connectedEvents, hasLength(1));

      await subscription.cancel();
    },
  );

  test('default peer rejects chat send before data channel opens', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));

    expect(
      () => peer.send(PeerChannels.chat, 'too soon'),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'default peer treats open chat and control channels as connected',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));

      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
    },
  );

  test(
    'default peer recovers from transient disconnect without a rebuild',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();
      final connectedEvents = <void>[];
      final disconnectedEvents = <void>[];
      final connectedSubscription = peer.onConnected.listen(
        connectedEvents.add,
      );
      final disconnectedSubscription = peer.onDisconnected.listen(
        disconnectedEvents.add,
      );

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));

      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      platform.connection.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
      );
      await pumpEventQueue();

      expect(peer.state, PeerState.reconnecting);
      expect(disconnectedEvents, hasLength(1));

      platform.connection.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
      expect(connectedEvents, hasLength(2));

      await connectedSubscription.cancel();
      await disconnectedSubscription.cancel();
    },
  );

  test(
    'default peer keeps session connected when optional channel closes',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();
      final disconnectedEvents = <void>[];
      final disconnectedSubscription = peer.onDisconnected.listen(
        disconnectedEvents.add,
      );

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      await peer.openChannel(PeerChannels.file);
      platform.channel(PeerChannels.file).emitOpen();
      await pumpEventQueue();
      await peer.closeChannel(PeerChannels.file);
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
      expect(disconnectedEvents, isEmpty);

      await disconnectedSubscription.cancel();
    },
  );
}

class _FakePlatformBridge implements PlatformBridge {
  final _FakeRtcPeerConnection connection = _FakeRtcPeerConnection();
  final Map<String, _FakeRtcDataChannel> channels =
      <String, _FakeRtcDataChannel>{};

  _FakeRtcDataChannel channel(String label) => channels[label]!;

  @override
  Future<RTCPeerConnection> createPeerConnection(Map<String, dynamic> config) {
    return Future<RTCPeerConnection>.value(connection);
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    RTCPeerConnection pc,
    String label,
    RTCDataChannelInit opts,
  ) async {
    final channel = _FakeRtcDataChannel(label);
    channels[label] = channel;
    return channel;
  }

  @override
  StorageBackend getLocalStorage() => MemoryStorageBackend();
}

class _FakeRtcPeerConnection extends Fake implements RTCPeerConnection {
  RTCPeerConnectionState? _connectionState =
      RTCPeerConnectionState.RTCPeerConnectionStateNew;

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCDataChannel channel)? onDataChannel;

  @override
  RTCPeerConnectionState? get connectionState => _connectionState;

  void emitConnectionState(RTCPeerConnectionState state) {
    _connectionState = state;
    onConnectionState?.call(state);
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    return RTCSessionDescription('offer-sdp', 'offer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {}

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {}

  @override
  Future<void> close() async {}
}

class _FakeRtcDataChannel extends Fake implements RTCDataChannel {
  _FakeRtcDataChannel(this._label);

  final String _label;
  RTCDataChannelState? _state = RTCDataChannelState.RTCDataChannelConnecting;
  final List<RTCDataChannelMessage> sentMessages = <RTCDataChannelMessage>[];

  @override
  Function(RTCDataChannelState state)? onDataChannelState;

  @override
  Function(RTCDataChannelMessage data)? onMessage;

  @override
  RTCDataChannelState? get state => _state;

  @override
  String? get label => _label;

  @override
  int? get id => _label.hashCode;

  @override
  int? get bufferedAmount => 0;

  @override
  int? bufferedAmountLowThreshold;

  void emitOpen() {
    _state = RTCDataChannelState.RTCDataChannelOpen;
    onDataChannelState?.call(_state!);
  }

  @override
  Future<void> send(RTCDataChannelMessage message) async {
    sentMessages.add(message);
  }

  @override
  Future<void> close() async {
    _state = RTCDataChannelState.RTCDataChannelClosed;
    onDataChannelState?.call(_state!);
  }
}
