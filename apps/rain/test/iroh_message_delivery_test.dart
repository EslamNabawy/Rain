import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Iroh send completion marks sent but not delivered before ACK',
    () async {
      final harness = await _Harness.create(
        connectedPeers: const <String>['bob'],
      );
      addTearDown(harness.close);

      await harness.runtime.start();
      await harness.runtime.sendMessage('bob', 'hello over iroh');

      expect(harness.brain.sentChatPayloads, hasLength(1));
      final message = await harness.singleMessage();
      expect(message.status, MessageStatus.sent.name);
    },
  );

  test('Iroh message becomes delivered only after correct peer ACK', () async {
    final harness = await _Harness.create(
      connectedPeers: const <String>['bob'],
    );
    addTearDown(harness.close);

    await harness.runtime.start();
    await harness.runtime.sendMessage('bob', 'hello over iroh');
    final sent = await harness.singleMessage();

    harness.brain.emitControl(
      'bob',
      jsonEncode(<String, String>{'type': 'ack', 'ackId': sent.id}),
    );
    await pumpEventQueue();

    final delivered = await harness.singleMessage();
    expect(delivered.status, MessageStatus.delivered.name);
  });

  test('ACK from wrong peer does not mark Iroh message delivered', () async {
    final harness = await _Harness.create(
      connectedPeers: const <String>['bob'],
    );
    addTearDown(harness.close);

    await harness.runtime.start();
    await harness.runtime.sendMessage('bob', 'hello over iroh');
    final sent = await harness.singleMessage();

    harness.brain.emitControl(
      'mallory',
      jsonEncode(<String, String>{'type': 'ack', 'ackId': sent.id}),
    );
    await pumpEventQueue();

    final afterWrongAck = await harness.singleMessage();
    expect(afterWrongAck.status, MessageStatus.sent.name);

    harness.brain.emitControl(
      'bob',
      jsonEncode(<String, String>{'type': 'ack', 'ackId': sent.id}),
    );
    await pumpEventQueue();

    final afterCorrectAck = await harness.singleMessage();
    expect(afterCorrectAck.status, MessageStatus.delivered.name);
  });

  test('disconnected Iroh send queues without reconnecting', () async {
    final harness = await _Harness.create();
    addTearDown(harness.close);

    await harness.runtime.sendMessage('bob', 'queue until manual connect');

    expect(harness.brain.connectedPeers, isEmpty);
    final message = await harness.singleMessage();
    expect(message.status, MessageStatus.queued.name);
    final queued = await harness.db.select(harness.db.queuedMessages).get();
    expect(queued.single.status, QueuedMessageStatus.queued.name);
  });
}

class _Harness {
  _Harness({
    required this.db,
    required this.deliveryService,
    required this.brain,
    required this.runtime,
  });

  final RainDatabase db;
  final MessageDeliveryService deliveryService;
  final _IrohMessageSessionManager brain;
  final RainRuntimeController runtime;

  static Future<_Harness> create({
    List<String> connectedPeers = const <String>[],
  }) async {
    final db = RainDatabase(NativeDatabase.memory());
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 1,
      gender: RainGender.female,
    );
    final adapter = NoopSignalingAdapter();
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
    final messageStore = MessageStore(db);
    final offlineQueueStore = OfflineQueueStore(db);
    final deliveryService = MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
    );
    final brain = _IrohMessageSessionManager(connectedPeers);
    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: adapter,
      brain: brain,
      database: db,
      friendStore: FriendStore(db),
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: deliveryService,
      friendRequestRefreshInterval: Duration.zero,
    );
    return _Harness(
      db: db,
      deliveryService: deliveryService,
      brain: brain,
      runtime: runtime,
    );
  }

  Future<Message> singleMessage() async {
    final messages = await db.select(db.messages).get();
    return messages.single;
  }

  Future<void> close() async {
    deliveryService.dispose();
    await runtime.dispose();
    await brain.close();
    await db.close();
  }
}

class _IrohMessageSessionManager implements SessionManager {
  _IrohMessageSessionManager(List<String> connectedPeers) {
    for (final peerId in connectedPeers) {
      _sessions[peerId] = _connectedSession(peerId);
    }
  }

  final connectedPeers = <String>[];
  final sentChatPayloads = <String>[];
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
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  Future<Session> connect(String peerId) async {
    connectedPeers.add(peerId);
    final session = _connectedSession(peerId);
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
  Future<void> registerPeer(String peerId) async {}

  @override
  void send(String peerId, SessionChannel channel, Object data) {}

  @override
  void sendControl(String peerId, String data) {}

  @override
  Future<void> unregisterPeer(String peerId) async {}

  void emitControl(String peerId, String data) {
    _messages.add(
      SessionMessage(
        channel: SessionChannel.control,
        data: data,
        receivedAt: DateTime.now(),
        peerId: peerId,
      ),
    );
  }

  Future<void> close() async {
    await _connected.close();
    await _disconnected.close();
    await _messages.close();
    await _changes.close();
  }

  Session _connectedSession(String peerId) {
    return Session(
      peerId: peerId,
      state: SessionState.connected,
      connectionType: ConnectionType.iroh,
      connectedAt: 1,
      updatedAt: 1,
      sender: sentChatPayloads.add,
    );
  }
}
