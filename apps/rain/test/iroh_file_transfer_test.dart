import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/infrastructure/iroh/iroh_bridge_client.dart';
import 'package:rain/infrastructure/iroh/iroh_models.dart';
import 'package:rain/infrastructure/iroh/iroh_session_manager.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Iroh file channel is ready after connect and openChannel', () async {
    final harness = await _IrohHarness.connect();
    addTearDown(harness.close);

    await harness.manager.openChannel('bob', SessionChannel.file);

    expect(harness.manager.isChannelOpen('bob', SessionChannel.file), isTrue);
  });

  test('Iroh outgoing file offer is sent on rain.file', () async {
    final harness = await _IrohHarness.connect();
    addTearDown(harness.close);
    final offer = FileTransferFrame.offer(
      transferId: 'transfer-1',
      messageId: 'message-1',
      fileName: 'hello.txt',
      fileSize: 3,
      sentAt: 1,
      seq: 1,
    ).encode();

    harness.manager.send('bob', SessionChannel.file, offer);

    expect(harness.native.sent, hasLength(1));
    expect(harness.native.sent.single.channel, 'rain.file');
    expect(harness.native.sent.single.payload, offer);
  });

  test('Iroh binary file chunk is sent on rain.file', () async {
    final harness = await _IrohHarness.connect();
    addTearDown(harness.close);
    final payload = FileTransferChunkPacket(
      frame: FileTransferFrame.chunk(
        transferId: 'transfer-1',
        index: 0,
        offset: 0,
        byteCount: 3,
      ),
      payload: Uint8List.fromList(<int>[1, 2, 3]),
    ).encode();

    harness.manager.send('bob', SessionChannel.file, payload);

    expect(harness.native.sent, hasLength(1));
    expect(harness.native.sent.single.channel, 'rain.file');
    expect(harness.native.sent.single.payload, same(payload));
  });

  test('Iroh file bufferedAmount uses rain.file channel id', () async {
    final harness = await _IrohHarness.connect();
    addTearDown(harness.close);
    harness.native.pendingBytes = 65536;

    final buffered = await harness.manager.bufferedAmount(
      'bob',
      SessionChannel.file,
    );

    expect(buffered, 65536);
    expect(harness.native.lastBufferedChannel, 'rain.file');
  });

  test('Iroh disconnect mid-transfer marks transfer failed clearly', () async {
    final db = RainDatabase(NativeDatabase.memory());
    final adapter = NoopSignalingAdapter();
    final brain = _IrohRuntimeSessionManager(<Session>[_session('bob')]);
    final temp = await Directory.systemTemp.createTemp(
      'rain-iroh-transfer-drop-',
    );
    addTearDown(() async {
      await brain.close();
      await db.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    await adapter.upsertFriendship('alice', 'bob');
    await db
        .into(db.friends)
        .insert(
          FriendsCompanion.insert(
            username: 'bob',
            displayName: 'Bob',
            state: FriendState.friend.name,
            addedAt: 1,
          ),
        );
    final tempFile = File('${temp.path}${Platform.pathSeparator}video.part');
    await tempFile.writeAsString('partial');
    final transferStore = FileTransferStore(db);
    await transferStore.upsert(
      FileTransferRecord(
        id: 'transfer-1',
        peerId: 'bob',
        messageId: 'message-1',
        direction: FileTransferDirection.incoming,
        fileName: 'video.mp4',
        fileSize: 4096,
        localPath: '${temp.path}${Platform.pathSeparator}video.mp4',
        tempPath: tempFile.path,
        bytesTransferred: 128,
        state: FileTransferState.receiving,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: RainGender.female,
      ),
      adapter: adapter,
      brain: brain,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
      fileTransferStore: transferStore,
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();
    brain.emitPeerDisconnected('bob');

    final failed = await _waitForTransferState(
      transferStore,
      'transfer-1',
      FileTransferState.failed,
    );
    expect(failed.error, 'Connection lost. Transfer canceled.');
    expect(await tempFile.exists(), isFalse);
  });
}

class _IrohHarness {
  const _IrohHarness({
    required this.adapter,
    required this.native,
    required this.manager,
  });

  final _MemoryIrohSignalingAdapter adapter;
  final _RecordingIrohNativeApi native;
  final IrohSessionManager manager;

  static Future<_IrohHarness> connect() async {
    final adapter = _MemoryIrohSignalingAdapter();
    final native = _RecordingIrohNativeApi();
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
    return _IrohHarness(adapter: adapter, native: native, manager: manager);
  }

  Future<void> close() async {
    await manager.dispose();
    await adapter.close();
  }
}

class _SentIrohPayload {
  const _SentIrohPayload({
    required this.peerId,
    required this.channel,
    required this.payload,
  });

  final String peerId;
  final String channel;
  final Object payload;
}

class _RecordingIrohNativeApi implements IrohNativeApi {
  var pendingBytes = 0;
  var lastBufferedChannel = '';
  final sent = <_SentIrohPayload>[];

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
  Future<void> stopEndpoint() async {}

  @override
  Future<void> disconnectPeer({required String peerId}) async {}

  @override
  Future<void> connectPeer({
    required String peerId,
    required String endpointAddr,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) async {}

  @override
  Future<void> acceptPeer({
    required String peerId,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) async {}

  @override
  Future<void> send({
    required String peerId,
    required String channel,
    required Object payload,
  }) async {
    sent.add(
      _SentIrohPayload(peerId: peerId, channel: channel, payload: payload),
    );
  }

  @override
  Future<int> bufferedAmount({
    required String peerId,
    required String channel,
  }) async {
    lastBufferedChannel = channel;
    return pendingBytes;
  }

  @override
  Stream<IrohTransportEvent> eventStream() =>
      const Stream<IrohTransportEvent>.empty();
}

class _MemoryIrohSignalingAdapter implements SignalingAdapter {
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

class _IrohRuntimeSessionManager implements SessionManager {
  _IrohRuntimeSessionManager(List<Session> sessions) {
    for (final session in sessions) {
      _sessions[session.peerId] = session;
    }
  }

  final _sessions = <String, Session>{};
  final _connected = StreamController<Session>.broadcast();
  final _disconnected = StreamController<String>.broadcast();
  final _messages = StreamController<SessionMessage>.broadcast();
  final _changes = StreamController<Session>.broadcast();

  @override
  Stream<Session> get onPeerConnected => _connected.stream;

  @override
  Stream<String> get onPeerDisconnected => _disconnected.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _messages.stream;

  @override
  Stream<Session> get onSessionChanged => _changes.stream;

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      const Stream<IncomingOfferRejection>.empty();

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  Future<Session> connect(String peerId) async {
    final session = _session(peerId);
    _sessions[peerId] = session;
    _connected.add(session);
    _changes.add(session);
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    _sessions.remove(peerId);
    _disconnected.add(peerId);
  }

  @override
  Session? getSession(String peerId) => _sessions[peerId];

  @override
  List<Session> getSessions() => _sessions.values.toList(growable: false);

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) {
    return _sessions[peerId]?.state == SessionState.connected;
  }

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {}

  @override
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {}

  @override
  Future<void> recoverConnection(
    String peerId, {
    String reason = 'Network changed. Restarting peer connection.',
  }) async {}

  @override
  Future<void> recoverConnections({
    String reason = 'Network changed. Restarting peer connections.',
  }) async {}

  @override
  void send(String peerId, SessionChannel channel, Object data) {}

  @override
  void sendControl(String peerId, String data) {}

  @override
  Future<void> unregisterPeer(String peerId) async {}

  void emitPeerDisconnected(String peerId) {
    _sessions.remove(peerId);
    _disconnected.add(peerId);
  }

  Future<void> close() async {
    await _connected.close();
    await _disconnected.close();
    await _messages.close();
    await _changes.close();
  }
}

Session _session(String peerId) {
  return Session(
    peerId: peerId,
    state: SessionState.connected,
    connectionType: ConnectionType.iroh,
    connectedAt: 1,
    updatedAt: 1,
    sender: (_) {},
  );
}

Future<FileTransferRecord> _waitForTransferState(
  FileTransferStore store,
  String transferId,
  FileTransferState state,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    final transfer = await store.loadById(transferId);
    if (transfer?.state == state) {
      return transfer!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  final transfer = await store.loadById(transferId);
  fail('Timed out waiting for $transferId to become $state. Saw $transfer.');
}
