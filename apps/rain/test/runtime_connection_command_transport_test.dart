import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/connection_command/connection_command_models.dart';
import 'package:rain/application/connection_command/connection_run_token.dart';
import 'package:rain/application/connection_command/runtime_connection_command_transport.dart';
import 'package:rain/application/connection_command/session_manager_connection_transport.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/transport/fallback_session_manager.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RuntimeConnectionCommandTransport', () {
    test('preflight succeeds for online friends without connecting', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.addOnlineFriend('bob');
      final transport = RuntimeConnectionCommandTransport(
        runtime: harness.runtime,
        delegate: SessionManagerConnectionTransport(webRtc: harness.brain),
      );

      final result = await transport.runLayer(
        peerId: 'bob',
        layer: ConnectionLayer.preflight,
        token: _token(),
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.succeeded, isTrue);
      final brain = harness.brain as _RecordingSessionManager;
      expect(brain.registerCalls, 0);
      expect(brain.connectCalls, 0);
    });

    test('preflight rejects non-friends with a precise code', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      final transport = RuntimeConnectionCommandTransport(
        runtime: harness.runtime,
        delegate: SessionManagerConnectionTransport(webRtc: harness.brain),
      );

      final result = await transport.runLayer(
        peerId: 'bob',
        layer: ConnectionLayer.preflight,
        token: _token(),
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.succeeded, isFalse);
      expect(result.failureCode, ConnectionFailureCode.notFriends);
      expect((harness.brain as _RecordingSessionManager).connectCalls, 0);
    });

    test('web rtc layers delegate after preflight policy is handled', () async {
      final harness = await _Harness.create();
      addTearDown(harness.close);
      await harness.addOnlineFriend('bob');
      final brain = harness.brain as _RecordingSessionManager;
      brain.nextState = SessionState.connected;
      final transport = RuntimeConnectionCommandTransport(
        runtime: harness.runtime,
        delegate: SessionManagerConnectionTransport(webRtc: harness.brain),
      );

      final result = await transport.runLayer(
        peerId: 'bob',
        layer: ConnectionLayer.webRtcDirect,
        token: _token(),
        timeout: const Duration(milliseconds: 10),
      );

      expect(result.succeeded, isTrue);
      expect(brain.registerCalls, 1);
      expect(brain.connectCalls, 1);
    });

    test(
      'iroh layer can force Iroh through the composed fallback manager',
      () async {
        final webRtc = _RecordingSessionManager();
        final iroh = _RecordingSessionManager();
        final fallback = FallbackSessionManager(webRtc: webRtc, iroh: iroh);
        final harness = await _Harness.create(brain: fallback);
        addTearDown(() async {
          await harness.close();
          await fallback.dispose();
          await webRtc.close();
          await iroh.close();
        });
        final transport = RuntimeConnectionCommandTransport(
          runtime: harness.runtime,
          delegate: SessionManagerConnectionTransport(webRtc: fallback),
        );

        final result = await transport.runLayer(
          peerId: 'bob',
          layer: ConnectionLayer.iroh,
          token: _token(),
          timeout: const Duration(milliseconds: 10),
        );

        expect(result.succeeded, isTrue);
        expect(webRtc.connectCalls, 0);
        expect(iroh.connectCalls, 1);
      },
    );
  });
}

ConnectionRunToken _token() {
  return ConnectionRunToken(
    peerId: 'bob',
    runId: 'run-1',
    generation: 1,
    startedAt: 1,
  );
}

class _Harness {
  _Harness({
    required this.db,
    required this.adapter,
    required this.brain,
    required this.runtime,
    required this.friendStore,
  });

  final RainDatabase db;
  final NoopSignalingAdapter adapter;
  final SessionManager brain;
  final RainRuntimeController runtime;
  final FriendStore friendStore;

  static Future<_Harness> create({SessionManager? brain}) async {
    final db = RainDatabase(NativeDatabase.memory());
    final adapter = NoopSignalingAdapter();
    final effectiveBrain = brain ?? _RecordingSessionManager();
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 1,
      gender: RainGender.female,
    );
    final friendStore = FriendStore(db);
    final messageStore = MessageStore(db);
    final offlineQueueStore = OfflineQueueStore(db);
    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: adapter,
      brain: effectiveBrain,
      database: db,
      friendStore: friendStore,
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      ),
    );
    return _Harness(
      db: db,
      adapter: adapter,
      brain: effectiveBrain,
      runtime: runtime,
      friendStore: friendStore,
    );
  }

  Future<void> addOnlineFriend(String username) async {
    await friendStore.upsertFriend(
      username: username,
      displayName: username,
      state: FriendState.friend,
    );
    await adapter.upsertIdentity(
      BackendIdentity(
        username: username,
        uid: 'uid-$username',
        displayName: username,
        gender: null,
        registeredAt: 1,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        lastHeartbeat: DateTime.now().millisecondsSinceEpoch,
        online: true,
      ),
    );
  }

  Future<void> close() async {
    await adapter.dispose();
    await db.close();
  }
}

class _RecordingSessionManager implements SessionManager {
  var nextState = SessionState.connected;
  var registerCalls = 0;
  var connectCalls = 0;
  var disconnectCalls = 0;
  var unregisterCalls = 0;
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
  Future<void> registerPeer(String peerId) async {
    registerCalls += 1;
  }

  @override
  Future<Session> connect(String peerId) async {
    connectCalls += 1;
    final session = Session(
      peerId: peerId,
      state: nextState,
      connectionType: ConnectionType.signaling,
      detail: nextState == SessionState.connected ? 'Connected.' : 'Failed.',
      sender: (_) {},
    );
    _sessions[peerId] = session;
    _changes.add(session);
    if (nextState == SessionState.connected) {
      _connected.add(session);
    }
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    disconnectCalls += 1;
    _sessions.remove(peerId);
    _disconnected.add(peerId);
  }

  @override
  Future<void> unregisterPeer(String peerId) async {
    unregisterCalls += 1;
  }

  @override
  Session? getSession(String peerId) => _sessions[peerId];

  @override
  List<Session> getSessions() => _sessions.values.toList(growable: false);

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) => true;

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {}

  @override
  void send(String peerId, SessionChannel channel, Object data) {}

  @override
  void sendControl(String peerId, String data) {}

  Future<void> close() async {
    await _connected.close();
    await _disconnected.close();
    await _messages.close();
    await _changes.close();
  }
}
