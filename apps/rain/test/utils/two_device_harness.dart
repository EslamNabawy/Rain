import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain_core/rain_core.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'firebase_emulator_signaling_adapter.dart';

class TwoDeviceHarness {
  Future<bool> run() async {
    final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final alice = 'alice$runId';
    final bob = 'bob$runId';

    const iceServers = defaultIceServers;
    final peerPair = _LinkedPeerPair();

    final aliceDb = RainDatabase(NativeDatabase.memory());
    final bobDb = RainDatabase(NativeDatabase.memory());
    final aliceAdapter = FirebaseEmulatorSignalingAdapter();
    final bobAdapter = FirebaseEmulatorSignalingAdapter();

    try {
      await aliceAdapter.register(alice, 'alicepw');
      await bobAdapter.register(bob, 'bob123');
      await aliceAdapter.login(alice, 'alicepw');
      await bobAdapter.login(bob, 'bob123');

      final aliceBrain = createDefaultProtocolBrain(
        selfUsername: alice,
        adapter: aliceAdapter,
        iceServers: iceServers,
        connectionMemoryStore: DriftConnectionMemoryStore(aliceDb),
        peerFactory: () => peerPair.alice,
      );
      final bobBrain = createDefaultProtocolBrain(
        selfUsername: bob,
        adapter: bobAdapter,
        iceServers: iceServers,
        connectionMemoryStore: DriftConnectionMemoryStore(bobDb),
        peerFactory: () => peerPair.bob,
      );

      final aliceIdentity = RainIdentity(
        username: alice,
        displayName: 'Alice',
        createdAt: 0,
        gender: null,
      );
      final bobIdentity = RainIdentity(
        username: bob,
        displayName: 'Bob',
        createdAt: 0,
        gender: null,
      );

      final runtimeAlice = RainRuntimeController(
        selfIdentity: aliceIdentity,
        adapter: aliceAdapter,
        brain: aliceBrain,
        database: aliceDb,
        friendStore: FriendStore(aliceDb),
        messageStore: MessageStore(aliceDb),
        offlineQueueStore: OfflineQueueStore(aliceDb),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(aliceDb),
          offlineQueueStore: OfflineQueueStore(aliceDb),
        ),
      );

      final runtimeBob = RainRuntimeController(
        selfIdentity: bobIdentity,
        adapter: bobAdapter,
        brain: bobBrain,
        database: bobDb,
        friendStore: FriendStore(bobDb),
        messageStore: MessageStore(bobDb),
        offlineQueueStore: OfflineQueueStore(bobDb),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(bobDb),
          offlineQueueStore: OfflineQueueStore(bobDb),
        ),
      );

      await runtimeAlice.start();
      await runtimeBob.start();

      await FriendStore(aliceDb).upsertFriend(
        username: bob,
        displayName: 'Bob',
        state: FriendState.friend,
        addedAt: 0,
      );
      await FriendStore(bobDb).upsertFriend(
        username: alice,
        displayName: 'Alice',
        state: FriendState.friend,
        addedAt: 0,
      );

      await Future.wait(<Future<void>>[
        runtimeAlice.connectPeer(
          bob,
          waitForConnected: true,
          connectionTimeout: const Duration(seconds: 10),
        ),
        runtimeBob.connectPeer(
          alice,
          waitForConnected: true,
          connectionTimeout: const Duration(seconds: 10),
        ),
      ]);

      final aSess = aliceBrain.getSession(bob);
      final bSess = bobBrain.getSession(alice);
      if (aSess?.state != SessionState.connected ||
          bSess?.state != SessionState.connected) {
        return false;
      }

      await runtimeAlice.sendMessage(bob, 'echo-from-alice');
      await Future.delayed(const Duration(milliseconds: 500));

      final bobMessages = await bobDb.select(bobDb.messages).get();
      return bobMessages.any(
        (m) =>
            m.peerId == alice &&
            m.content == 'echo-from-alice' &&
            m.isOutgoing == false,
      );
    } finally {
      await aliceAdapter.dispose();
      await bobAdapter.dispose();
      await aliceDb.close();
      await bobDb.close();
    }
  }
}

class _LinkedPeerPair {
  _LinkedPeerPair() {
    alice.partner = bob;
    bob.partner = alice;
  }

  late final _LinkedPeerCore alice = _LinkedPeerCore(
    name: 'alice',
    connectPair: _connect,
  );
  late final _LinkedPeerCore bob = _LinkedPeerCore(
    name: 'bob',
    connectPair: _connect,
  );

  void _connect() {
    alice.emitConnected();
    bob.emitConnected();
  }
}

class _LinkedPeerCore implements PeerCore {
  _LinkedPeerCore({required this.name, required this.connectPair});

  final String name;
  final void Function() connectPair;
  _LinkedPeerCore? partner;
  PeerState _state = PeerState.idle;
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

  @override
  Future<void> init(PeerConfig config) async {
    _state = PeerState.ready;
    _stateController.add(_state);
  }

  @override
  Future<void> destroy() async {
    _state = PeerState.idle;
    _stateController.add(_state);
  }

  @override
  Future<RTCSessionDescription> createOffer() async {
    _state = PeerState.offering;
    _stateController.add(_state);
    return RTCSessionDescription('offer-sdp-$name', 'offer');
  }

  @override
  Future<RTCSessionDescription> setOffer(RTCSessionDescription offer) async {
    _state = PeerState.answering;
    _stateController.add(_state);
    return RTCSessionDescription('answer-sdp-$name', 'answer');
  }

  @override
  Future<void> setAnswer(RTCSessionDescription answer) async {
    _state = PeerState.connecting;
    _stateController.add(_state);
    connectPair();
  }

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {}

  @override
  List<RTCIceCandidate> getLocalCandidates() => const <RTCIceCandidate>[];

  @override
  void send(String channelId, dynamic data) {
    final target = partner;
    if (target == null || _state != PeerState.connected) {
      throw StateError('Linked peer is not connected.');
    }
    target._messageController.add(
      PeerMessage(channelId: channelId, data: data, receivedAt: DateTime.now()),
    );
  }

  @override
  Future<void> openChannel(String channelId, {RTCDataChannelInit? opts}) async {
    _channelOpenController.add(channelId);
  }

  @override
  Future<void> closeChannel(String channelId) async {
    _channelCloseController.add(channelId);
  }

  @override
  Future<int> bufferedAmount(String channelId) async => 0;

  @override
  bool isChannelOpen(String channelId) => _state == PeerState.connected;

  @override
  Future<PeerConnectionRoute> currentRoute() async => PeerConnectionRoute(
    kind: PeerRouteKind.direct,
    localCandidateType: 'host',
    remoteCandidateType: 'host',
    localAddressFamily: PeerAddressFamily.ipv4,
    remoteAddressFamily: PeerAddressFamily.ipv4,
    updatedAt: DateTime.now().millisecondsSinceEpoch,
  );

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

  void emitConnected() {
    if (_state == PeerState.connected) return;
    _state = PeerState.connected;
    _stateController.add(_state);
    _connectedController.add(null);
  }
}
