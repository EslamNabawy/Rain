import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'runtime stays transport-agnostic and does not import Iroh directly',
    () {
      final source = File(
        'lib/application/runtime/rain_runtime_controller.dart',
      ).readAsStringSync().replaceAll('\r\n', '\n');

      expect(source, contains('final SessionManager? brain;'));
      expect(source, isNot(contains('infrastructure/iroh')));
      expect(source, isNot(contains('IrohSessionManager')));
      expect(source, isNot(contains('IrohBridgeClient')));
    },
  );

  test('logout disconnects active Iroh sessions and clears identity', () async {
    final db = RainDatabase(NativeDatabase.memory());
    final brain = _LifecycleSessionManager(<Session>[
      _session('bob', ConnectionType.iroh),
    ]);
    addTearDown(() async {
      await brain.close();
      await db.close();
    });

    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 1,
      gender: RainGender.female,
    );
    await IdentityRepository(db).saveIdentity(identity);

    final runtime = _runtime(db: db, identity: identity, brain: brain);
    await runtime.start();
    await runtime.logOut();

    expect(brain.connectedPeers, isEmpty);
    expect(brain.disconnectedPeers, <String>['bob']);
    expect(brain.unregisteredPeers, <String>['bob']);
    expect(await IdentityRepository(db).loadIdentity(), isNull);
  });

  test('network loss disconnects Iroh sessions without reconnecting', () async {
    final db = RainDatabase(NativeDatabase.memory());
    final brain = _LifecycleSessionManager(<Session>[
      _session('bob', ConnectionType.iroh),
    ]);
    addTearDown(() async {
      await brain.close();
      await db.close();
    });

    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 1,
      gender: RainGender.female,
    );
    final runtime = _runtime(db: db, identity: identity, brain: brain);

    await runtime.handleNetworkLost(
      'Internet connection lost. Transfer canceled.',
    );

    expect(brain.connectedPeers, isEmpty);
    expect(brain.disconnectedPeers, <String>['bob']);
    expect(brain.unregisteredPeers, <String>['bob']);
  });
}

RainRuntimeController _runtime({
  required RainDatabase db,
  required RainIdentity identity,
  required SessionManager brain,
}) {
  final messageStore = MessageStore(db);
  final offlineQueueStore = OfflineQueueStore(db);
  return RainRuntimeController(
    selfIdentity: identity,
    adapter: NoopSignalingAdapter(),
    brain: brain,
    database: db,
    friendStore: FriendStore(db),
    messageStore: messageStore,
    offlineQueueStore: offlineQueueStore,
    messageDeliveryService: MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
    ),
    friendRequestRefreshInterval: Duration.zero,
  );
}

Session _session(String peerId, ConnectionType connectionType) {
  return Session(
    peerId: peerId,
    state: SessionState.connected,
    connectionType: connectionType,
    connectedAt: 1,
    updatedAt: 1,
    sender: (_) {},
  );
}

class _LifecycleSessionManager implements SessionManager {
  _LifecycleSessionManager(List<Session> sessions) {
    for (final session in sessions) {
      _sessions[session.peerId] = session;
    }
  }

  final connectedPeers = <String>[];
  final disconnectedPeers = <String>[];
  final unregisteredPeers = <String>[];
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
    final session = _session(peerId, ConnectionType.iroh);
    _sessions[peerId] = session;
    _connected.add(session);
    _changes.add(session);
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    disconnectedPeers.add(peerId);
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
  Future<void> unregisterPeer(String peerId) async {
    unregisteredPeers.add(peerId);
  }

  Future<void> close() async {
    await _connected.close();
    await _disconnected.close();
    await _messages.close();
    await _changes.close();
  }
}
