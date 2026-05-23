import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show MediaStream, MediaStreamTrack, RTCSessionDescription;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:protocol_brain/protocol_brain.dart' as protocol;
import 'package:protocol_brain/testing.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/runtime/video_call_renderers.dart';
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

    test('startVoiceCall requires Firebase voice signaling', () async {
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

      await expectLater(
        runtime.startVoiceCall('bob'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('Voice calls require Firebase voice signaling'),
          ),
        ),
      );

      expect(runtime.voiceCallState.phase, VoiceCallPhase.idle);
      expect(brain.registeredPeers, isEmpty);
      expect(brain.connectedPeers, isEmpty);
      expect(brain.startedAudioPeers, isEmpty);
      expect(brain.mediaOfferPeers, isEmpty);
      expect(brain.sentControlPayloads, isEmpty);
    });

    test('legacy control-channel voice invite is ignored', () async {
      final adapter = NoopSignalingAdapter();
      final brain = TestSessionManager();
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
              recordedSources.add(source);
            },
      );
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
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(runtime.voiceCallState.phase, VoiceCallPhase.idle);
      expect(brain.startedAudioPeers, isEmpty);
      expect(brain.sentControlPayloads, isEmpty);
      expect(recordedSources, contains('voice-call-legacy-control'));
    });

    test('active file transfer still blocks frozen voice call start', () async {
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
      addTearDown(runtime.dispose);

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

      expect(brain.registeredPeers, isEmpty);
      expect(brain.sentControlPayloads, isEmpty);
    });

    test(
      'startVoiceCall creates Firebase voice room without peer connect',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
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
        await runtime.startVoiceCall('bob');

        expect(runtime.voiceCallState.phase, VoiceCallPhase.outgoingRinging);
        expect(adapter.rooms.values.single.caller, 'alice');
        expect(adapter.rooms.values.single.callee, 'bob');
        expect(
          adapter.rooms.values.single.status,
          VoiceCallSignalingStatus.ringing,
        );
        expect(brain.startedAudioPeers, <String>['bob']);
        expect(brain.connectedPeers, isEmpty);
        expect(brain.sentControlPayloads, isEmpty);
      },
    );

    test(
      'Firebase voice signaling reaches active without chat peer link',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager();
        final bobBrain = TestSessionManager();
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
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
        await bobDb
            .into(bobDb.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'alice',
                displayName: 'Alice',
                state: 'friend',
                addedAt: 0,
              ),
            );
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter, brain: aliceBrain);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter, brain: bobBrain);
        addTearDown(aliceRuntime.dispose);
        addTearDown(bobRuntime.dispose);

        await aliceRuntime.start();
        await bobRuntime.start();
        await aliceRuntime.startVoiceCall('bob');
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase voice invite to ring on callee',
        );
        await bobRuntime.acceptVoiceCall();

        await _waitForCondition(
          () =>
              aliceRuntime.voiceCallState.phase == VoiceCallPhase.active &&
              bobRuntime.voiceCallState.phase == VoiceCallPhase.active,
          'Firebase voice call to become active on both peers',
        );

        expect(aliceBrain.connectedPeers, isEmpty);
        expect(bobBrain.connectedPeers, isEmpty);
        expect(
          adapter.rooms.values.single.status,
          VoiceCallSignalingStatus.connected,
        );

        await aliceRuntime.sendMessage('bob', 'chat still works');
        final queued = await db.select(db.queuedMessages).get();
        expect(queued, hasLength(1));
      },
    );

    test(
      'active Firebase voice call supports local deafen and output routing',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager();
        final bobBrain = TestSessionManager();
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
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
        await bobDb
            .into(bobDb.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'alice',
                displayName: 'Alice',
                state: 'friend',
                addedAt: 0,
              ),
            );
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter, brain: aliceBrain);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter, brain: bobBrain);
        addTearDown(aliceRuntime.dispose);
        addTearDown(bobRuntime.dispose);

        await aliceRuntime.start();
        await bobRuntime.start();
        await aliceRuntime.startVoiceCall('bob');
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase voice invite to ring on callee',
        );
        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.active,
          'Firebase voice call to become active before local audio controls',
        );

        await aliceRuntime.setVoiceCallDeafened(true);
        expect(aliceRuntime.voiceCallState.isDeafened, isTrue);
        expect(aliceBrain.deafenedPeers, <String>['bob:true']);
        expect(aliceBrain.mutedPeers, isEmpty);
        expect(adapter.rooms.values.single.muted.values, everyElement(isFalse));

        await aliceRuntime.setVoiceCallOutputRoute(
          VoiceCallOutputRoute.speaker,
        );
        expect(aliceBrain.outputRoutes['bob'], <VoiceMediaOutputRoute>[
          VoiceMediaOutputRoute.speaker,
        ]);
        expect(
          aliceRuntime.voiceCallState.outputRoute,
          VoiceCallOutputRoute.speaker,
        );

        aliceBrain.audioOutputRouteError = UnsupportedError(
          'speaker route unavailable',
        );
        await aliceRuntime.setVoiceCallOutputRoute(
          VoiceCallOutputRoute.bluetooth,
        );

        expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.active);
        expect(
          aliceRuntime.voiceCallState.outputRoute,
          VoiceCallOutputRoute.speaker,
        );
        expect(
          aliceRuntime.voiceCallState.outputRouteWarning,
          'Audio route unavailable.',
        );

        await aliceRuntime.hangUpVoiceCall();
        expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.idle);
        expect(aliceRuntime.voiceCallState.isDeafened, isFalse);
        expect(
          aliceRuntime.voiceCallState.outputRoute,
          VoiceCallOutputRoute.systemDefault,
        );
      },
    );

    test('outgoing microphone denial writes no Firebase invite', () async {
      final adapter = RecordingVoiceSignalingAdapter();
      final brain = TestSessionManager()
        ..startLocalAudioError = StateError('Microphone permission denied');
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
      await expectLater(runtime.startVoiceCall('bob'), throwsStateError);

      expect(adapter.rooms, isEmpty);
      expect(runtime.voiceCallState.phase, VoiceCallPhase.failed);
      expect(
        runtime.voiceCallState.failureReason,
        VoiceCallFailureReason.microphoneDenied,
      );
    });

    test(
      'startVideoCall preflights mic and camera before Firebase invite',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
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
        final runtime = _runtimeFor(
          db,
          alice,
          adapter,
          brain: brain,
          videoCallRendererFactory: const _TestVideoCallRendererFactory(),
        );
        addTearDown(runtime.dispose);

        await runtime.start();
        await runtime.startVideoCall('bob');

        expect(runtime.voiceCallState.phase, VoiceCallPhase.outgoingRinging);
        expect(runtime.voiceCallState.isVideo, isTrue);
        expect(
          adapter.rooms.values.single.mediaMode,
          protocol.CallMediaMode.video,
        );
        expect(brain.startedAudioPeers, <String>['bob']);
        expect(brain.startedVideoPeers, <String>['bob']);
      },
    );

    test('outgoing camera denial writes no Firebase invite', () async {
      final adapter = RecordingVoiceSignalingAdapter();
      final brain = TestSessionManager()
        ..startLocalVideoError = const CallMediaException(
          CallMediaFailureReason.cameraDenied,
          'Camera permission is required.',
        );
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
      final runtime = _runtimeFor(
        db,
        alice,
        adapter,
        brain: brain,
        videoCallRendererFactory: const _TestVideoCallRendererFactory(),
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      await expectLater(
        runtime.startVideoCall('bob'),
        throwsA(isA<CallMediaException>()),
      );

      expect(adapter.rooms, isEmpty);
      expect(runtime.voiceCallState.phase, VoiceCallPhase.failed);
      expect(
        runtime.voiceCallState.failureReason,
        VoiceCallFailureReason.cameraDenied,
      );
      expect(brain.startedAudioPeers, <String>['bob']);
      expect(brain.startedVideoPeers, <String>['bob']);
    });

    test(
      'incoming video accept preflights camera before Firebase accept',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager();
        final bobBrain = TestSessionManager();
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
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
        await bobDb
            .into(bobDb.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'alice',
                displayName: 'Alice',
                state: 'friend',
                addedAt: 0,
              ),
            );
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(
          db,
          alice,
          adapter,
          brain: aliceBrain,
          videoCallRendererFactory: const _TestVideoCallRendererFactory(),
        );
        final bobRuntime = _runtimeFor(
          bobDb,
          bob,
          adapter,
          brain: bobBrain,
          videoCallRendererFactory: const _TestVideoCallRendererFactory(),
        );
        addTearDown(aliceRuntime.dispose);
        addTearDown(bobRuntime.dispose);

        await aliceRuntime.start();
        await bobRuntime.start();
        await aliceRuntime.startVideoCall('bob');
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase video invite to ring on callee',
        );
        expect(
          adapter.rooms.values.single.status,
          VoiceCallSignalingStatus.ringing,
        );

        await bobRuntime.acceptVoiceCall();

        expect(bobBrain.startedAudioPeers, <String>['alice']);
        expect(bobBrain.startedVideoPeers, <String>['alice']);
        await _waitForCondition(
          () =>
              adapter.rooms.values.single.status !=
              VoiceCallSignalingStatus.ringing,
          'Firebase video room to move beyond ringing after camera preflight',
        );
      },
    );

    test('remote camera denial maps to typed video failure', () async {
      final adapter = RecordingVoiceSignalingAdapter();
      final aliceBrain = TestSessionManager();
      final bobBrain = TestSessionManager()
        ..startLocalVideoError = const CallMediaException(
          CallMediaFailureReason.cameraDenied,
          'Camera permission is required.',
        );
      final bobDb = RainDatabase(NativeDatabase.memory());
      addTearDown(bobDb.close);
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
      await bobDb
          .into(bobDb.friends)
          .insert(
            FriendsCompanion.insert(
              username: 'alice',
              displayName: 'Alice',
              state: 'friend',
              addedAt: 0,
            ),
          );
      final bob = RainIdentity(
        username: 'bob',
        displayName: 'Bob',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        gender: RainGender.male,
      );
      final aliceRuntime = _runtimeFor(
        db,
        alice,
        adapter,
        brain: aliceBrain,
        videoCallRendererFactory: const _TestVideoCallRendererFactory(),
      );
      final bobRuntime = _runtimeFor(
        bobDb,
        bob,
        adapter,
        brain: bobBrain,
        videoCallRendererFactory: const _TestVideoCallRendererFactory(),
      );
      addTearDown(aliceRuntime.dispose);
      addTearDown(bobRuntime.dispose);

      await aliceRuntime.start();
      await bobRuntime.start();
      await aliceRuntime.startVideoCall('bob');
      await _waitForCondition(
        () => bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
        'Firebase video invite to ring before camera denial',
      );

      await expectLater(
        bobRuntime.acceptVoiceCall(),
        throwsA(isA<CallMediaException>()),
      );
      await _waitForCondition(
        () =>
            adapter.rooms.values.single.status ==
            VoiceCallSignalingStatus.failed,
        'Firebase video room to fail after callee camera denial',
      );
      expect(adapter.rooms.values.single.reasonCode, 'cameraDenied');
      await _waitForCondition(
        () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.failed,
        'caller to observe remote camera denial',
      );
      expect(
        aliceRuntime.voiceCallState.failureReason,
        VoiceCallFailureReason.remoteCameraDenied,
      );
    });

    test('active file transfer blocks starting a video call', () async {
      final adapter = RecordingVoiceSignalingAdapter();
      final brain = TestSessionManager();
      final transferStore = FileTransferStore(db);
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
        fileTransferStore: transferStore,
        videoCallRendererFactory: const _TestVideoCallRendererFactory(),
      );
      addTearDown(runtime.dispose);

      await expectLater(
        runtime.startVideoCall('bob'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('Finish the active file transfer'),
          ),
        ),
      );

      expect(adapter.rooms, isEmpty);
      expect(brain.callMediaConnections, isEmpty);
    });

    test(
      'active Firebase video call blocks file transfer and hangup releases media',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager();
        final bobBrain = TestSessionManager();
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
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
        await bobDb
            .into(bobDb.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'alice',
                displayName: 'Alice',
                state: 'friend',
                addedAt: 0,
              ),
            );
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(
          db,
          alice,
          adapter,
          brain: aliceBrain,
          videoCallRendererFactory: const _TestVideoCallRendererFactory(),
        );
        final bobRuntime = _runtimeFor(
          bobDb,
          bob,
          adapter,
          brain: bobBrain,
          videoCallRendererFactory: const _TestVideoCallRendererFactory(),
        );
        addTearDown(aliceRuntime.dispose);
        addTearDown(bobRuntime.dispose);

        await aliceRuntime.start();
        await bobRuntime.start();
        await aliceRuntime.startVideoCall('bob');
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase video invite to ring before file block check',
        );
        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.active,
          'Firebase video call to become active before file block check',
        );

        await expectLater(
          aliceRuntime.sendFile(
            peerId: 'bob',
            fileName: 'blocked.txt',
            fileSize: 1,
            openRead: () => Stream<List<int>>.value(<int>[1]),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains('Finish the call first'),
            ),
          ),
        );

        await aliceRuntime.hangUpVoiceCall();
        await _waitForCondition(
          () =>
              adapter.rooms.values.single.status ==
              VoiceCallSignalingStatus.ended,
          'Firebase video room to end after hangup',
        );
        expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.idle);
        expect(
          (aliceBrain.callMediaConnections['bob']! as _TestCallMediaConnection)
              .disposed,
          isTrue,
        );
        await _waitForCondition(
          () => bobRuntime.voiceCallState.phase == VoiceCallPhase.idle,
          'remote video call to clear after hangup',
        );

        await aliceRuntime.startVoiceCall('bob');
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'voice call to ring after video hangup',
        );
        expect(aliceRuntime.voiceCallState.isVideo, isFalse);
      },
    );

    test('active Firebase pair lock is surfaced as peer busy', () async {
      final adapter = RecordingVoiceSignalingAdapter();
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
      final now = DateTime.now().millisecondsSinceEpoch;
      await adapter.createOutgoingCall(
        callId: 'existing-call',
        caller: 'alice',
        callee: 'bob',
        createdAt: now,
        expiresAt: now + const Duration(minutes: 2).inMilliseconds,
      );
      final runtime = _runtimeFor(db, alice, adapter, brain: brain);
      addTearDown(runtime.dispose);

      await runtime.start();
      await expectLater(
        runtime.startVoiceCall('bob'),
        throwsA(isA<VoiceSignalingException>()),
      );

      expect(runtime.voiceCallState.phase, VoiceCallPhase.failed);
      expect(
        runtime.voiceCallState.failureReason,
        VoiceCallFailureReason.peerBusy,
      );
      expect(runtime.voiceCallState.detail, 'Peer is busy.');
      expect(adapter.rooms, hasLength(1));
      expect(adapter.rooms.values.single.callId, 'existing-call');
    });

    test(
      'incoming microphone denial fails Firebase room before accept',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager();
        final bobBrain = TestSessionManager()
          ..startLocalAudioError = StateError('Microphone permission denied');
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
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
        await bobDb
            .into(bobDb.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'alice',
                displayName: 'Alice',
                state: 'friend',
                addedAt: 0,
              ),
            );
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter, brain: aliceBrain);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter, brain: bobBrain);
        addTearDown(aliceRuntime.dispose);
        addTearDown(bobRuntime.dispose);

        await aliceRuntime.start();
        await bobRuntime.start();
        await aliceRuntime.startVoiceCall('bob');
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase voice invite to ring before mic denial',
        );

        await expectLater(bobRuntime.acceptVoiceCall(), throwsStateError);
        await _waitForCondition(
          () =>
              adapter.rooms.values.single.status ==
              VoiceCallSignalingStatus.failed,
          'Firebase voice room to fail after callee mic denial',
        );

        final room = adapter.rooms.values.single;
        expect(room.reasonCode, 'microphoneDenied');
        expect(bobRuntime.voiceCallState.phase, VoiceCallPhase.failed);
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'caller to see remote microphone denial',
        );
        expect(
          aliceRuntime.voiceCallState.failureReason,
          VoiceCallFailureReason.remoteMicrophoneDenied,
        );
      },
    );

    test(
      'active Firebase voice call blocks new outgoing file transfer',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager();
        final bobBrain = TestSessionManager();
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
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
        await bobDb
            .into(bobDb.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'alice',
                displayName: 'Alice',
                state: 'friend',
                addedAt: 0,
              ),
            );
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter, brain: aliceBrain);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter, brain: bobBrain);
        addTearDown(aliceRuntime.dispose);
        addTearDown(bobRuntime.dispose);

        await aliceRuntime.start();
        await bobRuntime.start();
        await aliceRuntime.startVoiceCall('bob');
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase voice invite to ring before file block check',
        );
        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.active,
          'Firebase voice call to become active before file block check',
        );

        await expectLater(
          aliceRuntime.sendFile(
            peerId: 'bob',
            fileName: 'blocked.txt',
            fileSize: 1,
            openRead: () => Stream<List<int>>.value(<int>[1]),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains('Finish the call first'),
            ),
          ),
        );
      },
    );

    test('dispose releases active Firebase voice room', () async {
      final adapter = RecordingVoiceSignalingAdapter();
      final aliceBrain = TestSessionManager();
      final bobBrain = TestSessionManager();
      final bobDb = RainDatabase(NativeDatabase.memory());
      addTearDown(bobDb.close);
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
      await bobDb
          .into(bobDb.friends)
          .insert(
            FriendsCompanion.insert(
              username: 'alice',
              displayName: 'Alice',
              state: 'friend',
              addedAt: 0,
            ),
          );
      final bob = RainIdentity(
        username: 'bob',
        displayName: 'Bob',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        gender: RainGender.male,
      );
      final aliceRuntime = _runtimeFor(db, alice, adapter, brain: aliceBrain);
      final bobRuntime = _runtimeFor(bobDb, bob, adapter, brain: bobBrain);
      addTearDown(aliceRuntime.dispose);
      addTearDown(bobRuntime.dispose);

      await aliceRuntime.start();
      await bobRuntime.start();
      await aliceRuntime.startVoiceCall('bob');
      await _waitForCondition(
        () => bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
        'Firebase voice invite to ring before dispose cleanup',
      );
      await bobRuntime.acceptVoiceCall();
      await _waitForCondition(
        () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.active,
        'Firebase voice call to become active before dispose cleanup',
      );

      await aliceRuntime.dispose();

      await _waitForCondition(
        () =>
            adapter.rooms.values.single.status ==
            VoiceCallSignalingStatus.ended,
        'Firebase voice room to end on runtime dispose',
      );
      final room = adapter.rooms.values.single;
      expect(room.endedBy, 'alice');
      expect(room.reason, 'Rain is closing.');
    });

    test(
      'network loss ends active Firebase voice call and clears busy lock',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager();
        final bobBrain = TestSessionManager();
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
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
        await bobDb
            .into(bobDb.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'alice',
                displayName: 'Alice',
                state: 'friend',
                addedAt: 0,
              ),
            );
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter, brain: aliceBrain);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter, brain: bobBrain);
        addTearDown(aliceRuntime.dispose);
        addTearDown(bobRuntime.dispose);

        await aliceRuntime.start();
        await bobRuntime.start();
        await aliceRuntime.startVoiceCall('bob');
        final callId = aliceRuntime.voiceCallState.callId!;
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase voice invite to ring before network loss test',
        );
        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () =>
              aliceRuntime.voiceCallState.phase == VoiceCallPhase.active &&
              bobRuntime.voiceCallState.phase == VoiceCallPhase.active,
          'Firebase voice call to become active before network loss',
        );

        expect(adapter.activePairLocks, hasLength(1));
        expect(aliceRuntime.voiceCallBlocksFileTransfer('bob'), isTrue);

        await aliceRuntime.handleNetworkLost(
          'Network connection lost. Call ended.',
        );

        await _waitForCondition(
          () =>
              adapter.rooms[callId]?.status == VoiceCallSignalingStatus.failed,
          'Firebase voice room to fail on network loss',
        );
        await _waitForCondition(
          () => bobRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'remote runtime to fail after peer network loss',
        );

        expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.failed);
        expect(
          aliceRuntime.voiceCallState.failureReason,
          VoiceCallFailureReason.networkLost,
        );
        expect(adapter.rooms[callId]?.reasonCode, 'networkLost');
        expect(adapter.activePairLocks, isEmpty);
        expect(aliceRuntime.voiceCallBlocksFileTransfer('bob'), isFalse);
        expect(aliceBrain.stoppedAudioPeers, contains('bob'));
        expect(bobBrain.stoppedAudioPeers, contains('alice'));
      },
    );

    test(
      'retry after failed Firebase media uses fresh call id and media session',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager()
          ..applyMediaAnswerError = StateError(
            'Unable to RTCPeerConnection::setRemoteDescription',
          );
        final bobBrain = TestSessionManager();
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
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
        await bobDb
            .into(bobDb.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'alice',
                displayName: 'Alice',
                state: 'friend',
                addedAt: 0,
              ),
            );
        final bob = RainIdentity(
          username: 'bob',
          displayName: 'Bob',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          gender: RainGender.male,
        );
        final aliceRuntime = _runtimeFor(db, alice, adapter, brain: aliceBrain);
        final bobRuntime = _runtimeFor(bobDb, bob, adapter, brain: bobBrain);
        addTearDown(aliceRuntime.dispose);
        addTearDown(bobRuntime.dispose);

        await aliceRuntime.start();
        await bobRuntime.start();
        await aliceRuntime.startVoiceCall('bob');
        final firstCallId = aliceRuntime.voiceCallState.callId!;
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'first Firebase voice invite to ring',
        );
        expect(aliceRuntime.voiceCallBlocksFileTransfer('bob'), isTrue);

        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'first Firebase voice call to fail media',
        );
        await _waitForCondition(
          () => adapter.activePairLocks.isEmpty,
          'failed Firebase voice call to clear active pair lock',
        );
        await _waitForCondition(
          () => bobRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'callee to observe failed Firebase voice call before retry',
        );
        expect(
          adapter.rooms[firstCallId]?.status,
          VoiceCallSignalingStatus.failed,
        );
        expect(aliceRuntime.voiceCallBlocksFileTransfer('bob'), isFalse);

        aliceBrain.applyMediaAnswerError = null;
        await aliceRuntime.startVoiceCall('bob');
        final secondCallId = aliceRuntime.voiceCallState.callId!;

        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'retry Firebase voice invite to ring',
        );

        expect(secondCallId, isNot(firstCallId));
        expect(adapter.activePairLocks.values.single.callId, secondCallId);
        expect(aliceBrain.startedAudioPeers, <String>['bob', 'bob']);
        expect(aliceRuntime.voiceCallBlocksFileTransfer('bob'), isTrue);
      },
    );

    group(
      'legacy control-channel voice signaling path',
      () {
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

            expect(
              runtime.voiceCallState.phase,
              VoiceCallPhase.outgoingRinging,
            );
            expect(brain.registeredPeers, contains('bob'));
            expect(brain.startedAudioPeers, contains('bob'));
            expect(brain.sentControlPayloads, hasLength(1));
            final invite = VoiceCallFrame.tryDecode(
              brain.sentControlPayloads.single,
            );
            expect(invite?.type, VoiceCallFrameType.invite);
            expect(invite?.from, 'alice');
            expect(invite?.to, 'bob');
          },
        );

        test(
          'startVoiceCall requests microphone before sending invite',
          () async {
            final adapter = NoopSignalingAdapter();
            final brain = TestSessionManager()
              ..startLocalAudioError = StateError(
                'Microphone permission denied',
              );
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

            final callStarted = runtime.startVoiceCall('bob');
            await _waitForCondition(
              () => brain.connectedPeers.contains('bob'),
              'voice call to request peer connection',
            );
            brain.markConnected('bob');

            await expectLater(
              callStarted,
              throwsA(
                isA<StateError>().having(
                  (error) => error.toString(),
                  'message',
                  contains('Microphone permission denied'),
                ),
              ),
            );

            expect(brain.startedAudioPeers, <String>['bob']);
            expect(brain.sentControlPayloads, isEmpty);
            expect(runtime.voiceCallState.phase, VoiceCallPhase.failed);
            expect(
              runtime.voiceCallState.failureReason,
              VoiceCallFailureReason.microphoneDenied,
            );
            expect(
              runtime.voiceCallState.detail,
              'Microphone permission required.',
            );
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
            () =>
                runtime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
            'incoming voice invite to ring',
          );

          await runtime.rejectVoiceCall();

          expect(runtime.voiceCallState.phase, VoiceCallPhase.idle);
          final reject = VoiceCallFrame.tryDecode(
            brain.sentControlPayloads.last,
          );
          expect(reject?.type, VoiceCallFrameType.reject);
          expect(reject?.callId, 'call-1');
        });

        test(
          'incoming voice retry from same peer replaces stale ringing call',
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
              () => runtime.voiceCallState.callId == 'call-1',
              'first incoming voice invite to ring',
            );

            brain.emitControlMessage(
              'bob',
              VoiceCallFrame(
                type: VoiceCallFrameType.invite,
                callId: 'call-2',
                from: 'bob',
                to: 'alice',
                sentAt: DateTime.now().millisecondsSinceEpoch,
              ).encode(),
            );
            await _waitForCondition(
              () => runtime.voiceCallState.callId == 'call-2',
              'same-peer voice retry to replace stale invite',
            );

            final frames = brain.sentControlPayloads
                .map(VoiceCallFrame.tryDecode)
                .whereType<VoiceCallFrame>()
                .toList(growable: false);
            expect(
              frames.where((frame) => frame.type == VoiceCallFrameType.busy),
              isEmpty,
            );
            expect(
              frames.any(
                (frame) =>
                    frame.type == VoiceCallFrameType.hangup &&
                    frame.callId == 'call-1',
              ),
              isTrue,
            );
            expect(
              runtime.voiceCallState.phase,
              VoiceCallPhase.incomingRinging,
            );
          },
        );

        test('duplicate incoming voice invite does not report busy', () async {
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
          final invite = VoiceCallFrame(
            type: VoiceCallFrameType.invite,
            callId: 'call-1',
            from: 'bob',
            to: 'alice',
            sentAt: DateTime.now().millisecondsSinceEpoch,
          ).encode();
          brain.emitControlMessage('bob', invite);
          await _waitForCondition(
            () => runtime.voiceCallState.callId == 'call-1',
            'incoming voice invite to ring',
          );

          brain.emitControlMessage('bob', invite);
          await Future<void>.delayed(const Duration(milliseconds: 80));

          final frames = brain.sentControlPayloads
              .map(VoiceCallFrame.tryDecode)
              .whereType<VoiceCallFrame>()
              .toList(growable: false);
          expect(
            frames.where((frame) => frame.type == VoiceCallFrameType.busy),
            isEmpty,
          );
          expect(runtime.voiceCallState.callId, 'call-1');
          expect(runtime.voiceCallState.phase, VoiceCallPhase.incomingRinging);
        });

        test(
          'acceptVoiceCall rejects before accept when microphone is denied',
          () async {
            final adapter = NoopSignalingAdapter();
            final brain = TestSessionManager()
              ..startLocalAudioError = StateError(
                'Microphone permission denied',
              );
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
              () =>
                  runtime.voiceCallState.phase ==
                  VoiceCallPhase.incomingRinging,
              'incoming voice invite to ring',
            );

            await expectLater(
              runtime.acceptVoiceCall(),
              throwsA(
                isA<StateError>().having(
                  (error) => error.toString(),
                  'message',
                  contains('Microphone permission denied'),
                ),
              ),
            );

            final frames = brain.sentControlPayloads
                .map(VoiceCallFrame.tryDecode)
                .whereType<VoiceCallFrame>()
                .toList(growable: false);
            expect(frames.map((frame) => frame.type), <VoiceCallFrameType>[
              VoiceCallFrameType.reject,
            ]);
            expect(frames.single.reasonCode, 'microphoneDenied');
            expect(frames.single.reason, 'Microphone permission required.');
            expect(runtime.voiceCallState.phase, VoiceCallPhase.failed);
            expect(
              runtime.voiceCallState.failureReason,
              VoiceCallFailureReason.microphoneDenied,
            );
            expect(
              runtime.voiceCallState.detail,
              'Microphone permission required.',
            );
          },
        );

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
          final invite = brain.sentControlPayloads
              .map(VoiceCallFrame.tryDecode)
              .whereType<VoiceCallFrame>()
              .lastWhere((frame) => frame.type == VoiceCallFrameType.invite);
          brain.emitControlMessage(
            'bob',
            VoiceCallFrame(
              type: VoiceCallFrameType.accept,
              callId: runtime.voiceCallState.callId!,
              from: 'bob',
              to: 'alice',
              sentAt: DateTime.now().millisecondsSinceEpoch,
              seq: 1,
              sessionEpoch: invite.sessionEpoch,
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
          expect(offer.sessionEpoch, invite.sessionEpoch);
          brain.emitControlMessage(
            'bob',
            VoiceCallFrame(
              type: VoiceCallFrameType.answer,
              callId: runtime.voiceCallState.callId!,
              from: 'bob',
              to: 'alice',
              sentAt: DateTime.now().millisecondsSinceEpoch,
              seq: 2,
              sessionEpoch: invite.sessionEpoch,
              sdp: 'media-answer-bob',
              sdpType: 'answer',
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
                contains('Finish the call first'),
              ),
            ),
          );
        });

        test('stale media answers are ignored by signaling sequence', () async {
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
          final invite = brain.sentControlPayloads
              .map(VoiceCallFrame.tryDecode)
              .whereType<VoiceCallFrame>()
              .lastWhere((frame) => frame.type == VoiceCallFrameType.invite);
          brain.emitControlMessage(
            'bob',
            VoiceCallFrame(
              type: VoiceCallFrameType.accept,
              callId: runtime.voiceCallState.callId!,
              from: 'bob',
              to: 'alice',
              sentAt: DateTime.now().millisecondsSinceEpoch,
              seq: 1,
              sessionEpoch: invite.sessionEpoch,
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
          expect(offer.sessionEpoch, invite.sessionEpoch);
          final answer = VoiceCallFrame(
            type: VoiceCallFrameType.answer,
            callId: runtime.voiceCallState.callId!,
            from: 'bob',
            to: 'alice',
            sentAt: DateTime.now().millisecondsSinceEpoch,
            seq: 2,
            sessionEpoch: invite.sessionEpoch,
            sdp: 'media-answer-bob',
            sdpType: 'answer',
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
            final invite = brain.sentControlPayloads
                .map(VoiceCallFrame.tryDecode)
                .whereType<VoiceCallFrame>()
                .lastWhere((frame) => frame.type == VoiceCallFrameType.invite);
            brain.emitControlMessage(
              'bob',
              VoiceCallFrame(
                type: VoiceCallFrameType.accept,
                callId: runtime.voiceCallState.callId!,
                from: 'bob',
                to: 'alice',
                sentAt: DateTime.now().millisecondsSinceEpoch,
                seq: 1,
                sessionEpoch: invite.sessionEpoch,
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
            expect(offer.sessionEpoch, invite.sessionEpoch);
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
                seq: 2,
                sessionEpoch: invite.sessionEpoch,
                sdp: 'bad-media-answer-bob',
                sdpType: 'answer',
              ).encode(),
            );
            await _waitForCondition(
              () => runtime.voiceCallState.phase == VoiceCallPhase.failed,
              'voice call media failure to surface',
            );

            expect(
              runtime.voiceCallState.detail,
              'Call media could not connect. Try again.',
            );
            final hangup = brain.sentControlPayloads
                .map(VoiceCallFrame.tryDecode)
                .whereType<VoiceCallFrame>()
                .lastWhere((frame) => frame.type == VoiceCallFrameType.hangup);
            expect(hangup.reason, 'Voice call media could not connect.');
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
      },
      skip:
          'Legacy control-channel voice path frozen until Firebase signaling.',
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
  VideoCallRendererFactory videoCallRendererFactory =
      const RtcVideoCallRendererFactory(),
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
    videoCallRendererFactory: videoCallRendererFactory,
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

class RecordingVoiceSignalingAdapter extends RecordingNoopSignalingAdapter
    implements VoiceSignalingAdapter {
  final FakeVoiceSignalingAdapter _voice = FakeVoiceSignalingAdapter();

  Map<String, VoiceCallRoom> get rooms => _voice.rooms;

  Map<String, VoiceActivePairLock> get activePairLocks =>
      _voice.activePairLocks;

  @override
  Future<void> acceptCall({
    required String callId,
    required String callee,
    required int acceptedAt,
  }) {
    return _voice.acceptCall(
      callId: callId,
      callee: callee,
      acceptedAt: acceptedAt,
    );
  }

  @override
  Future<VoiceCallRoom> createOutgoingCall({
    required String callId,
    required String caller,
    required String callee,
    required int createdAt,
    required int expiresAt,
    protocol.CallMediaMode mediaMode = protocol.CallMediaMode.audio,
  }) {
    return _voice.createOutgoingCall(
      callId: callId,
      caller: caller,
      callee: callee,
      createdAt: createdAt,
      expiresAt: expiresAt,
      mediaMode: mediaMode,
    );
  }

  @override
  Future<void> deleteCall(String callId) => _voice.deleteCall(callId);

  @override
  Future<void> dispose() async {
    await _voice.dispose();
    await super.dispose();
  }

  @override
  Future<void> endCall({
    required String callId,
    required String username,
    required VoiceCallSignalingStatus status,
    required int endedAt,
    String? reasonCode,
    String? reason,
  }) {
    return _voice.endCall(
      callId: callId,
      username: username,
      status: status,
      endedAt: endedAt,
      reasonCode: reasonCode,
      reason: reason,
    );
  }

  @override
  Future<VoiceCallRoom?> fetchCall(String callId) => _voice.fetchCall(callId);

  @override
  Future<void> markConnected({
    required String callId,
    required String username,
    required int connectedAt,
  }) {
    return _voice.markConnected(
      callId: callId,
      username: username,
      connectedAt: connectedAt,
    );
  }

  @override
  Future<void> setMuted({
    required String callId,
    required String username,
    required bool muted,
    required int updatedAt,
  }) {
    return _voice.setMuted(
      callId: callId,
      username: username,
      muted: muted,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> setCameraMuted({
    required String callId,
    required String username,
    required bool cameraMuted,
    required int updatedAt,
  }) {
    return _voice.setCameraMuted(
      callId: callId,
      username: username,
      cameraMuted: cameraMuted,
      updatedAt: updatedAt,
    );
  }

  @override
  Stream<VoiceCallRoom?> watchCall(String callId) => _voice.watchCall(callId);

  @override
  Stream<VoiceCallInboxEntry> watchIncomingCalls(String username) {
    return _voice.watchIncomingCalls(username);
  }

  @override
  Stream<VoiceCallIceCandidateRecord> watchIceCandidates({
    required String callId,
    required VoiceCallRole role,
  }) {
    return _voice.watchIceCandidates(callId: callId, role: role);
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceAnswer(String callId) {
    return _voice.watchVoiceAnswer(callId);
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceOffer(String callId) {
    return _voice.watchVoiceOffer(callId);
  }

  @override
  Future<String> writeIceCandidate({
    required String callId,
    required String username,
    required VoiceCallRole role,
    required VoiceSignalingEnvelope candidate,
    required int createdAt,
  }) {
    return _voice.writeIceCandidate(
      callId: callId,
      username: username,
      role: role,
      candidate: candidate,
      createdAt: createdAt,
    );
  }

  @override
  Future<void> writeVoiceAnswer({
    required String callId,
    required String callee,
    required VoiceSignalingEnvelope answer,
    required int updatedAt,
  }) {
    return _voice.writeVoiceAnswer(
      callId: callId,
      callee: callee,
      answer: answer,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> writeVoiceOffer({
    required String callId,
    required String caller,
    required VoiceSignalingEnvelope offer,
    required int updatedAt,
  }) {
    return _voice.writeVoiceOffer(
      callId: callId,
      caller: caller,
      offer: offer,
      updatedAt: updatedAt,
    );
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
  final List<String> startedVideoPeers = <String>[];
  final List<String> mediaOfferPeers = <String>[];
  final List<String> appliedMediaOfferPeers = <String>[];
  final List<String> appliedMediaAnswerPeers = <String>[];
  final List<String> deafenedPeers = <String>[];
  final List<String> sentFilePayloads = <String>[];
  final List<String> sentControlPayloads = <String>[];
  final Map<String, VoiceMediaConnection> voiceMediaConnections =
      <String, VoiceMediaConnection>{};
  final Map<String, CallMediaConnection> callMediaConnections =
      <String, CallMediaConnection>{};
  final Map<String, bool> mutedPeers = <String, bool>{};
  final Map<String, bool> cameraMutedPeers = <String, bool>{};
  final Map<String, List<VoiceMediaOutputRoute>> outputRoutes =
      <String, List<VoiceMediaOutputRoute>>{};
  Object? startLocalAudioError;
  Object? startLocalVideoError;
  Object? createMediaOfferError;
  Object? applyMediaOfferError;
  Object? applyMediaAnswerError;
  Object? audioOutputRouteError;
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
    final error = startLocalAudioError;
    if (error != null) {
      throw error;
    }
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
  Future<VoiceMediaConnection> createVoiceMediaConnection(String peerId) async {
    final connection = _TestVoiceMediaConnection(this, peerId);
    voiceMediaConnections[peerId] = connection;
    return connection;
  }

  @override
  Future<CallMediaConnection> createCallMediaConnection(String peerId) async {
    final connection = _TestCallMediaConnection(this, peerId);
    callMediaConnections[peerId] = connection;
    return connection;
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

class _TestVoiceMediaConnection implements VoiceMediaConnection {
  _TestVoiceMediaConnection(this.owner, this.peerId);

  final TestSessionManager owner;
  final String peerId;
  final StreamController<VoiceIceCandidate> _iceController =
      StreamController<VoiceIceCandidate>.broadcast();
  final StreamController<VoiceRemoteAudioTrack> _remoteTrackController =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaAudioLevel> _audioLevelController =
      StreamController<VoiceMediaAudioLevel>.broadcast();
  final StreamController<VoiceMediaState> _stateController =
      StreamController<VoiceMediaState>.broadcast();
  final List<VoiceIceCandidate> remoteCandidates = <VoiceIceCandidate>[];
  bool disposed = false;

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack =>
      _remoteTrackController.stream;

  @override
  Stream<VoiceMediaAudioLevel> get onAudioLevelChanged =>
      _audioLevelController.stream;

  @override
  Stream<VoiceMediaState> get onStateChanged => _stateController.stream;

  @override
  VoiceMediaDiagnostics get diagnostics => const VoiceMediaDiagnostics();

  @override
  Future<void> startLocalAudio() async {
    owner.startedAudioPeers.add(peerId);
    final error = owner.startLocalAudioError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<VoiceSessionDescription> createOffer() async {
    owner.mediaOfferPeers.add(peerId);
    final error = owner.createMediaOfferError;
    if (error != null) {
      throw error;
    }
    return VoiceSessionDescription(sdp: 'media-offer-$peerId', type: 'offer');
  }

  @override
  Future<VoiceSessionDescription> acceptOffer(
    VoiceSessionDescription offer,
  ) async {
    owner.appliedMediaOfferPeers.add(peerId);
    final error = owner.applyMediaOfferError;
    if (error != null) {
      throw error;
    }
    _emitConnected();
    return VoiceSessionDescription(sdp: 'media-answer-$peerId', type: 'answer');
  }

  @override
  Future<void> applyAnswer(VoiceSessionDescription answer) async {
    owner.appliedMediaAnswerPeers.add(peerId);
    final error = owner.applyMediaAnswerError;
    if (error != null) {
      throw error;
    }
    _emitConnected();
  }

  @override
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> setMuted({required bool muted}) async {
    owner.mutedPeers[peerId] = muted;
  }

  @override
  Future<void> setDeafened({required bool deafened}) async {
    owner.deafenedPeers.add('$peerId:$deafened');
  }

  @override
  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route) async {
    final error = owner.audioOutputRouteError;
    if (error != null) {
      throw error;
    }
    owner.outputRoutes
        .putIfAbsent(peerId, () => <VoiceMediaOutputRoute>[])
        .add(route);
  }

  @override
  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    owner.stoppedAudioPeers.add(peerId);
    await _iceController.close();
    await _remoteTrackController.close();
    await _audioLevelController.close();
    await _stateController.close();
  }

  void emitIceCandidate(VoiceIceCandidate candidate) {
    _iceController.add(candidate);
  }

  void _emitConnected() {
    _stateController.add(
      VoiceMediaState(
        phase: VoiceMediaPhase.connected,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class _TestCallMediaConnection implements CallMediaConnection {
  _TestCallMediaConnection(this.owner, this.peerId);

  final TestSessionManager owner;
  final String peerId;
  final StreamController<CallIceCandidate> _iceController =
      StreamController<CallIceCandidate>.broadcast();
  final StreamController<CallRemoteMediaTrack> _remoteTrackController =
      StreamController<CallRemoteMediaTrack>.broadcast();
  final StreamController<CallMediaState> _stateController =
      StreamController<CallMediaState>.broadcast();
  final List<CallIceCandidate> remoteCandidates = <CallIceCandidate>[];
  bool hasLocalAudio = false;
  bool hasLocalVideo = false;
  bool disposed = false;

  @override
  Stream<CallIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<CallRemoteMediaTrack> get onRemoteTrack =>
      _remoteTrackController.stream;

  @override
  Stream<CallMediaState> get onStateChanged => _stateController.stream;

  @override
  CallMediaDiagnostics get diagnostics => CallMediaDiagnostics(
    hasLocalAudio: hasLocalAudio,
    hasLocalVideo: hasLocalVideo,
    disposed: disposed,
  );

  @override
  MediaStream? get localStream => null;

  @override
  MediaStreamTrack? get localVideoTrack => null;

  @override
  Future<void> startLocalMedia({required CallMediaKind kind}) async {
    if (hasLocalAudio && (kind == CallMediaKind.audio || hasLocalVideo)) {
      return;
    }
    owner.startedAudioPeers.add(peerId);
    final audioError = owner.startLocalAudioError;
    if (audioError != null) {
      throw audioError;
    }
    hasLocalAudio = true;
    if (kind == CallMediaKind.video) {
      owner.startedVideoPeers.add(peerId);
      final videoError = owner.startLocalVideoError;
      if (videoError != null) {
        throw videoError;
      }
      hasLocalVideo = true;
    }
    _stateController.add(
      CallMediaState(
        phase: CallMediaPhase.localMediaReady,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  @override
  Future<CallSessionDescription> createOffer({
    required CallMediaKind kind,
  }) async {
    await startLocalMedia(kind: kind);
    owner.mediaOfferPeers.add(peerId);
    final error = owner.createMediaOfferError;
    if (error != null) {
      throw error;
    }
    return CallSessionDescription(sdp: 'media-offer-$peerId', type: 'offer');
  }

  @override
  Future<CallSessionDescription> acceptOffer(
    CallSessionDescription offer, {
    required CallMediaKind kind,
  }) async {
    await startLocalMedia(kind: kind);
    owner.appliedMediaOfferPeers.add(peerId);
    final error = owner.applyMediaOfferError;
    if (error != null) {
      throw error;
    }
    _emitConnected();
    return CallSessionDescription(sdp: 'media-answer-$peerId', type: 'answer');
  }

  @override
  Future<void> applyAnswer(CallSessionDescription answer) async {
    owner.appliedMediaAnswerPeers.add(peerId);
    final error = owner.applyMediaAnswerError;
    if (error != null) {
      throw error;
    }
    _emitConnected();
  }

  @override
  Future<void> addRemoteCandidate(CallIceCandidate candidate) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> setMicrophoneMuted({required bool muted}) async {
    owner.mutedPeers[peerId] = muted;
  }

  @override
  Future<void> setCameraMuted({required bool muted}) async {
    owner.cameraMutedPeers[peerId] = muted;
  }

  @override
  Future<void> switchCamera() async {
    owner.startedVideoPeers.add('$peerId:switch');
  }

  @override
  Future<void> setDeafened({required bool deafened}) async {
    owner.deafenedPeers.add('$peerId:$deafened');
  }

  @override
  Future<void> setAudioOutputRoute(CallMediaOutputRoute route) async {
    final error = owner.audioOutputRouteError;
    if (error != null) {
      throw error;
    }
    owner.outputRoutes
        .putIfAbsent(peerId, () => <VoiceMediaOutputRoute>[])
        .add(route);
  }

  @override
  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    owner.stoppedAudioPeers.add(peerId);
    await _iceController.close();
    await _remoteTrackController.close();
    await _stateController.close();
  }

  void _emitConnected() {
    _stateController.add(
      CallMediaState(
        phase: CallMediaPhase.connected,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}

class _TestVideoCallRendererFactory implements VideoCallRendererFactory {
  const _TestVideoCallRendererFactory();

  @override
  VideoCallRendererHandle create() => _TestVideoCallRendererHandle();
}

class _TestVideoCallRendererHandle implements VideoCallRendererHandle {
  MediaStream? _stream;
  void Function()? _onFirstFrameRendered;

  @override
  Future<void> initialize() async {}

  @override
  MediaStream? get srcObject => _stream;

  @override
  set srcObject(MediaStream? stream) {
    _stream = stream;
    if (stream != null) {
      scheduleMicrotask(() => _onFirstFrameRendered?.call());
    }
  }

  @override
  int? get textureId => 1;

  @override
  set onFirstFrameRendered(void Function()? callback) {
    _onFirstFrameRendered = callback;
  }

  @override
  Future<void> dispose() async {
    _stream = null;
    _onFirstFrameRendered = null;
  }
}
