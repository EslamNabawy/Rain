import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:rain_core/rain_core.dart';

import '../lib/services/rain_runtime_controller.dart';
import '../lib/services/noop_signaling_adapter.dart';
// Uses rain_core exports for database and stores

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Friend flow', () {
    late RainDatabase db;
    late RainIdentity alice;

    setUp(() {
      db = RainDatabase(NativeDatabase.memory());
      alice = RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
      );
    });

    test(
      'sendFriendRequest creates pendingOutgoing and triggers adapter',
      () async {
        final adapter = NoopSignalingAdapter();
        final runtime = RainRuntimeController(
          selfIdentity: alice,
          adapter: adapter,
          brain: null,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
        );

        // Listen for the inbound friend request event for 'bob' before sending
        // to validate that the adapter emits correctly.
        final stream = adapter.onFriendRequest('bob');
        final sendFuture = runtime.sendFriendRequest('bob');
        await sendFuture;

        // Expect the event to carry the from-username 'alice'
        await expectLater(stream, emits('alice'));
        // Also verify that a pendingOutgoing row is inserted for bob
        final rows = await db.select(db.friends).get();
        final hasBob = rows.any(
          (r) => r.username == 'bob' && r.state == 'pendingOutgoing',
        );
        expect(hasBob, isTrue);
      },
    );

    test(
      'acceptFriend updates state to Friend and uses existing displayName',
      () async {
        final adapter = NoopSignalingAdapter();
        // Pre-insert an existing friend row for bob with a displayName of 'Bob'
        await db
            .into(db.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'bob',
                displayName: 'Bob',
                state: 'friend',
                addedAt: 0,
              ),
            );

        final runtime = RainRuntimeController(
          selfIdentity: alice,
          adapter: adapter,
          brain: null,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
        );

        // Listen for the adapter action when accepting a friend
        final stream = adapter.onFriendRequest('bob');
        await runtime.acceptFriend('bob');
        await expectLater(stream, emits('alice'));

        // Verify the database updated row
        final rows = await db.select(db.friends).get();
        final hasBobFriend = rows.any(
          (r) =>
              r.username == 'bob' &&
              r.state == 'friend' &&
              r.displayName == 'Bob',
        );
        expect(hasBobFriend, isTrue);
      },
    );

    test('inbound friend request is processed to pendingIncoming', () async {
      final adapter = NoopSignalingAdapter();
      final runtime = RainRuntimeController(
        selfIdentity: alice,
        adapter: adapter,
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
      );
      await runtime.start();

      // Simulate an inbound friend request from 'charlie' to 'alice'
      await adapter.writeFriendRequest('alice', 'charlie');
      // Allow the runtime to process the inbound event
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final rows = await db.select(db.friends).get();
      final hasCharlie = rows.any(
        (r) => r.username == 'charlie' && r.state == 'pendingIncoming',
      );
      expect(hasCharlie, isTrue);
    });

    test(
      'inbound acceptance signals outcome and results in friend state',
      () async {
        final adapter = NoopSignalingAdapter();
        // preload an inbound candidate to Charlie
        await db
            .into(db.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'charlie',
                displayName: 'Charlie',
                state: 'pendingIncoming',
                addedAt: 0,
              ),
            );

        final runtime = RainRuntimeController(
          selfIdentity: alice,
          adapter: adapter,
          brain: null,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
        );
        await runtime.start();

        final inboundStream = adapter.onFriendRequest('charlie');
        await runtime.acceptFriend('charlie');
        await expectLater(inboundStream, emits('alice'));

        final rows = await db.select(db.friends).get();
        final isFriend = rows.any(
          (r) => r.username == 'charlie' && r.state == 'friend',
        );
        expect(isFriend, isTrue);
      },
    );

    test('sendFriendRequest to self throws', () {
      final adapter = NoopSignalingAdapter();
      final runtime = RainRuntimeController(
        selfIdentity: alice,
        adapter: adapter,
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
      );
      expect(runtime.sendFriendRequest('alice'), throwsA(isA<Exception>()));
    });
  });
}
