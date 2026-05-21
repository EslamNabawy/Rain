import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain_core/rain_core.dart';

import 'utils/firebase_emulator_signaling_adapter.dart';

const bool runIntegrationTests = bool.fromEnvironment(
  'RUN_RAIN_INTEGRATION_TESTS',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!runIntegrationTests) return;
    HttpOverrides.global = null;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    if (!runIntegrationTests) return;
    HttpOverrides.global = null;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  test(
    'Two-user end-to-end friend flow on Firebase emulator',
    () async {
      final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final alice = 'alice$runId';
      final bob = 'bob$runId';

      final dbAlice = RainDatabase(NativeDatabase.memory());
      final dbBob = RainDatabase(NativeDatabase.memory());

      final adapterAlice = FirebaseEmulatorSignalingAdapter();
      final adapterBob = FirebaseEmulatorSignalingAdapter();

      try {
        await adapterAlice.register(alice, 'alicepw');
        await adapterBob.register(bob, 'bob123');
        await adapterAlice.login(alice, 'alicepw');
        await adapterBob.login(bob, 'bob123');

        final aliceIdentity = RainIdentity(
          username: alice,
          displayName: 'Alice',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.female,
        );
        final bobIdentity = RainIdentity(
          username: bob,
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
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
          friendRequestRefreshInterval: const Duration(milliseconds: 50),
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
          friendRequestRefreshInterval: const Duration(milliseconds: 50),
        );

        await runtimeAlice.start();
        await runtimeBob.start();

        await runtimeAlice.sendFriendRequest(bob);

        final inbound = await adapterBob.onFriendRequest(bob).first;
        expect(inbound, alice);

        await runtimeBob.acceptFriend(alice);

        await Future<void>.delayed(const Duration(milliseconds: 250));

        final aliceBob = await runtimeAlice.friendStore.loadFriend(bob);
        final bobAlice = await runtimeBob.friendStore.loadFriend(alice);
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
