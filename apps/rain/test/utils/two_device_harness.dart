import 'package:drift/native.dart';
import 'package:rain_core/rain_core.dart';
import 'package:protocol_brain/protocol_brain.dart';

import '../../lib/services/rain_runtime_controller.dart';
import '../../lib/services/firebase/firebase_signaling_adapter.dart';

// Two-device handshake harness for CI/local emulators.
// Returns true if a tiny message can traverse the data channel after a
// successful handshake between Alice and Bob.
class TwoDeviceHarness {
  Future<bool> run() async {
    final iceServers = const <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ];

    // Per-device in-memory databases
    final aliceDb = RainDatabase(NativeDatabase.memory());
    final bobDb = RainDatabase(NativeDatabase.memory());

    // Emulator signaling adapters
    final aliceAdapter = FirebaseSignalingAdapter(useEmulator: true);
    final bobAdapter = FirebaseSignalingAdapter(useEmulator: true);

    // Register users on emulator
    await aliceAdapter.register('alice', 'alicepw');
    await bobAdapter.register('bob', 'bobpw');
    await aliceAdapter.login('alice', 'alicepw');
    await bobAdapter.login('bob', 'bobpw');

    // Brains for both sides
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
    );
    final bobIdentity = RainIdentity(
      username: 'bob',
      displayName: 'Bob',
      createdAt: 0,
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

    // Echo payload after handshake to verify data channel works
    await runtimeAlice.sendMessage('bob', 'echo-from-alice');
    await Future.delayed(const Duration(milliseconds: 500));

    final bobMessages = await bobDb.select(bobDb.messages).get();
    final found = bobMessages.any(
      (m) =>
          m.peerId == 'alice' &&
          m.content == 'echo-from-alice' &&
          m.isOutgoing == false,
    );
    return found;
  }
}
