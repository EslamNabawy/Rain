import 'package:drift/native.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:rain/firebase_options.dart';
import 'package:rain/services/rain_runtime_controller.dart';
import 'package:rain_core/rain_core.dart';
import 'package:protocol_brain/protocol_brain.dart';

class TwoDeviceHarness {
  Future<bool> run() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final iceServers = const <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ];

    final aliceDb = RainDatabase(NativeDatabase.memory());
    final bobDb = RainDatabase(NativeDatabase.memory());
    final aliceAdapter = FirebaseSignalingAdapter(useEmulator: true);
    final bobAdapter = FirebaseSignalingAdapter(useEmulator: true);

    try {
      await aliceAdapter.register('alice', 'alicepw');
      await bobAdapter.register('bob', 'bobpw');
      await aliceAdapter.login('alice', 'alicepw');
      await bobAdapter.login('bob', 'bobpw');

      final aliceBrain = createDefaultProtocolBrain(
        selfUsername: 'alice',
        adapter: aliceAdapter,
        iceServers: iceServers,
        connectionMemoryStore: DriftConnectionMemoryStore(aliceDb),
      );
      final bobBrain = createDefaultProtocolBrain(
        selfUsername: 'bob',
        adapter: bobAdapter,
        iceServers: iceServers,
        connectionMemoryStore: DriftConnectionMemoryStore(bobDb),
      );

      final aliceIdentity = RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: null,
      );
      final bobIdentity = RainIdentity(
        username: 'bob',
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

      await runtimeAlice.connectPeer('bob');
      await runtimeBob.connectPeer('alice');

      await Future.delayed(const Duration(seconds: 2));

      final aSess = aliceBrain.getSession('bob');
      final bSess = bobBrain.getSession('alice');
      if (aSess?.state != SessionState.connected ||
          bSess?.state != SessionState.connected) {
        return false;
      }

      await runtimeAlice.sendMessage('bob', 'echo-from-alice');
      await Future.delayed(const Duration(milliseconds: 500));

      final bobMessages = await bobDb.select(bobDb.messages).get();
      return bobMessages.any(
        (m) =>
            m.peerId == 'alice' &&
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
