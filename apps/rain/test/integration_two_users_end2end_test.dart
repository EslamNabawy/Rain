import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:rain_core/rain_core.dart';
import 'package:protocol_brain/protocol_brain.dart';

import '../lib/services/rain_runtime_controller.dart';
import '../lib/services/noop_signaling_adapter.dart';

// This test relies on Firebase Emulators plugged into the FirebaseSignalingAdapter
// It creates two independent user contexts and runs a minimal end-to-end friend flow
// (register -> login -> send friend request -> inbound -> accept) using the emulator.
// Note: This test is meant to be run in CI with emulators started via the harness.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Two-user end-to-end friend flow on Firebase emulator', () async {
    // Each user gets its own in-memory Drift DB to simulate separate devices
    final dbAlice = RainDatabase(NativeDatabase.memory());
    final dbBob = RainDatabase(NativeDatabase.memory());

    // Emulated Firebase adapters
    final adapterAlice = FirebaseSignalingAdapter(useEmulator: true);
    final adapterBob = FirebaseSignalingAdapter(useEmulator: true);

    // Register and login two users
    await adapterAlice.register('alice', 'alicepw');
    await adapterBob.register('bob', 'bobpw');
    await adapterAlice.login('alice', 'alicepw');
    await adapterBob.login('bob', 'bobpw');

    // Identity objects for local state
    final aliceIdentity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final bobIdentity = RainIdentity(
      username: 'bob',
      displayName: 'Bob',
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    final runtimeAlice = RainRuntimeController(
      selfIdentity: aliceIdentity,
      adapter: adapterAlice,
      brain: null,
      database: dbAlice,
      friendStore: FriendStore(dbAlice),
      messageStore: MessageStore(dbAlice),
      offlineQueueStore: OfflineQueueStore(dbAlice),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(dbAlice),
        offlineQueueStore: OfflineQueueStore(dbAlice),
      ),
    );
    final runtimeBob = RainRuntimeController(
      selfIdentity: bobIdentity,
      adapter: adapterBob,
      brain: null,
      database: dbBob,
      friendStore: FriendStore(dbBob),
      messageStore: MessageStore(dbBob),
      offlineQueueStore: OfflineQueueStore(dbBob),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(dbBob),
        offlineQueueStore: OfflineQueueStore(dbBob),
      ),
    );

    await runtimeAlice.start();
    await runtimeBob.start();

    // Alice sends a friend request to Bob
    await runtimeAlice.sendFriendRequest('bob');

    // Bob should observe an inbound friend request from Alice
    final inbound = await adapterBob.onFriendRequest('bob').first;
    expect(inbound, 'alice');

    // Bob accepts the request
    await runtimeBob.acceptFriend('alice');

    // Verify both sides reflect the friend relationship
    final aliceBob = await runtimeAlice.friendStore.loadFriend('bob');
    final bobAlice = await runtimeBob.friendStore.loadFriend('alice');
    expect(aliceBob != null, isTrue);
    expect(aliceBob!.state, FriendState.friend);
    expect(bobAlice != null, isTrue);
    expect(bobAlice!.state, FriendState.friend);
  });
}
