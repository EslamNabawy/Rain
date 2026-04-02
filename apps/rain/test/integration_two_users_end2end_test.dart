import 'package:drift/native.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import '../lib/firebase_options.dart';
import '../lib/services/firebase/firebase_signaling_adapter.dart';
import '../lib/services/rain_runtime_controller.dart';

const bool runIntegrationTests =
    bool.fromEnvironment('RUN_RAIN_INTEGRATION_TESTS');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Two-user end-to-end friend flow on Firebase emulator',
    () async {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      final dbAlice = RainDatabase(NativeDatabase.memory());
      final dbBob = RainDatabase(NativeDatabase.memory());

      final adapterAlice = FirebaseSignalingAdapter(useEmulator: true);
      final adapterBob = FirebaseSignalingAdapter(useEmulator: true);

      try {
        await adapterAlice.register('alice', 'alicepw');
        await adapterBob.register('bob', 'bobpw');
        await adapterAlice.login('alice', 'alicepw');
        await adapterBob.login('bob', 'bobpw');

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

        await runtimeAlice.sendFriendRequest('bob');

        final inbound = await adapterBob.onFriendRequest('bob').first;
        expect(inbound, 'alice');

        await runtimeBob.acceptFriend('alice');

        final aliceBob = await runtimeAlice.friendStore.loadFriend('bob');
        final bobAlice = await runtimeBob.friendStore.loadFriend('alice');
        expect(aliceBob != null, isTrue);
        expect(aliceBob!.state, FriendState.friend);
        expect(bobAlice != null, isTrue);
        expect(bobAlice!.state, FriendState.friend);
      } finally {
        await adapterAlice.dispose();
        await adapterBob.dispose();
        await dbAlice.close();
        await dbBob.close();
      }
    },
    skip: runIntegrationTests ? null : 'Requires Firebase emulators',
  );
}
