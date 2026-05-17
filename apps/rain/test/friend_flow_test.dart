import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
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
        await adapter.register('bob', 'bobpw');
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
        final result = await runtime.sendFriendRequest('bob');
        expect(await requestReceived, 'alice');
        expect(result, FriendRequestResult.sent);

        final rows = await db.select(db.friends).get();
        final hasBob = rows.any(
          (r) => r.username == 'bob' && r.state == 'pendingOutgoing',
        );
        expect(hasBob, isTrue);
      },
    );

    test(
      'sendFriendRequest removes stale local friendship before sending a new request',
      () async {
        final adapter = NoopSignalingAdapter();
        await adapter.register('bob', 'bobpw');
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

        final result = await runtime.sendFriendRequest('bob');

        expect(result, FriendRequestResult.sent);
        final friend = await FriendStore(db).loadFriend('bob');
        expect(friend?.state, FriendState.pendingOutgoing);
      },
    );

    test(
      'sendFriendRequest accepts an existing incoming request instead of leaving split state',
      () async {
        final adapter = NoopSignalingAdapter();
        await adapter.register('bob', 'bobpw');
        await adapter.writeFriendRequest('alice', 'bob');

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

        final result = await runtime.sendFriendRequest('bob');

        expect(result, FriendRequestResult.acceptedExisting);
        expect(await adapter.loadAcceptedFriends('alice'), contains('bob'));
        expect(await adapter.loadAcceptedFriends('bob'), contains('alice'));
        final friend = await FriendStore(db).loadFriend('bob');
        expect(friend?.state, FriendState.friend);
      },
    );

    test(
      'sendFriendRequest rejects unknown user without local pending row',
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

        await expectLater(
          runtime.sendFriendRequest('bob'),
          throwsA(
            isA<Exception>().having(
              (Exception error) => error.toString(),
              'message',
              contains('was not found'),
            ),
          ),
        );
        expect(await db.select(db.friends).get(), isEmpty);
      },
    );

    test(
      'acceptFriend updates state to Friend and uses existing displayName',
      () async {
        final adapter = NoopSignalingAdapter();
        await adapter.register('bob', 'bobpw');
        await adapter.writeFriendRequest('alice', 'bob');
        await db
            .into(db.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'bob',
                displayName: 'Bob',
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

        await runtime.acceptFriend('bob');

        final rows = await db.select(db.friends).get();
        final hasBobFriend = rows.any(
          (r) =>
              r.username == 'bob' &&
              r.state == 'friend' &&
              r.displayName == 'Bob',
        );
        expect(hasBobFriend, isTrue);
        expect(await adapter.loadAcceptedFriends('alice'), contains('bob'));
      },
    );

    test(
      'acceptFriend does not create a local friend when backend persistence fails',
      () async {
        final adapter = FailingFriendshipNoopSignalingAdapter();
        await adapter.writeFriendRequest('alice', 'bob');
        await db
            .into(db.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'bob',
                displayName: 'Bob',
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

        await expectLater(
          runtime.acceptFriend('bob'),
          throwsA(
            isA<Exception>().having(
              (Exception error) => error.toString(),
              'message',
              contains('friendship persistence failed'),
            ),
          ),
        );

        final friend = await FriendStore(db).loadFriend('bob');
        expect(friend?.state, FriendState.pendingIncoming);
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
      'incoming friend request refresh loop recovers when live stream does not emit',
      () async {
        final adapter = SilentFriendRequestAdapter();
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
          friendRequestRefreshInterval: const Duration(milliseconds: 10),
        );

        await runtime.start();
        await adapter.writeFriendRequest('alice', 'charlie');
        await _waitForFriendState(db, 'charlie', FriendState.pendingIncoming);
      },
    );

    test(
      'durable friendship sync updates the sender after acceptance',
      () async {
        final adapter = RecordingNoopSignalingAdapter();
        await adapter.register('charlie', 'charliepw');

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
          friendRequestRefreshInterval: const Duration(milliseconds: 10),
        );
        await runtime.sendFriendRequest('charlie');
        await runtime.start();
        await adapter.upsertFriendship('alice', 'charlie');
        await adapter.deleteFriendRequest('charlie', 'alice');
        await _waitForFriendState(db, 'charlie', FriendState.friend);

        final rows = await db.select(db.friends).get();
        final isFriend = rows.any(
          (r) =>
              r.username == 'charlie' &&
              r.state == 'friend' &&
              r.displayName == 'charlie',
        );
        expect(isFriend, isTrue);
        expect(adapter.savedFriendships, contains('alice::charlie'));
      },
    );

    test(
      'acceptance updates the requester live without restart or polling',
      () async {
        final adapter = RecordingNoopSignalingAdapter();
        final bobDb = RainDatabase(NativeDatabase.memory());
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: 0,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter);

        try {
          await aliceRuntime.start();
          await bobRuntime.start();

          await aliceRuntime.sendFriendRequest('bob');
          await _waitForFriendState(db, 'bob', FriendState.pendingOutgoing);
          await _waitForFriendState(
            bobDb,
            'alice',
            FriendState.pendingIncoming,
          );

          await bobRuntime.acceptFriend('alice');

          await _waitForFriendState(db, 'bob', FriendState.friend);
          await _waitForFriendState(bobDb, 'alice', FriendState.friend);
        } finally {
          await aliceRuntime.dispose();
          await bobRuntime.dispose();
          await bobDb.close();
        }
      },
    );

    test(
      'sendFriendRequest to self throws even with whitespace or case',
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
        await expectLater(
          runtime.sendFriendRequest(' Alice '),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('blockFriend clears backend requests in both directions', () async {
      final adapter = RecordingNoopSignalingAdapter();
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

      await runtime.blockFriend('bob');

      expect(
        adapter.deletedRequests,
        containsAll(<String>['bob->alice', 'alice->bob']),
      );
      expect(adapter.deletedFriendships, contains('alice::bob'));
    });

    test(
      'unfriend removes backend friendship, local row, and session',
      () async {
        final adapter = RecordingNoopSignalingAdapter();
        await adapter.register('bob', 'bobpw');
        await adapter.upsertFriendship('alice', 'bob');
        await FriendStore(db).upsertFriend(
          username: 'bob',
          displayName: 'Bob',
          state: FriendState.friend,
        );
        final brain = TestSessionManager();
        await brain.connect('bob');
        final runtime = RainRuntimeController(
          selfIdentity: alice,
          adapter: adapter,
          brain: brain,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
        );

        await runtime.unfriend(' Bob ');

        expect(adapter.deletedFriendships, contains('alice::bob'));
        expect(
          await adapter.loadAcceptedFriends('alice'),
          isNot(contains('bob')),
        );
        expect(await FriendStore(db).loadFriend('bob'), isNull);
        expect(brain.getSession('bob'), isNull);
      },
    );

    test(
      'rejectFriend cleans up pending peer tracking and session hooks',
      () async {
        final adapter = RecordingNoopSignalingAdapter();
        await adapter.register('bob', 'bobpw');
        final brain = TestSessionManager();
        final runtime = RainRuntimeController(
          selfIdentity: alice,
          adapter: adapter,
          brain: brain,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
        );

        await runtime.sendFriendRequest('bob');
        await brain.connect('bob');
        await runtime.rejectFriend('bob');

        expect(adapter.deletedRequests, contains('alice->bob'));
        expect(await FriendStore(db).loadFriend('bob'), isNull);
        expect(brain.disconnectedPeers, contains('bob'));
        expect(brain.unregisteredPeers, contains('bob'));
        expect(brain.getSession('bob'), isNull);
      },
    );

    test('blockFriend closes and unregisters any peer session', () async {
      final adapter = RecordingNoopSignalingAdapter();
      final brain = TestSessionManager();
      await brain.connect('bob');
      final runtime = RainRuntimeController(
        selfIdentity: alice,
        adapter: adapter,
        brain: brain,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
      );

      await runtime.blockFriend('bob');

      expect(brain.disconnectedPeers, contains('bob'));
      expect(brain.unregisteredPeers, contains('bob'));
      expect(brain.getSession('bob'), isNull);
    });

    test(
      'blockFriend publishes blocked state to the other user live',
      () async {
        final adapter = RecordingNoopSignalingAdapter();
        final bobDb = RainDatabase(NativeDatabase.memory());
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: 0,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter);

        try {
          await adapter.upsertFriendship('alice', 'bob');
          await aliceRuntime.start();
          await bobRuntime.start();
          await _waitForFriendState(db, 'bob', FriendState.friend);
          await _waitForFriendState(bobDb, 'alice', FriendState.friend);

          await aliceRuntime.blockFriend('bob');

          await _waitForFriendState(db, 'bob', FriendState.blocked);
          await _waitForFriendState(bobDb, 'alice', FriendState.blockedByPeer);
          expect(
            await adapter.loadAcceptedFriends('bob'),
            isNot(contains('alice')),
          );
        } finally {
          await aliceRuntime.dispose();
          await bobRuntime.dispose();
          await bobDb.close();
        }
      },
    );

    test(
      'unblock clears backend block so a new friend request is delivered',
      () async {
        final adapter = RecordingNoopSignalingAdapter();
        final bobDb = RainDatabase(NativeDatabase.memory());
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: 0,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter);

        try {
          await adapter.upsertFriendship('alice', 'bob');
          await aliceRuntime.start();
          await bobRuntime.start();
          await _waitForFriendState(db, 'bob', FriendState.friend);
          await _waitForFriendState(bobDb, 'alice', FriendState.friend);

          await aliceRuntime.blockFriend('bob');
          await _waitForFriendState(bobDb, 'alice', FriendState.blockedByPeer);
          await expectLater(
            bobRuntime.sendFriendRequest('alice'),
            throwsA(
              isA<Exception>().having(
                (Exception error) => error.toString(),
                'message',
                contains('blocked you'),
              ),
            ),
          );

          await aliceRuntime.unblockFriend('bob');
          await _waitForFriendRemoval(db, 'bob');
          await _waitForFriendRemoval(bobDb, 'alice');

          await bobRuntime.sendFriendRequest('alice');

          await _waitForFriendState(db, 'bob', FriendState.pendingIncoming);
          await _waitForFriendState(
            bobDb,
            'alice',
            FriendState.pendingOutgoing,
          );
        } finally {
          await aliceRuntime.dispose();
          await bobRuntime.dispose();
          await bobDb.close();
        }
      },
    );

    test('blocked inbound request is deleted from the backend flow', () async {
      final adapter = RecordingNoopSignalingAdapter();
      await db
          .into(db.friends)
          .insert(
            FriendsCompanion.insert(
              username: 'charlie',
              displayName: 'Charlie',
              state: 'blocked',
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
      await adapter.writeFriendRequest('alice', 'charlie');
      await _waitForDeletedRequest(adapter, 'charlie->alice');

      final friend = await FriendStore(db).loadFriend('charlie');
      expect(friend?.state, FriendState.blocked);
    });

    test('unblockFriend removes the blocked relationship', () async {
      final adapter = NoopSignalingAdapter();
      await db
          .into(db.friends)
          .insert(
            FriendsCompanion.insert(
              username: 'david',
              displayName: 'David',
              state: 'blocked',
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

      await runtime.unblockFriend('david');

      final friend = await FriendStore(db).loadFriend('david');
      expect(friend, isNull);
    });

    test('sendMessage rejects non-friends', () async {
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

      await expectLater(
        runtime.sendMessage('erin', 'hello'),
        throwsA(isA<StateError>()),
      );
      expect(await db.select(db.messages).get(), isEmpty);
      expect(await db.select(db.queuedMessages).get(), isEmpty);
    });

    test(
      'sendMessage queues while disconnected without registering or connecting',
      () async {
        final adapter = NoopSignalingAdapter();
        final brain = TestSessionManager();
        await adapter.register('bob', 'bobpw');
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
        final messageStore = MessageStore(db);
        final offlineQueueStore = OfflineQueueStore(db);
        final runtime = RainRuntimeController(
          selfIdentity: alice,
          adapter: adapter,
          brain: brain,
          database: db,
          friendStore: FriendStore(db),
          messageStore: messageStore,
          offlineQueueStore: offlineQueueStore,
          messageDeliveryService: MessageDeliveryService(
            messageStore: messageStore,
            offlineQueueStore: offlineQueueStore,
          ),
        );

        await runtime.sendMessage('bob', 'hello while offline');

        expect(brain.registeredPeers, isEmpty);
        expect(brain.connectedPeers, isEmpty);
        final messages = await db.select(db.messages).get();
        expect(messages, hasLength(1));
        expect(messages.single.status, MessageStatus.queued.name);
        final queued = await db.select(db.queuedMessages).get();
        expect(queued, hasLength(1));
        expect(queued.single.status, QueuedMessageStatus.queued.name);
      },
    );

    test('resendMessage stays queued while disconnected', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      await adapter.register('bob', 'bobpw');
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
      final messageStore = MessageStore(db);
      final offlineQueueStore = OfflineQueueStore(db);
      final deliveryService = MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      );
      final envelope = await messageStore.composeOutgoingEnvelope(
        from: 'alice',
        to: 'bob',
        content: 'retry later',
      );
      await deliveryService.queueOutgoing(envelope);
      final runtime = RainRuntimeController(
        selfIdentity: alice,
        adapter: adapter,
        brain: brain,
        database: db,
        friendStore: FriendStore(db),
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
        messageDeliveryService: deliveryService,
      );

      await runtime.resendMessage(envelope.id);

      expect(brain.registeredPeers, isEmpty);
      expect(brain.connectedPeers, isEmpty);
      final message = (await db.select(db.messages).get()).single;
      expect(message.status, MessageStatus.queued.name);
      final queued = (await db.select(db.queuedMessages).get()).single;
      expect(queued.status, QueuedMessageStatus.queued.name);
    });

    test(
      'start, presence, and refresh do not open peer links automatically',
      () async {
        final adapter = NoopSignalingAdapter();
        final brain = TestSessionManager();
        await adapter.register('bob', 'bobpw');
        await adapter.upsertFriendship('alice', 'bob');
        final runtime = RainRuntimeController(
          selfIdentity: alice,
          adapter: adapter,
          brain: brain,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
          friendRequestRefreshInterval: Duration.zero,
        );

        await runtime.start();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await adapter.setPresence('bob', true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await runtime.refreshRelationships();
        await runtime.refreshRelationships(onlyUsername: 'bob');

        expect(brain.registeredPeers, isEmpty);
        expect(brain.connectedPeers, isEmpty);
        await runtime.dispose();
      },
    );

    test('disconnectPeer unregisters the peer session', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      await adapter.register('bob', 'bobpw');
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
        brain: brain,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
      );

      await runtime.connectPeer('bob', interactive: true);
      await runtime.disconnectPeer('bob');

      expect(brain.disconnectedPeers, <String>['bob']);
      expect(brain.unregisteredPeers, <String>['bob']);
      expect(brain.getSession('bob'), isNull);
    });

    test('connectPeer interactive rejects pending relationships', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      await adapter.register('bob', 'bobpw');
      await adapter.writeFriendRequest('bob', 'alice');
      await db
          .into(db.friends)
          .insert(
            FriendsCompanion.insert(
              username: 'bob',
              displayName: 'Bob',
              state: 'pendingOutgoing',
              addedAt: 0,
            ),
          );

      final runtime = RainRuntimeController(
        selfIdentity: alice,
        adapter: adapter,
        brain: brain,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
        friendRequestRefreshInterval: const Duration(milliseconds: 10),
      );

      await expectLater(
        runtime.connectPeer('bob', interactive: true),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.toString(),
            'message',
            contains('accept your friend request'),
          ),
        ),
      );
      await runtime.dispose();
      expect(brain.registeredPeers, isEmpty);
      expect(brain.connectedPeers, isEmpty);
    });

    test('connectPeer registers and connects a friend', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      await adapter.register('bob', 'bobpw');
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
        brain: brain,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
      );

      await runtime.connectPeer('bob', interactive: true);

      expect(brain.registeredPeers, <String>['bob']);
      expect(brain.connectedPeers, <String>['bob']);
    });

    test(
      'connectPeer waitForConnected succeeds only after the session is connected',
      () async {
        final adapter = NoopSignalingAdapter();
        final brain = TestSessionManager();
        await adapter.register('bob', 'bobpw');
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
          brain: brain,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
        );

        final connectFuture = runtime.connectPeer(
          'bob',
          interactive: true,
          waitForConnected: true,
          connectionTimeout: const Duration(seconds: 1),
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));
        brain.markConnected('bob');

        await connectFuture;
        expect(brain.connectedPeers, <String>['bob']);
      },
    );

    test(
      'connectPeer waitForConnected surfaces session failure detail',
      () async {
        final adapter = NoopSignalingAdapter();
        final brain = TestSessionManager();
        await adapter.register('bob', 'bobpw');
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
          brain: brain,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
        );

        final connectFuture = runtime.connectPeer(
          'bob',
          interactive: true,
          waitForConnected: true,
          connectionTimeout: const Duration(seconds: 1),
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));
        brain.markFailed(
          'bob',
          'Encrypted signaling data could not be read. Use the same latest build.',
        );

        await expectLater(
          connectFuture,
          throwsA(
            isA<StateError>().having(
              (StateError error) => error.toString(),
              'message',
              contains('Encrypted signaling data could not be read'),
            ),
          ),
        );
      },
    );

    test('connectPeer interactive rejects offline friends', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      await adapter.register('bob', 'bobpw');
      await adapter.setPresence('bob', false);
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
        brain: brain,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
      );

      await expectLater(
        runtime.connectPeer('bob', interactive: true),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.toString(),
            'message',
            contains('offline'),
          ),
        ),
      );

      expect(brain.connectedPeers, isEmpty);
    });

    test(
      'connectPeer waitForConnected times out when no session is established',
      () async {
        final adapter = NoopSignalingAdapter();
        final brain = TestSessionManager();
        await adapter.register('bob', 'bobpw');
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
          brain: brain,
          database: db,
          friendStore: FriendStore(db),
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
          messageDeliveryService: MessageDeliveryService(
            messageStore: MessageStore(db),
            offlineQueueStore: OfflineQueueStore(db),
          ),
        );

        await expectLater(
          runtime.connectPeer(
            'bob',
            interactive: true,
            waitForConnected: true,
            connectionTimeout: const Duration(milliseconds: 250),
          ),
          throwsA(
            isA<StateError>().having(
              (StateError error) => error.toString(),
              'message',
              allOf(contains('timed out'), contains('both users')),
            ),
          ),
        );
        expect(brain.getSession('bob'), isNull);
      },
    );

    test(
      'start rebuilds pending outgoing requests from backend state',
      () async {
        final adapter = NoopSignalingAdapter();
        await adapter.register('bob', 'bobpw');
        await adapter.writeFriendRequest('bob', 'alice');

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
          friendRequestRefreshInterval: const Duration(milliseconds: 10),
        );

        await runtime.start();
        await _waitForFriendState(db, 'bob', FriendState.pendingOutgoing);
      },
    );

    test(
      'start removes stale local relationships that no longer exist on the backend',
      () async {
        final adapter = NoopSignalingAdapter();
        await adapter.register('bob', 'bobpw');
        await db
            .into(db.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'bob',
                displayName: 'Bob',
                state: 'pendingOutgoing',
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
          friendRequestRefreshInterval: const Duration(milliseconds: 10),
        );

        await runtime.start();
        await _waitForFriendRemoval(db, 'bob');
      },
    );

    test(
      'start reconciles durable backend friendship into local friend state',
      () async {
        final adapter = NoopSignalingAdapter();
        await adapter.register('alice', 'alicepw');
        await adapter.register('bob', 'bobpw');

        final aliceRuntime = RainRuntimeController(
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

        await aliceRuntime.sendFriendRequest('bob');
        await adapter.upsertFriendship('alice', 'bob');
        await adapter.deleteFriendRequest('bob', 'alice');

        final beforeStart = await aliceRuntime.friendStore.loadFriend('bob');
        expect(beforeStart?.state, FriendState.pendingOutgoing);

        await aliceRuntime.start();
        await _waitForFriendState(db, 'bob', FriendState.friend);
      },
    );
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

RainRuntimeController _runtimeFor(
  RainDatabase database,
  RainIdentity identity,
  NoopSignalingAdapter adapter, {
  SessionManager? brain,
}) {
  final messageStore = MessageStore(database);
  final offlineQueueStore = OfflineQueueStore(database);
  return RainRuntimeController(
    selfIdentity: identity,
    adapter: adapter,
    brain: brain,
    database: database,
    friendStore: FriendStore(database),
    messageStore: messageStore,
    offlineQueueStore: offlineQueueStore,
    messageDeliveryService: MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
    ),
  );
}

Future<void> _waitForDeletedRequest(
  RecordingNoopSignalingAdapter adapter,
  String requestKey,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (adapter.deletedRequests.contains(requestKey)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Timed out waiting for backend request cleanup: $requestKey.');
}

Future<void> _waitForFriendRemoval(RainDatabase db, String username) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final friend = await FriendStore(db).loadFriend(username);
    if (friend == null) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Timed out waiting for @$username to be removed.');
}

class RecordingNoopSignalingAdapter extends NoopSignalingAdapter {
  final List<String> deletedRequests = <String>[];
  final List<String> writtenRequests = <String>[];
  final List<String> savedFriendships = <String>[];
  final List<String> deletedFriendships = <String>[];

  @override
  Future<void> deleteFriendRequest(String to, String from) async {
    deletedRequests.add('$from->$to');
    await super.deleteFriendRequest(to, from);
  }

  @override
  Future<void> writeFriendRequest(String to, String from) async {
    writtenRequests.add('$from->$to');
    await super.writeFriendRequest(to, from);
  }

  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) async {
    savedFriendships.add(_friendshipKey(firstUser, secondUser));
    await super.upsertFriendship(firstUser, secondUser);
  }

  @override
  Future<void> deleteFriendship(String firstUser, String secondUser) async {
    deletedFriendships.add(_friendshipKey(firstUser, secondUser));
    await super.deleteFriendship(firstUser, secondUser);
  }

  String _friendshipKey(String firstUser, String secondUser) {
    final users = <String>[firstUser, secondUser]..sort();
    return '${users[0]}::${users[1]}';
  }
}

class SilentFriendRequestAdapter extends NoopSignalingAdapter {
  @override
  Stream<String> onFriendRequest(String username) =>
      const Stream<String>.empty();
}

class FailingFriendshipNoopSignalingAdapter extends NoopSignalingAdapter {
  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) {
    throw Exception('friendship persistence failed');
  }
}

class TestSessionManager implements SessionManager {
  final List<String> registeredPeers = <String>[];
  final List<String> connectedPeers = <String>[];
  final List<String> disconnectedPeers = <String>[];
  final List<String> unregisteredPeers = <String>[];
  final Map<String, Session> _sessions = <String, Session>{};
  final StreamController<Session> _peerConnectedController =
      StreamController<Session>.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _peerMessageController =
      StreamController<SessionMessage>.broadcast();
  final StreamController<Session> _sessionChangedController =
      StreamController<Session>.broadcast();

  @override
  Stream<Session> get onPeerConnected => _peerConnectedController.stream;

  @override
  Stream<String> get onPeerDisconnected => _peerDisconnectedController.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _peerMessageController.stream;

  @override
  Stream<Session> get onSessionChanged => _sessionChangedController.stream;

  @override
  Future<Session> connect(String peerId) async {
    connectedPeers.add(peerId);
    final session = Session(
      peerId: peerId,
      state: SessionState.connecting,
      connectionType: ConnectionType.signaling,
      sender: (_) {},
    );
    _sessions[peerId] = session;
    _sessionChangedController.add(session);
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    disconnectedPeers.add(peerId);
    _sessions.remove(peerId);
    _peerDisconnectedController.add(peerId);
  }

  @override
  Session? getSession(String peerId) => _sessions[peerId];

  @override
  List<Session> getSessions() => _sessions.values.toList(growable: false);

  @override
  Future<void> registerPeer(String peerId) async {
    registeredPeers.add(peerId);
  }

  @override
  void sendControl(String peerId, String data) {}

  @override
  Future<void> unregisterPeer(String peerId) async {
    unregisteredPeers.add(peerId);
    _sessions.remove(peerId);
  }

  void markConnected(String peerId) {
    final existing = _sessions[peerId];
    if (existing == null) {
      return;
    }
    final session = existing.copyWith(
      state: SessionState.connected,
      connectedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _sessions[peerId] = session;
    _sessionChangedController.add(session);
    _peerConnectedController.add(session);
  }

  void markFailed(String peerId, String error) {
    final existing = _sessions[peerId];
    if (existing == null) {
      return;
    }
    final session = existing.copyWith(
      state: SessionState.failed,
      phase: SessionPhase.failed,
      detail: 'Failed',
      error: error,
    );
    _sessions[peerId] = session;
    _sessionChangedController.add(session);
  }
}
