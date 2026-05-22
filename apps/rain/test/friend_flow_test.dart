import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCSessionDescription;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Two-user flow tests intentionally model separate devices with separate
    // in-memory databases in the same isolate.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

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

    test(
      'sendFile while disconnected does not connect or create a transfer',
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

        await expectLater(
          runtime.sendFile(
            peerId: 'bob',
            fileName: 'note.txt',
            fileSize: 1,
            openRead: () => Stream<List<int>>.value(<int>[1]),
          ),
          throwsA(isA<StateError>()),
        );

        expect(brain.registeredPeers, isEmpty);
        expect(brain.connectedPeers, isEmpty);
        expect(await db.select(db.messages).get(), isEmpty);
        expect(await db.select(db.fileTransfers).get(), isEmpty);
      },
    );

    test(
      'startVoiceCall auto-connects and sends invite over control channel',
      () async {
        final adapter = NoopSignalingAdapter();
        final brain = TestSessionManager();
        await adapter.register('bob', 'bobpw');
        await adapter.upsertFriendship('alice', 'bob');
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
        final runtime = _runtimeFor(db, alice, adapter, brain: brain);

        final callStarted = runtime.startVoiceCall('bob');
        await _waitForCondition(
          () => brain.connectedPeers.contains('bob'),
          'voice call to request peer connection',
        );
        brain.markConnected('bob');
        await callStarted;

        expect(runtime.voiceCallState.phase, VoiceCallPhase.outgoingRinging);
        expect(brain.registeredPeers, contains('bob'));
        expect(brain.sentControlPayloads, hasLength(1));
        final invite = VoiceCallFrame.tryDecode(
          brain.sentControlPayloads.single,
        );
        expect(invite?.type, VoiceCallFrameType.invite);
        expect(invite?.from, 'alice');
        expect(invite?.to, 'bob');
      },
    );

    test('incoming voice invite can be rejected', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      await adapter.register('bob', 'bobpw');
      await adapter.upsertFriendship('alice', 'bob');
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
      final runtime = _runtimeFor(db, alice, adapter, brain: brain);
      addTearDown(runtime.dispose);

      await runtime.start();
      brain.emitControlMessage(
        'bob',
        VoiceCallFrame(
          type: VoiceCallFrameType.invite,
          callId: 'call-1',
          from: 'bob',
          to: 'alice',
          sentAt: DateTime.now().millisecondsSinceEpoch,
        ).encode(),
      );
      await _waitForCondition(
        () => runtime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
        'incoming voice invite to ring',
      );

      await runtime.rejectVoiceCall();

      expect(runtime.voiceCallState.phase, VoiceCallPhase.idle);
      final reject = VoiceCallFrame.tryDecode(brain.sentControlPayloads.last);
      expect(reject?.type, VoiceCallFrameType.reject);
      expect(reject?.callId, 'call-1');
    });

    test('active file transfer blocks starting a voice call', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      final transferStore = FileTransferStore(db);
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
      await transferStore.upsert(
        FileTransferRecord(
          id: 'transfer-1',
          peerId: 'bob',
          messageId: 'message-1',
          direction: FileTransferDirection.outgoing,
          fileName: 'busy.txt',
          fileSize: 1,
          bytesTransferred: 0,
          state: FileTransferState.sending,
          createdAt: 0,
          updatedAt: 0,
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
        fileTransferStore: transferStore,
      );

      await expectLater(
        runtime.startVoiceCall('bob'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('Finish the active file transfer'),
          ),
        ),
      );
    });

    test('active voice call blocks new outgoing file transfer', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      await adapter.register('bob', 'bobpw');
      await adapter.upsertFriendship('alice', 'bob');
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
      await brain.connect('bob');
      brain.markConnected('bob');
      final runtime = _runtimeFor(db, alice, adapter, brain: brain);
      addTearDown(runtime.dispose);

      await runtime.start();
      await runtime.startVoiceCall('bob');
      brain.emitControlMessage(
        'bob',
        VoiceCallFrame(
          type: VoiceCallFrameType.accept,
          callId: runtime.voiceCallState.callId!,
          from: 'bob',
          to: 'alice',
          sentAt: DateTime.now().millisecondsSinceEpoch,
        ).encode(),
      );
      await _waitForCondition(
        () => brain.mediaOfferPeers.contains('bob'),
        'voice media offer to be created',
      );
      final offer = brain.sentControlPayloads
          .map(VoiceCallFrame.tryDecode)
          .whereType<VoiceCallFrame>()
          .lastWhere((frame) => frame.type == VoiceCallFrameType.offer);
      brain.emitControlMessage(
        'bob',
        VoiceCallFrame(
          type: VoiceCallFrameType.answer,
          callId: runtime.voiceCallState.callId!,
          from: 'bob',
          to: 'alice',
          sentAt: DateTime.now().millisecondsSinceEpoch,
          sdp: 'media-answer-bob',
          sdpType: 'answer',
          mediaSeq: offer.mediaSeq,
        ).encode(),
      );
      await _waitForCondition(
        () => runtime.voiceCallState.phase == VoiceCallPhase.active,
        'voice call to become active',
      );

      await expectLater(
        runtime.sendFile(
          peerId: 'bob',
          fileName: 'note.txt',
          fileSize: 1,
          openRead: () => Stream<List<int>>.value(<int>[1]),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('Finish the call before sending files'),
          ),
        ),
      );
    });

    test('stale media answers are ignored by media sequence', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      await adapter.register('bob', 'bobpw');
      await adapter.upsertFriendship('alice', 'bob');
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
      await brain.connect('bob');
      brain.markConnected('bob');
      final runtime = _runtimeFor(db, alice, adapter, brain: brain);
      addTearDown(runtime.dispose);

      await runtime.start();
      await runtime.startVoiceCall('bob');
      brain.emitControlMessage(
        'bob',
        VoiceCallFrame(
          type: VoiceCallFrameType.accept,
          callId: runtime.voiceCallState.callId!,
          from: 'bob',
          to: 'alice',
          sentAt: DateTime.now().millisecondsSinceEpoch,
        ).encode(),
      );
      await _waitForCondition(
        () => brain.mediaOfferPeers.contains('bob'),
        'voice media offer to be created',
      );
      final offer = brain.sentControlPayloads
          .map(VoiceCallFrame.tryDecode)
          .whereType<VoiceCallFrame>()
          .lastWhere((frame) => frame.type == VoiceCallFrameType.offer);
      final answer = VoiceCallFrame(
        type: VoiceCallFrameType.answer,
        callId: runtime.voiceCallState.callId!,
        from: 'bob',
        to: 'alice',
        sentAt: DateTime.now().millisecondsSinceEpoch,
        sdp: 'media-answer-bob',
        sdpType: 'answer',
        mediaSeq: offer.mediaSeq,
      ).encode();

      brain.emitControlMessage('bob', answer);
      await _waitForCondition(
        () => runtime.voiceCallState.phase == VoiceCallPhase.active,
        'voice call to become active',
      );
      brain.emitControlMessage('bob', answer);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(brain.appliedMediaAnswerPeers, <String>['bob']);
    });

    test(
      'media answer failure sends failed hangup and preserves chat session',
      () async {
        final adapter = NoopSignalingAdapter();
        final brain = TestSessionManager();
        final recordedErrors = <Object>[];
        final recordedSources = <String>[];
        await adapter.register('bob', 'bobpw');
        await adapter.upsertFriendship('alice', 'bob');
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
        await brain.connect('bob');
        brain.markConnected('bob');
        final runtime = _runtimeFor(
          db,
          alice,
          adapter,
          brain: brain,
          errorRecorder:
              (
                Object error,
                StackTrace? stackTrace, {
                required String source,
                required bool fatal,
                String? flutterLibrary,
                String? flutterContext,
              }) {
                recordedErrors.add(error);
                recordedSources.add(source);
              },
        );
        addTearDown(runtime.dispose);

        await runtime.start();
        await runtime.startVoiceCall('bob');
        brain.emitControlMessage(
          'bob',
          VoiceCallFrame(
            type: VoiceCallFrameType.accept,
            callId: runtime.voiceCallState.callId!,
            from: 'bob',
            to: 'alice',
            sentAt: DateTime.now().millisecondsSinceEpoch,
          ).encode(),
        );
        await _waitForCondition(
          () => brain.mediaOfferPeers.contains('bob'),
          'voice media offer to be created',
        );
        final offer = brain.sentControlPayloads
            .map(VoiceCallFrame.tryDecode)
            .whereType<VoiceCallFrame>()
            .lastWhere((frame) => frame.type == VoiceCallFrameType.offer);
        brain.applyMediaAnswerError = StateError(
          'Unable to RTCPeerConnection::setRemoteDescription: '
          'peerConnectionSetRemoteDescription failed with m-line mismatch',
        );

        brain.emitControlMessage(
          'bob',
          VoiceCallFrame(
            type: VoiceCallFrameType.answer,
            callId: runtime.voiceCallState.callId!,
            from: 'bob',
            to: 'alice',
            sentAt: DateTime.now().millisecondsSinceEpoch,
            sdp: 'bad-media-answer-bob',
            sdpType: 'answer',
            mediaSeq: offer.mediaSeq,
          ).encode(),
        );
        await _waitForCondition(
          () => runtime.voiceCallState.phase == VoiceCallPhase.failed,
          'voice call media failure to surface',
        );

        final hangup = brain.sentControlPayloads
            .map(VoiceCallFrame.tryDecode)
            .whereType<VoiceCallFrame>()
            .lastWhere((frame) => frame.type == VoiceCallFrameType.hangup);
        expect(hangup.reasonCode, 'failed');
        expect(brain.stoppedAudioPeers, contains('bob'));
        expect(brain.disconnectedPeers, isEmpty);
        expect(recordedSources, contains('voice-call-media'));
        expect(
          recordedErrors.single.toString(),
          contains('setRemoteDescription'),
        );
      },
    );

    test('cancel during outgoing send is not overwritten as failed', () async {
      final adapter = NoopSignalingAdapter();
      await adapter.register('bob', 'bobpw');
      await adapter.upsertFriendship('alice', 'bob');
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
      final brain = TestSessionManager();
      await brain.connect('bob');
      brain.markConnected('bob');
      final transferStore = FileTransferStore(db);
      final source = StreamController<List<int>>();
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
        fileTransferStore: transferStore,
      );

      try {
        await runtime.start();
        await runtime.sendFile(
          peerId: 'bob',
          fileName: 'video.mp4',
          fileSize: 1,
          openRead: () => source.stream,
        );
        final transfer = (await transferStore.loadPeerTransfers('bob')).single;

        brain.emitFileMessage(
          'bob',
          FileTransferFrame.accept(transfer.id).encode(),
        );
        await _waitForTransferState(db, transfer.id, FileTransferState.sending);

        await runtime.cancelFileTransfer(transfer.id);
        await _waitForTransferState(
          db,
          transfer.id,
          FileTransferState.canceled,
        );

        source.add(<int>[7]);
        await source.close();
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final canceled = await transferStore.loadById(transfer.id);
        expect(canceled?.state, FileTransferState.canceled);
        expect(canceled?.error, 'Canceled.');
      } finally {
        if (!source.isClosed) {
          await source.close();
        }
        await runtime.dispose();
      }
    });

    test('incoming file chunks are finalized before complete frames', () async {
      final adapter = NoopSignalingAdapter();
      await adapter.register('bob', 'bobpw');
      await adapter.upsertFriendship('alice', 'bob');
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
      final brain = TestSessionManager();
      await brain.connect('bob');
      brain.markConnected('bob');
      final tempDir = Directory.systemTemp.createTempSync(
        'rain_file_receive_test_',
      );
      final transferStore = DelayingFileTransferStore(db);
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
        fileTransferStore: transferStore,
        documentsDirectoryProvider: () async => tempDir,
      );

      try {
        await runtime.start();
        final offer = FileTransferFrame.offer(
          transferId: 'transfer-1',
          messageId: 'message-1',
          fileName: 'hello.txt',
          fileSize: 3,
          sentAt: DateTime.now().millisecondsSinceEpoch,
          seq: 0,
        );
        brain.emitFileMessage('bob', offer.encode());
        await _waitForTransferState(
          db,
          'transfer-1',
          FileTransferState.offered,
        );
        await runtime.acceptFileTransfer('transfer-1');
        await _waitForTransferState(
          db,
          'transfer-1',
          FileTransferState.receiving,
        );

        transferStore.delayNextLoadById();
        brain
          ..emitFileMessage(
            'bob',
            FileTransferFrame.chunk(
              transferId: 'transfer-1',
              index: 0,
              offset: 0,
              byteCount: 3,
            ).encode(),
          )
          ..emitFileMessage('bob', Uint8List.fromList(<int>[1, 2, 3]))
          ..emitFileMessage(
            'bob',
            FileTransferFrame.complete(
              transferId: 'transfer-1',
              finalByteCount: 3,
              sha256:
                  '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
            ).encode(),
          );

        await _waitForTransferState(
          db,
          'transfer-1',
          FileTransferState.completed,
        );
        final transfer = await transferStore.loadById('transfer-1');
        expect(transfer?.error, isNull);
        expect(transfer?.bytesTransferred, 3);
        final receivedFile = File(transfer!.localPath!);
        expect(await receivedFile.exists(), isTrue);
        expect(await receivedFile.readAsBytes(), <int>[1, 2, 3]);
        expect(
          brain.sentFilePayloads,
          contains(
            FileTransferFrame.received(
              transferId: 'transfer-1',
              finalByteCount: 3,
              sha256:
                  '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
            ).encode(),
          ),
        );
      } finally {
        await runtime.dispose();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test(
      'incoming file packet carries chunk metadata and bytes together',
      () async {
        final adapter = NoopSignalingAdapter();
        await adapter.register('bob', 'bobpw');
        await adapter.upsertFriendship('alice', 'bob');
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
        final brain = TestSessionManager();
        await brain.connect('bob');
        brain.markConnected('bob');
        final tempDir = Directory.systemTemp.createTempSync(
          'rain_file_packet_receive_test_',
        );
        final transferStore = FileTransferStore(db);
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
          fileTransferStore: transferStore,
          documentsDirectoryProvider: () async => tempDir,
        );

        try {
          await runtime.start();
          brain.emitFileMessage(
            'bob',
            FileTransferFrame.offer(
              transferId: 'packet-transfer',
              messageId: 'packet-message',
              fileName: 'packet.bin',
              fileSize: 4,
              sentAt: DateTime.now().millisecondsSinceEpoch,
              seq: 0,
            ).encode(),
          );
          await _waitForTransferState(
            db,
            'packet-transfer',
            FileTransferState.offered,
          );
          await runtime.acceptFileTransfer('packet-transfer');
          await _waitForTransferState(
            db,
            'packet-transfer',
            FileTransferState.receiving,
          );

          final payload = Uint8List.fromList(<int>[9, 8, 7, 6]);
          brain
            ..emitFileMessage(
              'bob',
              FileTransferChunkPacket(
                frame: FileTransferFrame.chunk(
                  transferId: 'packet-transfer',
                  index: 0,
                  offset: 0,
                  byteCount: payload.lengthInBytes,
                ),
                payload: payload,
              ).encode(),
            )
            ..emitFileMessage(
              'bob',
              FileTransferFrame.complete(
                transferId: 'packet-transfer',
                finalByteCount: 4,
                sha256:
                    '63d987d1c6d69751c17297f410f5b3547a65d096a8993b35bcb4f9cad054f176',
              ).encode(),
            );

          await _waitForTransferState(
            db,
            'packet-transfer',
            FileTransferState.completed,
          );
          final transfer = await transferStore.loadById('packet-transfer');
          final receivedFile = File(transfer!.localPath!);
          expect(await receivedFile.readAsBytes(), <int>[9, 8, 7, 6]);
        } finally {
          await runtime.dispose();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        }
      },
    );

    test('zero-byte incoming files complete without a chunk temp file', () async {
      final adapter = NoopSignalingAdapter();
      await adapter.register('bob', 'bobpw');
      await adapter.upsertFriendship('alice', 'bob');
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
      final brain = TestSessionManager();
      await brain.connect('bob');
      brain.markConnected('bob');
      final tempDir = Directory.systemTemp.createTempSync(
        'rain_empty_file_receive_test_',
      );
      final transferStore = FileTransferStore(db);
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
        fileTransferStore: transferStore,
        documentsDirectoryProvider: () async => tempDir,
      );

      try {
        await runtime.start();
        brain.emitFileMessage(
          'bob',
          FileTransferFrame.offer(
            transferId: 'empty-transfer',
            messageId: 'empty-message',
            fileName: 'empty.txt',
            fileSize: 0,
            sentAt: DateTime.now().millisecondsSinceEpoch,
            seq: 0,
          ).encode(),
        );
        await _waitForTransferState(
          db,
          'empty-transfer',
          FileTransferState.offered,
        );
        await runtime.acceptFileTransfer('empty-transfer');
        brain.emitFileMessage(
          'bob',
          FileTransferFrame.complete(
            transferId: 'empty-transfer',
            finalByteCount: 0,
            sha256:
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
          ).encode(),
        );

        await _waitForTransferState(
          db,
          'empty-transfer',
          FileTransferState.completed,
        );
        final transfer = await transferStore.loadById('empty-transfer');
        final receivedFile = File(transfer!.localPath!);
        expect(await receivedFile.exists(), isTrue);
        expect(await receivedFile.length(), 0);
      } finally {
        await runtime.dispose();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

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
      'start and refresh register accepted friends for passive answering only',
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

        expect(brain.registeredPeers, <String>['bob']);
        expect(brain.connectedPeers, isEmpty);
        final guard = brain.incomingOfferGuards['bob'];
        expect(guard, isNotNull);
        var decision = await guard!('bob');
        expect(decision.allowed, isTrue);

        await runtime.disconnectPeer('bob');
        await runtime.refreshRelationships(onlyUsername: 'bob');
        decision = await guard('bob');

        expect(brain.registeredPeers, <String>['bob']);
        expect(brain.unregisteredPeers, <String>['bob']);
        expect(decision.allowed, isFalse);
        expect(decision.reason, contains('Manual disconnect'));
        await runtime.dispose();
      },
    );

    test('passive incoming offer guard rejects blocked friends', () async {
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
      await runtime.refreshRelationships(onlyUsername: 'bob');
      final guard = brain.incomingOfferGuards['bob'];
      expect(guard, isNotNull);
      expect((await guard!('bob')).allowed, isTrue);

      await runtime.blockFriend('bob');
      final decision = await guard('bob');

      expect(brain.unregisteredPeers, contains('bob'));
      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('blocked'));
      await runtime.dispose();
    });

    test('passive incoming offer guard rejects removed friends', () async {
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
      await runtime.refreshRelationships(onlyUsername: 'bob');
      final guard = brain.incomingOfferGuards['bob'];
      expect(guard, isNotNull);
      expect((await guard!('bob')).allowed, isTrue);

      await runtime.unfriend('bob');
      final decision = await guard('bob');

      expect(brain.unregisteredPeers, contains('bob'));
      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('no longer in your friends list'));
      await runtime.dispose();
    });

    test('passive listener cap limits accepted friend registrations', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
      for (final username in <String>['bob', 'cara', 'dan']) {
        await adapter.register(username, '${username}pw');
        await adapter.upsertFriendship('alice', username);
      }
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
        maxPassivePeerListeners: 2,
      );

      await runtime.start();
      await runtime.refreshRelationships();

      final snapshot = runtime.connectionCoordinatorSnapshotFor('bob');
      expect(snapshot.passiveListenerCount, 2);
      expect(snapshot.passiveListenerLimit, 2);
      expect(brain.incomingOfferGuards, hasLength(2));
      await runtime.dispose();
    });

    test('failed peer attempts back off before retrying', () async {
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
        initialConnectionRetryBackoff: const Duration(seconds: 30),
        maxConnectionRetryBackoff: const Duration(seconds: 30),
      );

      await runtime.start();
      await runtime.connectPeer('bob', interactive: true);
      brain.markFailed('bob', 'ICE failed');
      await pumpEventQueue();

      await expectLater(
        runtime.connectPeer('bob', interactive: true),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('cooling down'),
          ),
        ),
      );
      final snapshot = runtime.connectionCoordinatorSnapshotFor('bob');
      expect(snapshot.retryAttempt, 1);
      expect(snapshot.nextRetryAt, isNotNull);
      await runtime.dispose();
    });

    test('manual retry bypasses failed-attempt cooldown', () async {
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
        initialConnectionRetryBackoff: const Duration(seconds: 30),
        maxConnectionRetryBackoff: const Duration(seconds: 30),
      );

      await runtime.start();
      await runtime.connectPeer('bob', interactive: true);
      brain.markFailed('bob', 'ICE failed');
      await pumpEventQueue();

      await runtime.connectPeer(
        'bob',
        interactive: true,
        bypassRetryBackoff: true,
      );

      expect(brain.connectedPeers, <String>['bob', 'bob']);
      expect(
        runtime.connectionCoordinatorSnapshotFor('bob').nextRetryAt,
        isNull,
      );
      await runtime.dispose();
    });

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

    test('connectPeer can try through stale offline presence', () async {
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

      await runtime.connectPeer(
        'bob',
        interactive: true,
        allowStalePresence: true,
      );

      expect(brain.registeredPeers, <String>['bob']);
      expect(brain.connectedPeers, <String>['bob']);
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

Future<void> _waitForTransferState(
  RainDatabase db,
  String transferId,
  FileTransferState expectedState,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  final store = FileTransferStore(db);
  while (DateTime.now().isBefore(deadline)) {
    final transfer = await store.loadById(transferId);
    if (transfer?.state == expectedState) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  final transfer = await store.loadById(transferId);
  fail(
    'Timed out waiting for $transferId to become ${expectedState.name}; '
    'last state was ${transfer?.state.name}.',
  );
}

Future<void> _waitForCondition(
  bool Function() condition,
  String description,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  fail('Timed out waiting for $description.');
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
  RuntimeErrorRecorder? errorRecorder,
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
    errorRecorder: errorRecorder,
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

class DelayingFileTransferStore extends FileTransferStore {
  DelayingFileTransferStore(super.database);

  bool _delayNextLoad = false;

  void delayNextLoadById() {
    _delayNextLoad = true;
  }

  @override
  Future<FileTransferRecord?> loadById(String id) async {
    if (_delayNextLoad) {
      _delayNextLoad = false;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return super.loadById(id);
  }
}

class TestSessionManager implements SessionManager {
  final List<String> registeredPeers = <String>[];
  final List<String> connectedPeers = <String>[];
  final List<String> disconnectedPeers = <String>[];
  final List<String> unregisteredPeers = <String>[];
  final List<String> startedAudioPeers = <String>[];
  final List<String> stoppedAudioPeers = <String>[];
  final List<String> mediaOfferPeers = <String>[];
  final List<String> appliedMediaOfferPeers = <String>[];
  final List<String> appliedMediaAnswerPeers = <String>[];
  final List<String> sentFilePayloads = <String>[];
  final List<String> sentControlPayloads = <String>[];
  final Map<String, bool> mutedPeers = <String, bool>{};
  Object? createMediaOfferError;
  Object? applyMediaOfferError;
  Object? applyMediaAnswerError;
  final Map<String, Session> _sessions = <String, Session>{};
  final StreamController<Session> _peerConnectedController =
      StreamController<Session>.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _peerMessageController =
      StreamController<SessionMessage>.broadcast();
  final StreamController<SessionRemoteTrack> _remoteTrackController =
      StreamController<SessionRemoteTrack>.broadcast();
  final StreamController<Session> _sessionChangedController =
      StreamController<Session>.broadcast();
  final StreamController<IncomingOfferRejection>
  _incomingOfferRejectedController =
      StreamController<IncomingOfferRejection>.broadcast();
  final Map<String, IncomingOfferGuard> incomingOfferGuards =
      <String, IncomingOfferGuard>{};

  @override
  Stream<Session> get onPeerConnected => _peerConnectedController.stream;

  @override
  Stream<String> get onPeerDisconnected => _peerDisconnectedController.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _peerMessageController.stream;

  @override
  Stream<SessionRemoteTrack> get onRemoteTrack => _remoteTrackController.stream;

  @override
  Stream<Session> get onSessionChanged => _sessionChangedController.stream;

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      _incomingOfferRejectedController.stream;

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
  Future<void> recoverConnection(
    String peerId, {
    String reason = 'Network changed. Restarting peer connection.',
  }) async {}

  @override
  Future<void> recoverConnections({
    String reason = 'Network changed. Restarting peer connections.',
  }) async {}

  @override
  Session? getSession(String peerId) => _sessions[peerId];

  @override
  List<Session> getSessions() => _sessions.values.toList(growable: false);

  @override
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {
    registeredPeers.add(peerId);
    if (incomingOfferGuard != null) {
      incomingOfferGuards[peerId] = incomingOfferGuard;
    }
  }

  @override
  void sendControl(String peerId, String data) {
    sentControlPayloads.add(data);
  }

  @override
  void send(String peerId, SessionChannel channel, Object data) {
    if (channel == SessionChannel.file && data is String) {
      sentFilePayloads.add(data);
    }
  }

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {}

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) => true;

  @override
  Future<void> startLocalAudio(String peerId) async {
    startedAudioPeers.add(peerId);
  }

  @override
  Future<void> stopLocalAudio(String peerId) async {
    stoppedAudioPeers.add(peerId);
  }

  @override
  Future<void> setMicrophoneMuted(String peerId, {required bool muted}) async {
    mutedPeers[peerId] = muted;
  }

  @override
  Future<RTCSessionDescription> createMediaOffer(String peerId) async {
    mediaOfferPeers.add(peerId);
    final error = createMediaOfferError;
    if (error != null) {
      throw error;
    }
    return RTCSessionDescription('media-offer-$peerId', 'offer');
  }

  @override
  Future<RTCSessionDescription> applyMediaOffer(
    String peerId,
    RTCSessionDescription offer,
  ) async {
    appliedMediaOfferPeers.add(peerId);
    final error = applyMediaOfferError;
    if (error != null) {
      throw error;
    }
    return RTCSessionDescription('media-answer-$peerId', 'answer');
  }

  @override
  Future<void> applyMediaAnswer(
    String peerId,
    RTCSessionDescription answer,
  ) async {
    appliedMediaAnswerPeers.add(peerId);
    final error = applyMediaAnswerError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> unregisterPeer(String peerId) async {
    unregisteredPeers.add(peerId);
    incomingOfferGuards.remove(peerId);
    _sessions.remove(peerId);
  }

  void markConnected(String peerId, {bool isOfferOwner = true}) {
    final existing = _sessions[peerId];
    if (existing == null) {
      return;
    }
    final session = existing.copyWith(
      state: SessionState.connected,
      connectedAt: DateTime.now().millisecondsSinceEpoch,
      isOfferOwner: isOfferOwner,
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

  void emitFileMessage(String peerId, Object data) {
    _peerMessageController.add(
      SessionMessage(
        channel: SessionChannel.file,
        data: data,
        receivedAt: DateTime.now(),
        peerId: peerId,
      ),
    );
  }

  void emitControlMessage(String peerId, Object data) {
    _peerMessageController.add(
      SessionMessage(
        channel: SessionChannel.control,
        data: data,
        receivedAt: DateTime.now(),
        peerId: peerId,
      ),
    );
  }
}
