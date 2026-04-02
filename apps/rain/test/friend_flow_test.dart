import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/services/noop_signaling_adapter.dart';
import 'package:rain/services/rain_runtime_controller.dart';
import 'package:rain_core/rain_core.dart';

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
        gender: RainGender.female,
      );
    });

    tearDown(() async {
      await db.close();
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

        final requestReceived = _nextString(adapter.onFriendRequest('bob'));
        await runtime.sendFriendRequest('bob');
        expect(await requestReceived, 'alice');

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

        final requestReceived = _nextString(adapter.onFriendRequest('bob'));
        await runtime.acceptFriend('bob');
        expect(await requestReceived, 'alice');

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

      final inboundRequest = _nextString(adapter.onFriendRequest('alice'));
      await adapter.writeFriendRequest('alice', 'charlie');
      expect(await inboundRequest, 'charlie');
      await _waitForFriendState(db, 'charlie', FriendState.pendingIncoming);

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

        final inboundRequest =
            _nextString(adapter.onFriendRequest('charlie'));
        await runtime.acceptFriend('charlie');
        expect(await inboundRequest, 'alice');
        await _waitForFriendState(db, 'charlie', FriendState.friend);

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

Future<void> _waitForFriendState(
  RainDatabase db,
  String username,
  FriendState expectedState,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final rows = await db.select(db.friends).get();
    final match = rows.any(
      (row) => row.username == username && row.state == expectedState.name,
    );
    if (match) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Timed out waiting for @$username to become ${expectedState.name}.');
}

Future<String> _nextString(Stream<String> stream) {
  final completer = Completer<String>();
  late final StreamSubscription<String> subscription;

  subscription = stream.listen(
    (String value) async {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
      await subscription.cancel();
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    },
  );

  return completer.future;
}
