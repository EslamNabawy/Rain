import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/iroh/iroh_bridge_client.dart';
import 'package:rain/infrastructure/iroh/iroh_models.dart';
import 'package:rain/infrastructure/iroh/iroh_session_manager.dart';

class FakeIrohNativeApi implements IrohNativeApi {
  var stopped = false;
  var disconnectedPeerId = '';
  var connectedPeerId = '';
  var acceptedPeerId = '';
  var lastConnectAttemptId = '';
  var lastAcceptAttemptId = '';
  var lastConnectSecret = '';
  var lastAcceptSecret = '';
  var sentChannel = '';
  var sentPayload = Object();
  var pendingBytes = 0;
  final events = StreamController<IrohTransportEvent>.broadcast();

  @override
  Future<IrohEndpointInfo> startEndpoint({
    required String username,
    required String alpn,
  }) async {
    return IrohEndpointInfo(
      nodeId: '$username-node',
      endpointAddr: '$username-endpoint',
    );
  }

  @override
  Future<void> stopEndpoint() async {
    stopped = true;
  }

  @override
  Future<void> disconnectPeer({required String peerId}) async {
    disconnectedPeerId = peerId;
  }

  @override
  Future<void> connectPeer({
    required String peerId,
    required String endpointAddr,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) async {
    connectedPeerId = peerId;
    lastConnectAttemptId = connectAttemptId;
    lastConnectSecret = sessionSecret;
  }

  @override
  Future<void> acceptPeer({
    required String peerId,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) async {
    acceptedPeerId = peerId;
    lastAcceptAttemptId = connectAttemptId;
    lastAcceptSecret = sessionSecret;
  }

  @override
  Future<void> send({
    required String peerId,
    required String channel,
    required Object payload,
  }) async {
    sentChannel = channel;
    sentPayload = payload;
  }

  @override
  Future<int> bufferedAmount({
    required String peerId,
    required String channel,
  }) async {
    return pendingBytes;
  }

  @override
  Stream<IrohTransportEvent> eventStream() => events.stream;

  Future<void> close() => events.close();
}

class MemorySignalingAdapter implements SignalingAdapter {
  final addresses = <String, List<IrohAddressPayload>>{};
  final controllers = <String, StreamController<IrohAddressPayload>>{};

  @override
  Future<void> writeIrohAddress(
    String roomId,
    IrohAddressPayload payload,
  ) async {
    addresses.putIfAbsent(roomId, () => <IrohAddressPayload>[]).add(payload);
    controllers[roomId]?.add(payload);
  }

  @override
  Stream<IrohAddressPayload> onIrohAddress(String roomId) {
    final controller = controllers.putIfAbsent(
      roomId,
      () => StreamController<IrohAddressPayload>.broadcast(),
    );
    scheduleMicrotask(() {
      for (final payload in addresses[roomId] ?? const <IrohAddressPayload>[]) {
        if (!controller.isClosed) {
          controller.add(payload);
        }
      }
    });
    return controller.stream;
  }

  Future<void> close() async {
    for (final controller in controllers.values) {
      await controller.close();
    }
  }

  @override
  Future<void> ensureAuthenticated() async {}

  @override
  Future<String> currentUid() async => 'uid';

  @override
  Future<void> signOut() async {}

  @override
  Future<String> register(String username, String password) async => 'uid';

  @override
  Future<String> login(String username, String password) async => 'uid';

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {}

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) async {}

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    IceCandidatePayload candidate,
  ) async {}

  @override
  Stream<SDPPayload> onAnswer(String roomId) =>
      const Stream<SDPPayload>.empty();

  @override
  Stream<IceCandidatePayload> onICE(String roomId, IceRole role) =>
      const Stream<IceCandidatePayload>.empty();

  @override
  Stream<SDPPayload> onOffer(String roomId) => const Stream<SDPPayload>.empty();

  @override
  Future<void> setPresence(String username, bool online) async {}

  @override
  Future<void> sendHeartbeat(String username) async {}

  @override
  Stream<bool> watchPresence(String username) => const Stream<bool>.empty();

  @override
  Future<bool> isUsernameAvailable(String username) async => true;

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {}

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async => null;

  @override
  Future<void> addToUserSearch(String username) async {}

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async =>
      const <BackendIdentity>[];

  @override
  Future<void> writeFriendRequest(String to, String from) async {}

  @override
  Future<void> deleteFriendRequest(String to, String from) async {}

  @override
  Future<List<String>> loadIncomingFriendRequests(String username) async =>
      const <String>[];

  @override
  Future<List<String>> loadOutgoingFriendRequests(String username) async =>
      const <String>[];

  @override
  Future<List<String>> loadAcceptedFriends(String username) async =>
      const <String>[];

  @override
  Future<List<String>> loadBlockedUsers(String username) async =>
      const <String>[];

  @override
  Future<List<String>> loadUsersBlocking(String username) async =>
      const <String>[];

  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) async {}

  @override
  Future<void> deleteFriendship(String firstUser, String secondUser) async {}

  @override
  Future<void> blockUser(String blocker, String blocked) async {}

  @override
  Future<void> unblockUser(String blocker, String blocked) async {}

  @override
  Stream<String> onFriendRequest(String username) =>
      const Stream<String>.empty();

  @override
  Stream<String> onRelationshipChanged(String username) =>
      const Stream<String>.empty();

  @override
  Future<void> deleteRoom(String roomId) async {}

  @override
  Future<void> dispose() => close();
}

void main() {
  test('lower username dials using its own attempt secret', () async {
    final adapter = MemorySignalingAdapter();
    final native = FakeIrohNativeApi();
    final manager = IrohSessionManager(
      selfUsername: 'alice',
      adapter: adapter,
      bridge: IrohBridgeClient(native),
      alpn: 'rain.p2p.quic.v1',
      attemptIdFactory: () => 'alice-attempt',
      sessionSecretFactory: () => 'alice-secret',
    );

    final connected = manager.onPeerConnected.first;
    final connectFuture = manager.connect('bob');
    await Future<void>.delayed(Duration.zero);
    await adapter.writeIrohAddress(
      'alice:bob',
      const IrohAddressPayload(
        protocolVersion: 1,
        connectAttemptId: 'bob-attempt',
        username: 'bob',
        nodeId: 'bob-node',
        endpointAddr: 'bob-endpoint',
        sessionSecret: 'bob-secret',
        createdAt: 1000,
        expiresAt: 9999999999999,
      ),
    );

    final session = await connectFuture;

    expect(session.connectionType, ConnectionType.iroh);
    expect((await connected).peerId, 'bob');
    expect(native.connectedPeerId, 'bob');
    expect(native.lastConnectAttemptId, 'alice-attempt');
    expect(native.lastConnectSecret, 'alice-secret');
    expect(
      adapter.addresses['alice:bob']!.any(
        (payload) => payload.username == 'alice',
      ),
      isTrue,
    );
    await manager.dispose();
    await native.close();
    await adapter.close();
  });

  test('higher username accepts using lower peer attempt secret', () async {
    final adapter = MemorySignalingAdapter();
    final native = FakeIrohNativeApi();
    final manager = IrohSessionManager(
      selfUsername: 'bob',
      adapter: adapter,
      bridge: IrohBridgeClient(native),
      alpn: 'rain.p2p.quic.v1',
      attemptIdFactory: () => 'bob-attempt',
      sessionSecretFactory: () => 'bob-secret',
    );

    final connectFuture = manager.connect('alice');
    await Future<void>.delayed(Duration.zero);
    await adapter.writeIrohAddress(
      'alice:bob',
      const IrohAddressPayload(
        protocolVersion: 1,
        connectAttemptId: 'alice-attempt',
        username: 'alice',
        nodeId: 'alice-node',
        endpointAddr: 'alice-endpoint',
        sessionSecret: 'alice-secret',
        createdAt: 1000,
        expiresAt: 9999999999999,
      ),
    );

    final session = await connectFuture;

    expect(session.connectionType, ConnectionType.iroh);
    expect(native.acceptedPeerId, 'alice');
    expect(native.lastAcceptAttemptId, 'alice-attempt');
    expect(native.lastAcceptSecret, 'alice-secret');
    await manager.dispose();
    await native.close();
    await adapter.close();
  });

  test('send and bufferedAmount use Rain channel ids', () async {
    final adapter = MemorySignalingAdapter();
    final native = FakeIrohNativeApi()..pendingBytes = 77;
    final manager = IrohSessionManager(
      selfUsername: 'alice',
      adapter: adapter,
      bridge: IrohBridgeClient(native),
      alpn: 'rain.p2p.quic.v1',
      attemptIdFactory: () => 'alice-attempt',
      sessionSecretFactory: () => 'alice-secret',
    );

    final connectFuture = manager.connect('bob');
    await Future<void>.delayed(Duration.zero);
    await adapter.writeIrohAddress(
      'alice:bob',
      const IrohAddressPayload(
        protocolVersion: 1,
        connectAttemptId: 'bob-attempt',
        username: 'bob',
        nodeId: 'bob-node',
        endpointAddr: 'bob-endpoint',
        sessionSecret: 'bob-secret',
        createdAt: 1000,
        expiresAt: 9999999999999,
      ),
    );
    await connectFuture;

    manager.send('bob', SessionChannel.control, 'ack');
    final buffered = await manager.bufferedAmount('bob', SessionChannel.file);

    expect(native.sentChannel, 'rain.ctrl');
    expect(native.sentPayload, 'ack');
    expect(buffered, 77);
    expect(manager.isChannelOpen('bob', SessionChannel.file), isTrue);
    await manager.dispose();
    await native.close();
    await adapter.close();
  });

  test('native text events are emitted as session messages', () async {
    final adapter = MemorySignalingAdapter();
    final native = FakeIrohNativeApi();
    final manager = IrohSessionManager(
      selfUsername: 'alice',
      adapter: adapter,
      bridge: IrohBridgeClient(native),
      alpn: 'rain.p2p.quic.v1',
      attemptIdFactory: () => 'alice-attempt',
      sessionSecretFactory: () => 'alice-secret',
    );

    final connectFuture = manager.connect('bob');
    await Future<void>.delayed(Duration.zero);
    await adapter.writeIrohAddress(
      'alice:bob',
      const IrohAddressPayload(
        protocolVersion: 1,
        connectAttemptId: 'bob-attempt',
        username: 'bob',
        nodeId: 'bob-node',
        endpointAddr: 'bob-endpoint',
        sessionSecret: 'bob-secret',
        createdAt: 1000,
        expiresAt: 9999999999999,
      ),
    );
    await connectFuture;

    final messageFuture = manager.onPeerMessage.first;
    native.events.add(
      IrohTransportEvent(
        type: IrohTransportEventType.data,
        peerId: 'bob',
        channel: 'rain.ctrl',
        payload: Uint8List.fromList(utf8.encode('ack')),
        receivedAt: DateTime.fromMillisecondsSinceEpoch(123),
      ),
    );

    final message = await messageFuture;
    expect(message.peerId, 'bob');
    expect(message.channel, SessionChannel.control);
    expect(message.text, 'ack');
    expect(message.receivedAt.millisecondsSinceEpoch, 123);
    await manager.dispose();
    await native.close();
    await adapter.close();
  });

  test('native file events are emitted as binary session messages', () async {
    final adapter = MemorySignalingAdapter();
    final native = FakeIrohNativeApi();
    final manager = IrohSessionManager(
      selfUsername: 'alice',
      adapter: adapter,
      bridge: IrohBridgeClient(native),
      alpn: 'rain.p2p.quic.v1',
      attemptIdFactory: () => 'alice-attempt',
      sessionSecretFactory: () => 'alice-secret',
    );

    final connectFuture = manager.connect('bob');
    await Future<void>.delayed(Duration.zero);
    await adapter.writeIrohAddress(
      'alice:bob',
      const IrohAddressPayload(
        protocolVersion: 1,
        connectAttemptId: 'bob-attempt',
        username: 'bob',
        nodeId: 'bob-node',
        endpointAddr: 'bob-endpoint',
        sessionSecret: 'bob-secret',
        createdAt: 1000,
        expiresAt: 9999999999999,
      ),
    );
    await connectFuture;

    final messageFuture = manager.onPeerMessage.first;
    native.events.add(
      IrohTransportEvent(
        type: IrohTransportEventType.data,
        peerId: 'bob',
        channel: 'rain.file',
        payload: Uint8List.fromList(<int>[1, 2, 3]),
        receivedAt: DateTime.fromMillisecondsSinceEpoch(124),
      ),
    );

    final message = await messageFuture;
    expect(message.peerId, 'bob');
    expect(message.channel, SessionChannel.file);
    expect(message.binary, <int>[1, 2, 3]);
    expect(message.text, isNull);
    await manager.dispose();
    await native.close();
    await adapter.close();
  });

  test('disconnect closes native peer and clears session', () async {
    final adapter = MemorySignalingAdapter();
    final native = FakeIrohNativeApi();
    final manager = IrohSessionManager(
      selfUsername: 'alice',
      adapter: adapter,
      bridge: IrohBridgeClient(native),
      alpn: 'rain.p2p.quic.v1',
      attemptIdFactory: () => 'alice-attempt',
      sessionSecretFactory: () => 'alice-secret',
    );

    final connectFuture = manager.connect('bob');
    await Future<void>.delayed(Duration.zero);
    await adapter.writeIrohAddress(
      'alice:bob',
      const IrohAddressPayload(
        protocolVersion: 1,
        connectAttemptId: 'bob-attempt',
        username: 'bob',
        nodeId: 'bob-node',
        endpointAddr: 'bob-endpoint',
        sessionSecret: 'bob-secret',
        createdAt: 1000,
        expiresAt: 9999999999999,
      ),
    );
    await connectFuture;

    await manager.disconnect('bob');

    expect(native.disconnectedPeerId, 'bob');
    expect(manager.getSession('bob'), isNull);
    await manager.dispose();
    await native.close();
    await adapter.close();
  });
}
