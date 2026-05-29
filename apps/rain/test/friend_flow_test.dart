import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
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
      'startVoiceCall blocks offline peer before room or media setup',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final brain = TestSessionManager();
        await adapter.register('bob', 'bobpw');
        await adapter.setPresence('bob', false);
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
        await FriendStore(db).updatePresence('bob', true);
        final runtime = _runtimeFor(db, alice, adapter, brain: brain);
        addTearDown(runtime.dispose);

        await runtime.start();
        await expectLater(
          runtime.startVoiceCall('bob'),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains('@bob is offline. Keep both apps open'),
            ),
          ),
        );

        expect(runtime.voiceCallState.phase, VoiceCallPhase.idle);
        expect(adapter.rooms, isEmpty);
        expect(adapter.activePairLocks, isEmpty);
        expect(adapter.activeUserLocks, isEmpty);
        expect(brain.startedAudioPeers, isEmpty);
        final friend = await FriendStore(db).loadFriend('bob');
        expect(friend?.isOnline, isFalse);
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
      'integrated gate connects PC to phone voice on first attempt',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );

        final room = harness.adapter.rooms[callId]!;
        expect(room.status, VoiceCallSignalingStatus.connected);
        expect(room.caller, 'alice');
        expect(room.callee, 'bob');
        expect(room.mediaMode, protocol.CallMediaMode.audio);
        expect(harness.adapter.activePairLocks.values.single.callId, callId);
        expect(
          harness.aliceRuntime.voiceCallState.phase,
          VoiceCallPhase.active,
        );
        expect(harness.bobRuntime.voiceCallState.phase, VoiceCallPhase.active);
        expect(harness.aliceRuntime.voiceCallState.isOutgoing, isTrue);
        expect(harness.bobRuntime.voiceCallState.isOutgoing, isFalse);
        expect(harness.aliceBrain.startedAudioPeers, <String>['bob']);
        expect(harness.bobBrain.startedAudioPeers, <String>['alice']);
        expect(harness.aliceBrain.connectedPeers, isEmpty);
        expect(harness.bobBrain.connectedPeers, isEmpty);
      },
    );

    test(
      'integrated gate connects phone to PC voice on first attempt',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: false,
          mediaMode: protocol.CallMediaMode.audio,
        );

        final room = harness.adapter.rooms[callId]!;
        expect(room.status, VoiceCallSignalingStatus.connected);
        expect(room.caller, 'bob');
        expect(room.callee, 'alice');
        expect(room.mediaMode, protocol.CallMediaMode.audio);
        expect(harness.adapter.activePairLocks.values.single.callId, callId);
        expect(harness.bobRuntime.voiceCallState.phase, VoiceCallPhase.active);
        expect(
          harness.aliceRuntime.voiceCallState.phase,
          VoiceCallPhase.active,
        );
        expect(harness.bobRuntime.voiceCallState.isOutgoing, isTrue);
        expect(harness.aliceRuntime.voiceCallState.isOutgoing, isFalse);
        expect(harness.bobBrain.startedAudioPeers, <String>['alice']);
        expect(harness.aliceBrain.startedAudioPeers, <String>['bob']);
        expect(harness.aliceBrain.connectedPeers, isEmpty);
        expect(harness.bobBrain.connectedPeers, isEmpty);
      },
    );

    test(
      'integrated gate connects PC to phone video on first attempt',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.video,
        );

        final room = harness.adapter.rooms[callId]!;
        expect(room.status, VoiceCallSignalingStatus.connected);
        expect(room.caller, 'alice');
        expect(room.callee, 'bob');
        expect(room.mediaMode, protocol.CallMediaMode.video);
        expect(harness.adapter.activePairLocks.values.single.callId, callId);
        expect(
          harness.aliceRuntime.voiceCallState.phase,
          VoiceCallPhase.active,
        );
        expect(harness.bobRuntime.voiceCallState.phase, VoiceCallPhase.active);
        expect(harness.aliceRuntime.voiceCallState.isVideo, isTrue);
        expect(harness.bobRuntime.voiceCallState.isVideo, isTrue);
        expect(harness.aliceRuntime.voiceCallState.hasLocalVideo, isTrue);
        expect(harness.bobRuntime.voiceCallState.hasLocalVideo, isTrue);
        expect(harness.aliceBrain.startedVideoPeers, <String>['bob']);
        expect(harness.bobBrain.startedVideoPeers, <String>['alice']);
      },
    );

    test(
      'integrated gate connects phone to computer video on first attempt',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: false,
          mediaMode: protocol.CallMediaMode.video,
        );

        final room = harness.adapter.rooms[callId]!;
        expect(room.status, VoiceCallSignalingStatus.connected);
        expect(room.caller, 'bob');
        expect(room.callee, 'alice');
        expect(room.mediaMode, protocol.CallMediaMode.video);
        expect(harness.adapter.activePairLocks.values.single.callId, callId);
        expect(harness.bobRuntime.voiceCallState.phase, VoiceCallPhase.active);
        expect(
          harness.aliceRuntime.voiceCallState.phase,
          VoiceCallPhase.active,
        );
        expect(harness.bobRuntime.voiceCallState.isOutgoing, isTrue);
        expect(harness.aliceRuntime.voiceCallState.isOutgoing, isFalse);
        expect(harness.bobRuntime.voiceCallState.hasLocalVideo, isTrue);
        expect(harness.aliceRuntime.voiceCallState.hasLocalVideo, isTrue);
        expect(harness.bobBrain.startedVideoPeers, <String>['alice']);
        expect(harness.aliceBrain.startedVideoPeers, <String>['bob']);
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

    test('Firebase remote mute survives stale media session updates', () async {
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
        'Firebase voice invite to ring on callee',
      );
      await bobRuntime.acceptVoiceCall();
      await _waitForCondition(
        () =>
            aliceRuntime.voiceCallState.phase == VoiceCallPhase.active &&
            bobRuntime.voiceCallState.phase == VoiceCallPhase.active,
        'Firebase voice call to become active before mute check',
      );

      final bobStartedAt = bobRuntime.voiceCallState.startedAt;
      expect(bobStartedAt, isNotNull);

      await aliceRuntime.setVoiceCallMuted(true);
      expect(aliceRuntime.voiceCallState.isMuted, isTrue);
      expect(aliceRuntime.voiceCallState.isRemoteMuted, isFalse);
      await _waitForCondition(
        () => bobRuntime.voiceCallState.isRemoteMuted,
        'Firebase mute update to appear on the remote peer',
      );

      final bobConnection =
          bobBrain.voiceMediaConnections['alice']! as _TestVoiceMediaConnection;
      bobConnection.emitAudioLevel(
        VoiceMediaAudioLevel(
          remoteLevel: 0.42,
          localLevel: 0.11,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          source: VoiceMediaAudioLevelSource.audioLevel,
        ),
      );
      await _waitForCondition(
        () => bobRuntime.voiceCallState.audioLevel.remoteLevel == 0.42,
        'media session update to reach runtime',
      );

      expect(bobRuntime.voiceCallState.isRemoteMuted, isTrue);
      expect(bobRuntime.voiceCallState.startedAt, bobStartedAt);
    });

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
      'active file transfer with one peer blocks call with another',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final brain = TestSessionManager();
        final transferStore = FileTransferStore(db);
        await adapter.register('bob', 'bobpw');
        await adapter.register('cara', 'carapw');
        await adapter.upsertFriendship('alice', 'bob');
        await adapter.upsertFriendship('alice', 'cara');
        for (final username in <String>['bob', 'cara']) {
          await db
              .into(db.friends)
              .insert(
                FriendsCompanion.insert(
                  username: username,
                  displayName: username,
                  state: 'friend',
                  addedAt: 0,
                ),
              );
        }
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
        );
        addTearDown(runtime.dispose);

        await expectLater(
          runtime.startVoiceCall('cara'),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains(
                'Finish the active file transfer before starting a call.',
              ),
            ),
          ),
        );

        expect(adapter.rooms, isEmpty);
      },
    );

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
              contains('Finish the call before sending files.'),
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

    test(
      'active call with one peer blocks calls and files with another',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);
        await harness.adapter.register('cara', 'carapw');
        await harness.adapter.upsertFriendship('alice', 'cara');
        await db
            .into(db.friends)
            .insert(
              FriendsCompanion.insert(
                username: 'cara',
                displayName: 'Cara',
                state: 'friend',
                addedAt: 0,
              ),
            );

        await harness.start();
        await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );

        await expectLater(
          harness.aliceRuntime.startVoiceCall('cara'),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains(
                'You are already in a call with @bob. End it before calling @cara.',
              ),
            ),
          ),
        );
        await expectLater(
          harness.aliceRuntime.sendFile(
            peerId: 'cara',
            fileName: 'blocked.txt',
            fileSize: 1,
            openRead: () => Stream<List<int>>.value(<int>[1]),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'message',
              contains('Finish the call before sending files.'),
            ),
          ),
        );
      },
    );

    test('remote hangup clears local Firebase video call state', () async {
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
      final callId = aliceRuntime.voiceCallState.callId!;
      await _waitForCondition(
        () => bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
        'Firebase video invite to ring before remote hangup',
      );
      await bobRuntime.acceptVoiceCall();
      await _waitForCondition(
        () =>
            aliceRuntime.voiceCallState.phase == VoiceCallPhase.active &&
            bobRuntime.voiceCallState.phase == VoiceCallPhase.active,
        'Firebase video call to become active before remote hangup',
      );

      await bobRuntime.hangUpVoiceCall();

      await _waitForCondition(
        () => adapter.rooms[callId]?.status == VoiceCallSignalingStatus.ended,
        'Firebase video room to end after remote hangup',
      );
      await _waitForCondition(
        () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.idle,
        'local video call to clear after remote hangup',
      );

      expect(aliceRuntime.voiceCallState.hasLocalVideo, isFalse);
      expect(aliceRuntime.voiceCallState.hasRemoteVideo, isFalse);
      expect(aliceRuntime.voiceCallState.isVideo, isFalse);
      expect(
        (aliceBrain.callMediaConnections['bob']! as _TestCallMediaConnection)
            .disposed,
        isTrue,
      );
    });

    test(
      'integrated gate app close during ringing ends call and removes locks',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        await harness.aliceRuntime.startVoiceCall('bob');
        final callId = harness.aliceRuntime.voiceCallState.callId!;
        await _waitForCondition(
          () =>
              harness.bobRuntime.voiceCallState.phase ==
              VoiceCallPhase.incomingRinging,
          'Firebase voice invite to ring before callee closes app',
        );

        await harness.bobRuntime.dispose();

        await _waitForCondition(
          () =>
              harness.adapter.rooms[callId]?.status ==
              VoiceCallSignalingStatus.ended,
          'Firebase ringing room to end when callee app closes',
        );
        await _waitForCondition(
          () =>
              harness.aliceRuntime.voiceCallState.phase == VoiceCallPhase.idle,
          'caller runtime to clear ringing call after callee app closes',
        );

        final room = harness.adapter.rooms[callId]!;
        expect(room.endedBy, 'bob');
        expect(room.reason, 'Rain is closing.');
        expect(harness.adapter.activePairLocks, isEmpty);
        expect(harness.adapter.activeUserLocks, isEmpty);
        expect(harness.aliceBrain.stoppedAudioPeers, contains('bob'));
        expect(harness.bobBrain.stoppedAudioPeers, contains('alice'));
      },
    );

    test(
      'integrated gate callee app close clears active Firebase video call',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.video,
        );

        await harness.bobRuntime.dispose();

        await _waitForCondition(
          () =>
              harness.adapter.rooms[callId]?.status ==
              VoiceCallSignalingStatus.ended,
          'Firebase video room to end when callee app closes',
        );
        await _waitForCondition(
          () =>
              harness.aliceRuntime.voiceCallState.phase == VoiceCallPhase.idle,
          'caller runtime to clear when callee app closes',
        );

        final room = harness.adapter.rooms[callId]!;
        expect(room.endedBy, 'bob');
        expect(room.reason, 'Rain is closing.');
        expect(harness.adapter.activePairLocks, isEmpty);
        expect(harness.adapter.activeUserLocks, isEmpty);
        expect(harness.aliceRuntime.voiceCallState.isVideo, isFalse);
        expect(harness.aliceRuntime.voiceCallState.hasLocalVideo, isFalse);
        expect(harness.aliceRuntime.voiceCallState.hasRemoteVideo, isFalse);
        expect(harness.aliceBrain.stoppedAudioPeers, contains('bob'));
        expect(harness.bobBrain.stoppedAudioPeers, contains('alice'));
      },
    );

    test(
      'remote app close fails active call without reconnecting forever',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );
        harness.aliceBrain.seedSession('bob', SessionState.connected);

        await harness.aliceBrain.disconnect('bob');

        await _waitForCondition(
          () =>
              harness.aliceRuntime.voiceCallState.phase ==
              VoiceCallPhase.failed,
          'remote app close to fail the local active call',
        );
        expect(
          harness.aliceRuntime.voiceCallState.detail,
          'Peer closed Rain. Connection ended.',
        );
        expect(harness.aliceRuntime.voiceCallState.mediaReconnecting, isFalse);
        expect(
          harness.aliceRuntime.voiceCallState.failureReason,
          VoiceCallFailureReason.networkLost,
        );
        await _waitForCondition(
          () =>
              harness.adapter.rooms[callId]?.status ==
              VoiceCallSignalingStatus.failed,
          'remote app close to mark Firebase room terminal',
        );
        expect(harness.adapter.rooms[callId]?.reason, contains('closed Rain'));
        expect(harness.adapter.activePairLocks, isEmpty);
        expect(harness.adapter.activeUserLocks, isEmpty);
        expect(
          harness.aliceRuntime
              .connectionCoordinatorSnapshotFor('bob')
              .manualDisconnect,
          isFalse,
        );
      },
    );

    test(
      'local video renderer creation failure fails call without Firebase invite',
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
          videoCallRendererFactory: _FailingTestVideoCallRendererFactory(
            throwOnCreateAt: 1,
          ),
        );
        addTearDown(runtime.dispose);

        await runtime.start();
        await expectLater(
          runtime.startVideoCall('bob'),
          throwsA(
            isA<Exception>().having(
              (Object error) => error.toString(),
              'message',
              contains('Video renderer failed'),
            ),
          ),
        );

        expect(adapter.rooms, isEmpty);
        expect(runtime.voiceCallState.phase, VoiceCallPhase.failed);
        expect(
          runtime.voiceCallState.failureReason,
          VoiceCallFailureReason.videoRendererFailed,
        );
        expect(
          (brain.callMediaConnections['bob']! as _TestCallMediaConnection)
              .disposed,
          isTrue,
        );
      },
    );

    test(
      'remote video renderer attach failure ends only the video call',
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
          videoCallRendererFactory: _FailingTestVideoCallRendererFactory(
            throwOnRemoteAttach: true,
          ),
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
        final callId = aliceRuntime.voiceCallState.callId!;
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase video invite to ring before renderer attach failure',
        );
        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.active,
          'caller video call to become active before remote renderer failure',
        );

        (aliceBrain.callMediaConnections['bob']! as _TestCallMediaConnection)
            .emitRemoteVideoTrack();

        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'caller to fail after remote renderer attach failure',
        );
        expect(adapter.rooms[callId]?.status, VoiceCallSignalingStatus.failed);
        expect(adapter.rooms[callId]?.reasonCode, 'videoRendererFailed');
        expect(
          aliceRuntime.voiceCallState.failureReason,
          VoiceCallFailureReason.videoRendererFailed,
        );
        expect(
          (aliceBrain.callMediaConnections['bob']! as _TestCallMediaConnection)
              .disposed,
          isTrue,
        );
        await expectLater(
          aliceRuntime.sendMessage('bob', 'chat still works after video fail'),
          completes,
        );
        expect(await db.select(db.messages).get(), isNotEmpty);
      },
    );

    test(
      'video media connection failure after room creation fails both peers',
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
        final callId = aliceRuntime.voiceCallState.callId!;
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase video invite to ring before media answer failure',
        );
        await bobRuntime.acceptVoiceCall();

        await _waitForCondition(
          () =>
              adapter.rooms[callId]?.status == VoiceCallSignalingStatus.failed,
          'Firebase video room to fail after answer application failure',
        );
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'caller to fail after answer application failure',
        );
        await _waitForCondition(
          () => bobRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'callee to leave false active state after caller media failure',
        );

        expect(
          aliceRuntime.voiceCallState.failureReason,
          VoiceCallFailureReason.mediaConnectionFailed,
        );
        expect(adapter.rooms[callId]?.caller, 'alice');
        expect(adapter.rooms[callId]?.callee, 'bob');
        expect(adapter.rooms[callId]?.mediaMode, protocol.CallMediaMode.video);
        expect(adapter.activePairLocks, isEmpty);
        expect(aliceRuntime.voiceCallBlocksFileTransfer('bob'), isFalse);
        expect(bobRuntime.voiceCallBlocksFileTransfer('alice'), isFalse);
        expect(aliceRuntime.voiceCallState.isVideo, isTrue);
        expect(bobRuntime.voiceCallState.isVideo, isTrue);
        expect(
          (aliceBrain.callMediaConnections['bob']! as _TestCallMediaConnection)
              .disposed,
          isTrue,
        );
        expect(
          (bobBrain.callMediaConnections['alice']! as _TestCallMediaConnection)
              .disposed,
          isTrue,
        );
        await expectLater(
          aliceRuntime.sendMessage('bob', 'chat still works after media fail'),
          completes,
        );
      },
    );

    test(
      'remote video first-frame timeout ends the call without blocking chat',
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
          videoCallRendererFactory: _FailingTestVideoCallRendererFactory(
            remoteAutoFirstFrame: false,
          ),
          videoCallRemoteFirstFrameTimeout: Duration.zero,
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
        final callId = aliceRuntime.voiceCallState.callId!;
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase video invite to ring before first-frame timeout',
        );
        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.active,
          'caller video call to become active before first-frame timeout',
        );

        (aliceBrain.callMediaConnections['bob']! as _TestCallMediaConnection)
            .emitRemoteVideoTrack();

        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'caller to fail after remote first-frame timeout',
        );
        expect(adapter.rooms[callId]?.status, VoiceCallSignalingStatus.failed);
        expect(adapter.rooms[callId]?.reasonCode, 'videoFirstFrameTimeout');
        expect(
          aliceRuntime.voiceCallState.failureReason,
          VoiceCallFailureReason.videoFirstFrameTimeout,
        );
        expect(aliceRuntime.voiceCallState.hasRemoteVideo, isFalse);
        await expectLater(
          aliceRuntime.sendMessage('bob', 'chat still works after timeout'),
          completes,
        );
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
      adapter.seedActivePairLockForTest(
        VoiceActivePairLock(
          pairId: 'alice:bob',
          callId: 'existing-call',
          caller: 'bob',
          callee: 'alice',
          createdAt: now,
          updatedAt: now,
          expiresAt: now + const Duration(minutes: 2).inMilliseconds,
        ),
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
      expect(runtime.voiceCallState.detail, '@bob is already in a call.');
      expect(adapter.rooms, isEmpty);
      expect(adapter.activePairLocks['alice:bob']?.callId, 'existing-call');
    });

    test(
      'active Firebase user lock is surfaced as peer busy in another call',
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
        final now = DateTime.now().millisecondsSinceEpoch;
        adapter.seedActiveUserLockForTest(
          VoiceActiveUserLock(
            username: 'bob',
            callId: 'bob-cara-call',
            pairId: 'bob:cara',
            caller: 'bob',
            callee: 'cara',
            createdAt: now,
            updatedAt: now,
            expiresAt: now + const Duration(minutes: 2).inMilliseconds,
          ),
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
        expect(runtime.voiceCallState.detail, '@bob is already in a call.');
        expect(adapter.rooms, isEmpty);
        expect(adapter.activeUserLocks['bob']?.callId, 'bob-cara-call');
      },
    );

    test(
      'caller-owned Firebase setup room is reclaimed before retry',
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
        await runtime.startVoiceCall('bob');

        expect(adapter.rooms, hasLength(1));
        expect(adapter.rooms.values.single.callId, isNot('existing-call'));
        expect(adapter.rooms.values.single.caller, 'alice');
        expect(adapter.rooms.values.single.callee, 'bob');
        expect(runtime.voiceCallState.failureReason, isNull);
        expect(runtime.voiceCallState.phase, VoiceCallPhase.outgoingRinging);
      },
    );

    test(
      'stale orphan Firebase pair lock is reclaimed before call start',
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
        adapter.seedActivePairLockForTest(
          const VoiceActivePairLock(
            pairId: 'alice:bob',
            callId: 'orphan-call',
            caller: 'alice',
            callee: 'bob',
            createdAt: 1000,
            updatedAt: 1000,
            expiresAt: 60000,
          ),
        );
        final runtime = _runtimeFor(db, alice, adapter, brain: brain);
        addTearDown(runtime.dispose);

        await runtime.start();
        await runtime.startVoiceCall('bob');

        expect(runtime.voiceCallState.phase, VoiceCallPhase.outgoingRinging);
        expect(
          runtime.voiceCallState.failureReason,
          isNot(VoiceCallFailureReason.peerBusy),
        );
        expect(
          adapter.activePairLocks['alice:bob']?.callId,
          runtime.voiceCallState.callId,
        );
        expect(adapter.rooms.keys, contains(runtime.voiceCallState.callId));
      },
    );

    test(
      'terminal Firebase room with leftover pair lock is reclaimed before call start',
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
        await adapter.createOutgoingCall(
          callId: 'failed-call',
          caller: 'alice',
          callee: 'bob',
          createdAt: 1000,
          expiresAt: 60000,
        );
        await adapter.endCall(
          callId: 'failed-call',
          username: 'alice',
          status: VoiceCallSignalingStatus.failed,
          endedAt: 1200,
          reasonCode: 'mediaConnectionFailed',
          reason: 'Call media could not connect.',
        );
        adapter.seedActivePairLockForTest(
          const VoiceActivePairLock(
            pairId: 'alice:bob',
            callId: 'failed-call',
            caller: 'alice',
            callee: 'bob',
            createdAt: 1000,
            updatedAt: 1000,
            expiresAt: 60000,
          ),
        );
        final runtime = _runtimeFor(db, alice, adapter, brain: brain);
        addTearDown(runtime.dispose);

        await runtime.start();
        await runtime.startVoiceCall('bob');

        expect(runtime.voiceCallState.phase, VoiceCallPhase.outgoingRinging);
        expect(runtime.voiceCallState.isOutgoing, isTrue);
        expect(
          runtime.voiceCallState.failureReason,
          isNot(VoiceCallFailureReason.peerBusy),
        );
        expect(
          adapter.activePairLocks['alice:bob']?.callId,
          runtime.voiceCallState.callId,
        );
        expect(adapter.rooms.keys, isNot(contains('failed-call')));
      },
    );

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
              contains('Finish the call before sending files.'),
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
      expect(adapter.activePairLocks, isEmpty);
      await _waitForCondition(
        () => bobRuntime.voiceCallState.phase == VoiceCallPhase.idle,
        'remaining runtime to clear after remote dispose',
      );
      expect(bobBrain.stoppedAudioPeers, contains('alice'));
    });

    test('remote offline presence ends active Firebase voice call', () async {
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
        () => bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
        'Firebase voice invite to ring before offline presence',
      );
      await bobRuntime.acceptVoiceCall();
      await _waitForCondition(
        () =>
            aliceRuntime.voiceCallState.phase == VoiceCallPhase.active &&
            bobRuntime.voiceCallState.phase == VoiceCallPhase.active,
        'Firebase voice call to become active before offline presence',
      );

      await adapter.setPresence('bob', false);

      await _waitForCondition(
        () => adapter.rooms[callId]?.status == VoiceCallSignalingStatus.failed,
        'Firebase voice room to fail when peer presence goes offline',
      );
      await _waitForCondition(
        () => bobRuntime.voiceCallState.phase == VoiceCallPhase.failed,
        'remote runtime to observe offline terminal state',
      );

      expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.failed);
      expect(
        aliceRuntime.voiceCallState.failureReason,
        VoiceCallFailureReason.networkLost,
      );
      expect(adapter.rooms[callId]?.reasonCode, 'networkLost');
      expect(adapter.activePairLocks, isEmpty);
      expect(aliceBrain.stoppedAudioPeers, contains('bob'));
      expect(bobBrain.stoppedAudioPeers, contains('alice'));
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
      'peer data disconnect ends active Firebase voice call media',
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
        await aliceRuntime.connectPeer('bob');
        aliceBrain.markConnected('bob');
        await aliceRuntime.startVoiceCall('bob');
        final callId = aliceRuntime.voiceCallState.callId!;
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'Firebase voice invite to ring before data disconnect',
        );
        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () =>
              aliceRuntime.voiceCallState.phase == VoiceCallPhase.active &&
              bobRuntime.voiceCallState.phase == VoiceCallPhase.active,
          'Firebase voice call to become active before data disconnect',
        );

        await aliceBrain.disconnect('bob');

        await _waitForCondition(
          () =>
              adapter.rooms[callId]?.status == VoiceCallSignalingStatus.failed,
          'Firebase voice room to fail after data disconnect',
        );
        await _waitForCondition(
          () => bobRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'remote runtime to observe data disconnect terminal state',
        );
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'local runtime to finish data disconnect cleanup',
        );

        expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.failed);
        expect(
          aliceRuntime.voiceCallState.failureReason,
          VoiceCallFailureReason.networkLost,
        );
        expect(adapter.rooms[callId]?.reasonCode, 'networkLost');
        expect(adapter.activePairLocks, isEmpty);
        expect(aliceBrain.stoppedAudioPeers, contains('bob'));
        expect(bobBrain.stoppedAudioPeers, contains('alice'));
      },
    );

    test('duplicate Firebase terminal update is idempotent', () async {
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
        () => bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
        'Firebase voice invite to ring before duplicate terminal update',
      );
      await bobRuntime.acceptVoiceCall();
      await _waitForCondition(
        () =>
            aliceRuntime.voiceCallState.phase == VoiceCallPhase.active &&
            bobRuntime.voiceCallState.phase == VoiceCallPhase.active,
        'Firebase voice call to become active before duplicate terminal update',
      );

      await bobRuntime.hangUpVoiceCall();
      await _waitForCondition(
        () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.idle,
        'local call to clear after first terminal update',
      );
      final stoppedBeforeDuplicate = List<String>.of(
        aliceBrain.stoppedAudioPeers,
      );

      adapter.reemitCallForTest(callId);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(aliceRuntime.voiceCallState.phase, VoiceCallPhase.idle);
      expect(aliceBrain.stoppedAudioPeers, stoppedBeforeDuplicate);
      expect(adapter.activePairLocks, isEmpty);
    });

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
        expect(aliceRuntime.voiceCallState.isOutgoing, isTrue);
        expect(bobRuntime.voiceCallState.isOutgoing, isFalse);
        expect(adapter.rooms[secondCallId]?.caller, 'alice');
        expect(adapter.rooms[secondCallId]?.callee, 'bob');
        expect(
          adapter.rooms.values.where(
            (VoiceCallRoom room) =>
                room.caller == 'bob' && room.callee == 'alice',
          ),
          isEmpty,
        );
        expect(aliceBrain.startedAudioPeers, <String>['bob', 'bob']);
        expect(aliceRuntime.voiceCallBlocksFileTransfer('bob'), isTrue);
      },
    );

    test(
      'reverse retry after failed incoming Firebase call rings instead of busy',
      () async {
        final adapter = RecordingVoiceSignalingAdapter();
        final aliceBrain = TestSessionManager()
          ..applyMediaAnswerError = StateError(
            'Unable to RTCPeerConnection::setRemoteDescription',
          );
        final bobBrain = TestSessionManager();
        final bobDb = RainDatabase(NativeDatabase.memory());
        addTearDown(bobDb.close);
        await adapter.register('alice', 'alicepw');
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
        final originalCallId = aliceRuntime.voiceCallState.callId!;
        await _waitForCondition(
          () =>
              bobRuntime.voiceCallState.phase == VoiceCallPhase.incomingRinging,
          'original Firebase voice invite to ring',
        );
        await bobRuntime.acceptVoiceCall();
        await _waitForCondition(
          () => aliceRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'original caller to fail media',
        );
        await _waitForCondition(
          () => bobRuntime.voiceCallState.phase == VoiceCallPhase.failed,
          'original callee to observe failed incoming call',
        );

        aliceBrain.applyMediaAnswerError = null;
        await bobRuntime.startVoiceCall('alice');
        final reverseCallId = bobRuntime.voiceCallState.callId!;

        await _waitForCondition(
          () =>
              adapter.rooms[reverseCallId]?.status ==
              VoiceCallSignalingStatus.ringing,
          'reverse retry room to ring after stale failure',
        );
        await _waitForCondition(
          () =>
              aliceRuntime.voiceCallState.phase ==
              VoiceCallPhase.incomingRinging,
          'stale failed caller to receive reverse retry invite',
        );

        expect(aliceRuntime.voiceCallState.callId, reverseCallId);
        expect(aliceRuntime.voiceCallState.isOutgoing, isFalse);
        expect(bobRuntime.voiceCallState.isOutgoing, isTrue);
        expect(
          aliceRuntime.voiceCallState.failureReason,
          isNot(VoiceCallFailureReason.peerBusy),
        );
        expect(
          bobRuntime.voiceCallState.failureReason,
          isNot(VoiceCallFailureReason.peerBusy),
        );
        expect(originalCallId, isNot(reverseCallId));
        expect(adapter.activePairLocks.values.single.callId, reverseCallId);
        expect(adapter.rooms[reverseCallId]?.caller, 'bob');
        expect(adapter.rooms[reverseCallId]?.callee, 'alice');
        expect(adapter.rooms[reverseCallId]?.reasonCode, isNull);
      },
    );

    test(
      'advanced Firebase inbox entry is ignored instead of recreated as invite',
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
        await adapter.createOutgoingCall(
          callId: 'advanced-call',
          caller: 'bob',
          callee: 'alice',
          createdAt: 1000,
          expiresAt: 60000,
        );
        await adapter.acceptCall(
          callId: 'advanced-call',
          callee: 'alice',
          acceptedAt: 1200,
        );
        final runtime = _runtimeFor(db, alice, adapter, brain: brain);
        addTearDown(runtime.dispose);

        await runtime.start();
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(runtime.voiceCallState.phase, VoiceCallPhase.idle);
        expect(brain.startedAudioPeers, isEmpty);
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
                contains('Finish the call before sending files.'),
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

    test('interactive connect clears manual disconnect intent', () async {
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
              online: const Value(true),
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
        friendRequestRefreshInterval: Duration.zero,
      );

      await runtime.start();
      await runtime.connectPeer('bob', interactive: true);
      final disconnectedGuard = brain.incomingOfferGuards['bob'];
      expect(disconnectedGuard, isNotNull);
      await runtime.disconnectPeer('bob');

      expect((await disconnectedGuard!('bob')).allowed, isFalse);

      await runtime.connectPeer(
        'bob',
        interactive: true,
        allowStalePresence: true,
        bypassRetryBackoff: true,
      );

      final reconnectedGuard = brain.incomingOfferGuards['bob'];
      expect(reconnectedGuard, isNotNull);
      expect((await reconnectedGuard!('bob')).allowed, isTrue);
      expect(brain.connectedPeers, <String>['bob', 'bob']);
      await runtime.dispose();
    });

    test('background connect keeps manual disconnect intent', () async {
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
              online: const Value(true),
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
        friendRequestRefreshInterval: Duration.zero,
      );

      await runtime.start();
      await runtime.connectPeer('bob', interactive: true);
      final disconnectedGuard = brain.incomingOfferGuards['bob'];
      expect(disconnectedGuard, isNotNull);
      await runtime.disconnectPeer('bob');
      await runtime.connectPeer('bob');

      expect((await disconnectedGuard!('bob')).allowed, isFalse);
      expect(brain.connectedPeers, <String>['bob']);
      await runtime.dispose();
    });

    test(
      'manual disconnect suppresses remote recovery and interactive reconnect restarts cleanly',
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
                online: const Value(true),
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
          friendRequestRefreshInterval: Duration.zero,
        );

        await runtime.start();
        await runtime.connectPeer('bob', interactive: true);
        final disconnectedGuard = brain.incomingOfferGuards['bob'];
        expect(disconnectedGuard, isNotNull);

        await runtime.disconnectPeer('bob');

        expect(
          runtime.connectionCoordinatorSnapshotFor('bob').manualDisconnect,
          isTrue,
        );
        expect((await disconnectedGuard!('bob')).allowed, isFalse);
        expect(brain.unregisteredPeers, contains('bob'));

        brain.seedSession('bob', SessionState.reconnecting);
        final reconnect = runtime.connectPeer(
          'bob',
          interactive: true,
          waitForConnected: true,
          allowStalePresence: true,
          bypassRetryBackoff: true,
          connectionTimeout: const Duration(seconds: 2),
        );
        await _waitForCondition(
          () => brain.connectedPeers.length == 2,
          'fresh interactive reconnect attempt',
        );
        brain.markConnected('bob');
        await reconnect;

        expect(
          runtime.connectionCoordinatorSnapshotFor('bob').manualDisconnect,
          isFalse,
        );
        expect(brain.disconnectedPeers, <String>['bob', 'bob']);
        expect(brain.connectedPeers, <String>['bob', 'bob']);
        expect(brain.getSession('bob')?.state, SessionState.connected);
        await runtime.dispose();
      },
    );

    test(
      'manual disconnect is scoped to one peer in multi-peer runtime',
      () async {
        final adapter = NoopSignalingAdapter();
        final brain = TestSessionManager();
        for (final username in <String>['bob', 'cara']) {
          await adapter.register(username, '${username}pw');
          await adapter.upsertFriendship('alice', username);
          await db
              .into(db.friends)
              .insert(
                FriendsCompanion.insert(
                  username: username,
                  displayName: username,
                  state: 'friend',
                  addedAt: 0,
                  online: const Value(true),
                ),
              );
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
          networkRecoveryDebounce: Duration.zero,
        );

        await runtime.start();
        await runtime.connectPeer('bob', interactive: true);
        await runtime.connectPeer('cara', interactive: true);
        brain.markConnected('bob');
        brain.markConnected('cara');

        await runtime.disconnectPeer('bob');
        await runtime.handleNetworkAvailable('test recovery');
        await pumpEventQueue();

        expect(
          runtime.connectionCoordinatorSnapshotFor('bob').manualDisconnect,
          isTrue,
        );
        expect(brain.getSession('bob'), isNull);
        expect(brain.getSession('cara')?.state, SessionState.connected);
        expect(brain.connectedPeers, <String>['bob', 'cara']);

        await runtime.connectPeer(
          'bob',
          interactive: true,
          allowStalePresence: true,
          bypassRetryBackoff: true,
        );

        expect(
          runtime.connectionCoordinatorSnapshotFor('bob').manualDisconnect,
          isFalse,
        );
        expect(brain.connectedPeers, <String>['bob', 'cara', 'bob']);
        expect(brain.getSession('cara')?.state, SessionState.connected);
        await runtime.dispose();
      },
    );

    test(
      'temporary transport loss shows reconnecting grace before failing call',
      () async {
        final harness = await _createTwoUserCallHarness(
          db,
          alice,
          activeCallReconnectGrace: const Duration(milliseconds: 80),
        );
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );

        harness.aliceBrain.emitTransientPeerDisconnect('bob');
        await _waitForCondition(
          () => harness.aliceRuntime.voiceCallState.mediaReconnecting,
          'active call to enter reconnecting grace',
        );
        expect(
          harness.aliceRuntime.voiceCallState.phase,
          VoiceCallPhase.active,
        );
        expect(
          harness.aliceRuntime.voiceCallState.detail,
          contains('Reconnecting'),
        );
        expect(
          harness.adapter.rooms[callId]?.status,
          VoiceCallSignalingStatus.connected,
        );

        await _waitForCondition(
          () =>
              harness.aliceRuntime.voiceCallState.phase ==
              VoiceCallPhase.failed,
          'active call reconnecting grace to fail after timeout',
        );
        expect(
          harness.aliceRuntime.voiceCallState.failureReason,
          VoiceCallFailureReason.networkLost,
        );
        expect(harness.aliceRuntime.voiceCallState.mediaReconnecting, isFalse);
        expect(harness.adapter.rooms[callId]?.reasonCode, 'networkLost');
      },
    );

    test(
      'recovered transport clears reconnecting state and keeps call active',
      () async {
        final harness = await _createTwoUserCallHarness(
          db,
          alice,
          activeCallReconnectGrace: const Duration(milliseconds: 160),
        );
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );

        harness.aliceBrain.emitTransientPeerDisconnect('bob');
        await _waitForCondition(
          () => harness.aliceRuntime.voiceCallState.mediaReconnecting,
          'active call to enter reconnecting grace',
        );
        harness.aliceBrain.markConnected('bob');
        await _waitForCondition(
          () =>
              harness.aliceRuntime.voiceCallState.phase ==
                  VoiceCallPhase.active &&
              !harness.aliceRuntime.voiceCallState.mediaReconnecting,
          'active call reconnecting grace to clear on recovery',
        );

        expect(
          harness.adapter.rooms[callId]?.status,
          VoiceCallSignalingStatus.connected,
        );
        expect(harness.aliceRuntime.voiceCallState.reconnectingSince, isNull);
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(
          harness.aliceRuntime.voiceCallState.phase,
          VoiceCallPhase.active,
        );
      },
    );

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

    test(
      'caller can immediately call back after previous call ended by callee',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final firstCallId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );

        await harness.bobRuntime.hangUpVoiceCall();
        await _waitForHarnessCallIdle(harness, 'callee hangup to clear');
        expect(harness.adapter.activePairLocks, isEmpty);
        expect(harness.adapter.activeUserLocks, isEmpty);

        final secondCallId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );

        expect(secondCallId, isNot(firstCallId));
        expect(harness.adapter.rooms[secondCallId]?.caller, 'alice');
        expect(harness.adapter.rooms[secondCallId]?.callee, 'bob');
        expect(harness.aliceRuntime.voiceCallState.failureReason, isNull);
        expect(harness.bobRuntime.voiceCallState.failureReason, isNull);
      },
    );

    test(
      'callee can immediately call back after previous call ended by caller',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final firstCallId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );

        await harness.aliceRuntime.hangUpVoiceCall();
        await _waitForHarnessCallIdle(harness, 'caller hangup to clear');
        expect(harness.adapter.activePairLocks, isEmpty);
        expect(harness.adapter.activeUserLocks, isEmpty);

        final secondCallId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: false,
          mediaMode: protocol.CallMediaMode.audio,
        );

        expect(secondCallId, isNot(firstCallId));
        expect(harness.adapter.rooms[secondCallId]?.caller, 'bob');
        expect(harness.adapter.rooms[secondCallId]?.callee, 'alice');
        expect(harness.aliceRuntime.voiceCallState.failureReason, isNull);
        expect(harness.bobRuntime.voiceCallState.failureReason, isNull);
      },
    );

    test(
      'phone caller retry succeeds after stale pc outgoing room is cleaned',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);
        final staleCreatedAt =
            DateTime.now().millisecondsSinceEpoch -
            const Duration(minutes: 2).inMilliseconds;

        await harness.start();
        await harness.adapter.createOutgoingCall(
          callId: 'stale-pc-outgoing',
          caller: 'alice',
          callee: 'bob',
          createdAt: staleCreatedAt,
          expiresAt: staleCreatedAt + const Duration(seconds: 1).inMilliseconds,
        );
        expect(
          harness.adapter.activePairLocks.values.single.callId,
          'stale-pc-outgoing',
        );
        expect(
          harness.adapter.activeUserLocks['alice']?.callId,
          'stale-pc-outgoing',
        );
        expect(
          harness.adapter.activeUserLocks['bob']?.callId,
          'stale-pc-outgoing',
        );

        final retryCallId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: false,
          mediaMode: protocol.CallMediaMode.audio,
        );

        expect(retryCallId, isNot('stale-pc-outgoing'));
        expect(harness.adapter.rooms['stale-pc-outgoing'], isNull);
        expect(harness.adapter.rooms[retryCallId]?.caller, 'bob');
        expect(harness.adapter.rooms[retryCallId]?.callee, 'alice');
        expect(
          harness.adapter.activePairLocks.values.single.callId,
          retryCallId,
        );
        expect(harness.adapter.activeUserLocks['alice']?.callId, retryCallId);
        expect(harness.adapter.activeUserLocks['bob']?.callId, retryCallId);
        expect(
          harness.bobRuntime.voiceCallState.failureReason,
          isNot(VoiceCallFailureReason.peerBusy),
        );
        expect(
          harness.aliceRuntime.voiceCallState.failureReason,
          isNot(VoiceCallFailureReason.peerBusy),
        );
      },
    );

    test(
      'hangup cleanup is idempotent when signaling frame send fails',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );
        final connection =
            harness.aliceBrain.voiceMediaConnections['bob']!
                as _TestVoiceMediaConnection;
        harness.adapter.endCallError = StateError('end call write failed');

        await harness.aliceRuntime.hangUpVoiceCall();

        expect(harness.aliceRuntime.voiceCallState.phase, VoiceCallPhase.idle);
        expect(harness.aliceRuntime.voiceCallState.callId, isNull);
        expect(connection.disposed, isTrue);
        expect(harness.aliceBrain.stoppedAudioPeers, contains('bob'));
        expect(
          harness.adapter.rooms[callId]?.status,
          VoiceCallSignalingStatus.connected,
        );
      },
    );

    test(
      'local voice hangup writes terminal room before best-effort session hangup',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );
        harness.adapter.failEndCallAttempt = 2;

        await harness.aliceRuntime.hangUpVoiceCall();

        await _waitForHarnessCallIdle(
          harness,
          'Firebase terminal voice room to clear both peers',
        );
        expect(harness.adapter.endCallAttempts, 1);
        expect(
          harness.runtimeEvents,
          contains('alice:voice_terminal_write_before_session_hangup'),
        );
        expect(
          harness.runtimeEvents,
          contains('alice:voice_late_hangup_frame_ignored'),
        );
        final room = harness.adapter.rooms[callId]!;
        expect(room.status, VoiceCallSignalingStatus.ended);
        expect(room.endedBy, 'alice');
        expect(harness.adapter.activePairLocks, isEmpty);
        expect(harness.adapter.activeUserLocks, isEmpty);
        expect(
          (harness.aliceBrain.voiceMediaConnections['bob']!
                  as _TestVoiceMediaConnection)
              .disposed,
          isTrue,
        );
        expect(
          (harness.bobBrain.voiceMediaConnections['alice']!
                  as _TestVoiceMediaConnection)
              .disposed,
          isTrue,
        );
      },
    );

    test(
      'terminal Firebase voice room clears active call without a hangup frame',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );

        await harness.adapter.endCall(
          callId: callId,
          username: 'bob',
          status: VoiceCallSignalingStatus.ended,
          endedAt: DateTime.now().millisecondsSinceEpoch,
          reason: 'Call ended.',
        );

        await _waitForHarnessCallIdle(
          harness,
          'direct Firebase terminal voice room to clear both peers',
        );
        expect(harness.adapter.rooms[callId]?.endedBy, 'bob');
        expect(harness.aliceBrain.stoppedAudioPeers, contains('bob'));
        expect(harness.bobBrain.stoppedAudioPeers, contains('alice'));
      },
    );

    test(
      'terminal Firebase voice room blocks late active voice media state',
      () async {
        final harness = await _createTwoUserCallHarness(db, alice);
        addTearDown(harness.dispose);

        await harness.start();
        final callId = await _startAndAcceptHarnessCall(
          harness,
          callerIsAlice: true,
          mediaMode: protocol.CallMediaMode.audio,
        );
        final disposeGate = Completer<void>();
        addTearDown(() {
          if (!disposeGate.isCompleted) {
            disposeGate.complete();
          }
        });
        harness.bobBrain.voiceDisposeGate = disposeGate;
        final bobConnection =
            harness.bobBrain.voiceMediaConnections['alice']!
                as _TestVoiceMediaConnection;

        await harness.adapter.endCall(
          callId: callId,
          username: 'alice',
          status: VoiceCallSignalingStatus.ended,
          endedAt: DateTime.now().millisecondsSinceEpoch,
          reason: 'Call ended.',
        );
        await _waitForCondition(
          () =>
              harness.bobRuntime.voiceCallState.phase == VoiceCallPhase.ending,
          'remote voice call to enter terminal cleanup',
        );

        bobConnection.emitConnectedForTest();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(harness.bobRuntime.voiceCallState.phase, VoiceCallPhase.ending);
        disposeGate.complete();
        await _waitForHarnessCallIdle(
          harness,
          'terminal voice room to remain authoritative after late active state',
        );
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
  RuntimeEventRecorder? eventRecorder,
  VideoCallRendererFactory videoCallRendererFactory =
      const RtcVideoCallRendererFactory(),
  Duration videoCallRemoteFirstFrameTimeout = const Duration(seconds: 8),
  Duration activeCallReconnectGrace = const Duration(seconds: 8),
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
    videoCallRemoteFirstFrameTimeout: videoCallRemoteFirstFrameTimeout,
    activeCallReconnectGrace: activeCallReconnectGrace,
    errorRecorder: errorRecorder,
    eventRecorder: eventRecorder,
  );
}

Future<_TwoUserCallHarness> _createTwoUserCallHarness(
  RainDatabase aliceDb,
  RainIdentity alice, {
  TestSessionManager? aliceBrain,
  TestSessionManager? bobBrain,
  Duration activeCallReconnectGrace = const Duration(seconds: 8),
}) async {
  final adapter = RecordingVoiceSignalingAdapter();
  final resolvedAliceBrain = aliceBrain ?? TestSessionManager();
  final resolvedBobBrain = bobBrain ?? TestSessionManager();
  final runtimeEvents = <String>[];
  final bobDb = RainDatabase(NativeDatabase.memory());
  final bob = RainIdentity(
    username: 'bob',
    displayName: 'Bob',
    createdAt: DateTime.now().millisecondsSinceEpoch,
    gender: RainGender.male,
  );

  await adapter.register('alice', 'alicepw');
  await adapter.register('bob', 'bobpw');
  await adapter.upsertFriendship('alice', 'bob');
  await aliceDb
      .into(aliceDb.friends)
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

  return _TwoUserCallHarness(
    adapter: adapter,
    aliceBrain: resolvedAliceBrain,
    bobBrain: resolvedBobBrain,
    bobDb: bobDb,
    aliceRuntime: _runtimeFor(
      aliceDb,
      alice,
      adapter,
      brain: resolvedAliceBrain,
      activeCallReconnectGrace: activeCallReconnectGrace,
      videoCallRendererFactory: const _TestVideoCallRendererFactory(),
      eventRecorder: _recordRuntimeEventFor(runtimeEvents, 'alice'),
    ),
    bobRuntime: _runtimeFor(
      bobDb,
      bob,
      adapter,
      brain: resolvedBobBrain,
      activeCallReconnectGrace: activeCallReconnectGrace,
      videoCallRendererFactory: const _TestVideoCallRendererFactory(),
      eventRecorder: _recordRuntimeEventFor(runtimeEvents, 'bob'),
    ),
    runtimeEvents: runtimeEvents,
  );
}

RuntimeEventRecorder _recordRuntimeEventFor(List<String> events, String owner) {
  return ({
    required String category,
    required String name,
    String severity = 'info',
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    events.add('$owner:$name');
  };
}

Future<String> _startAndAcceptHarnessCall(
  _TwoUserCallHarness harness, {
  required bool callerIsAlice,
  required protocol.CallMediaMode mediaMode,
}) async {
  final caller = callerIsAlice ? harness.aliceRuntime : harness.bobRuntime;
  final callee = callerIsAlice ? harness.bobRuntime : harness.aliceRuntime;
  final peerId = callerIsAlice ? 'bob' : 'alice';
  final callerUsername = callerIsAlice ? 'alice' : 'bob';
  final calleeUsername = callerIsAlice ? 'bob' : 'alice';

  switch (mediaMode) {
    case protocol.CallMediaMode.audio:
      await caller.startVoiceCall(peerId);
      break;
    case protocol.CallMediaMode.video:
      await caller.startVideoCall(peerId);
      break;
  }
  final callId = caller.voiceCallState.callId!;

  expect(caller.voiceCallState.phase, VoiceCallPhase.outgoingRinging);
  expect(caller.voiceCallState.isOutgoing, isTrue);
  expect(caller.voiceCallState.mediaMode, mediaMode);
  expect(harness.adapter.activePairLocks.values.single.callId, callId);
  expect(harness.adapter.activeUserLocks[callerUsername]?.callId, callId);
  expect(harness.adapter.activeUserLocks[calleeUsername]?.callId, callId);
  expect(harness.adapter.rooms[callId]?.caller, callerUsername);
  expect(harness.adapter.rooms[callId]?.callee, calleeUsername);
  expect(
    harness.adapter.rooms[callId]?.status,
    VoiceCallSignalingStatus.ringing,
  );

  await _waitForCondition(
    () => callee.voiceCallState.phase == VoiceCallPhase.incomingRinging,
    'Firebase ${mediaMode.name} invite to ring on first attempt',
  );
  expect(callee.voiceCallState.isOutgoing, isFalse);
  expect(callee.voiceCallState.mediaMode, mediaMode);

  await callee.acceptVoiceCall();
  await _waitForCondition(
    () =>
        caller.voiceCallState.phase == VoiceCallPhase.active &&
        callee.voiceCallState.phase == VoiceCallPhase.active,
    'Firebase ${mediaMode.name} call to become active on first attempt',
  );

  expect(
    harness.adapter.rooms[callId]?.status,
    VoiceCallSignalingStatus.connected,
  );
  expect(harness.adapter.activePairLocks.values.single.callId, callId);
  expect(harness.adapter.activeUserLocks[callerUsername]?.callId, callId);
  expect(harness.adapter.activeUserLocks[calleeUsername]?.callId, callId);
  expect(caller.voiceCallState.callId, callId);
  expect(callee.voiceCallState.callId, callId);
  expect(caller.voiceCallState.mediaMode, mediaMode);
  expect(callee.voiceCallState.mediaMode, mediaMode);
  return callId;
}

Future<void> _waitForHarnessCallIdle(
  _TwoUserCallHarness harness,
  String reason,
) {
  return _waitForCondition(
    () =>
        harness.aliceRuntime.voiceCallState.phase == VoiceCallPhase.idle &&
        harness.bobRuntime.voiceCallState.phase == VoiceCallPhase.idle,
    reason,
  );
}

class _TwoUserCallHarness {
  const _TwoUserCallHarness({
    required this.adapter,
    required this.aliceBrain,
    required this.bobBrain,
    required this.bobDb,
    required this.aliceRuntime,
    required this.bobRuntime,
    required this.runtimeEvents,
  });

  final RecordingVoiceSignalingAdapter adapter;
  final TestSessionManager aliceBrain;
  final TestSessionManager bobBrain;
  final RainDatabase bobDb;
  final RainRuntimeController aliceRuntime;
  final RainRuntimeController bobRuntime;
  final List<String> runtimeEvents;

  Future<void> start() async {
    await aliceRuntime.start();
    await bobRuntime.start();
  }

  Future<void> dispose() async {
    await aliceRuntime.dispose();
    await bobRuntime.dispose();
    await bobDb.close();
    await adapter.dispose();
  }
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
  Object? endCallError;
  int endCallAttempts = 0;
  int? failEndCallAttempt;

  Map<String, VoiceCallRoom> get rooms => _voice.rooms;

  Map<String, VoiceActivePairLock> get activePairLocks =>
      _voice.activePairLocks;

  Map<String, VoiceActiveUserLock> get activeUserLocks =>
      _voice.activeUserLocks;

  void seedActivePairLockForTest(VoiceActivePairLock lock) {
    _voice.seedActivePairLockForTest(lock);
  }

  void seedActiveUserLockForTest(VoiceActiveUserLock lock) {
    _voice.seedActiveUserLockForTest(lock);
  }

  void reemitCallForTest(String callId) {
    _voice.reemitCallForTest(callId);
  }

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
    endCallAttempts += 1;
    if (failEndCallAttempt == endCallAttempts) {
      throw StateError('failed to send hangup');
    }
    final error = endCallError;
    if (error != null) {
      throw error;
    }
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
  Completer<void>? voiceDisposeGate;
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
      phase: SessionPhase.connected,
      detail: 'Connected.',
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

  void emitTransientPeerDisconnect(String peerId) {
    final existing = _sessions[peerId];
    final session =
        existing?.copyWith(
          state: SessionState.reconnecting,
          phase: SessionPhase.reconnecting,
          detail: 'Peer transport reconnecting.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ) ??
        Session(
          peerId: peerId,
          state: SessionState.reconnecting,
          connectionType: ConnectionType.signaling,
          phase: SessionPhase.reconnecting,
          detail: 'Peer transport reconnecting.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          sender: (_) {},
        );
    _sessions[peerId] = session;
    _sessionChangedController.add(session);
    _peerDisconnectedController.add(peerId);
  }

  void seedSession(String peerId, SessionState state) {
    final existing = _sessions[peerId];
    final session =
        existing?.copyWith(
          state: state,
          phase: _phaseForState(state),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ) ??
        Session(
          peerId: peerId,
          state: state,
          connectionType: ConnectionType.signaling,
          phase: _phaseForState(state),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          sender: (_) {},
        );
    _sessions[peerId] = session;
    _sessionChangedController.add(session);
  }

  SessionPhase _phaseForState(SessionState state) {
    return switch (state) {
      SessionState.connecting => SessionPhase.openingDataChannels,
      SessionState.connected => SessionPhase.connected,
      SessionState.reconnecting => SessionPhase.reconnecting,
      SessionState.failed => SessionPhase.failed,
    };
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
  Future<void> selectAudioOutputDevice(String deviceId) async {}

  @override
  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    final gate = owner.voiceDisposeGate;
    if (gate != null) {
      await gate.future;
    }
    owner.stoppedAudioPeers.add(peerId);
    await _iceController.close();
    await _remoteTrackController.close();
    await _audioLevelController.close();
    await _stateController.close();
  }

  void emitIceCandidate(VoiceIceCandidate candidate) {
    _iceController.add(candidate);
  }

  void emitAudioLevel(VoiceMediaAudioLevel level) {
    _audioLevelController.add(level);
  }

  void emitConnectedForTest() {
    _emitConnected();
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
  MediaStream? get localStream =>
      hasLocalVideo ? _FakeMediaStream('local-video-stream') : null;

  @override
  MediaStreamTrack? get localVideoTrack => hasLocalVideo
      ? _FakeMediaStreamTrack('local-video-track', 'video')
      : null;

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
  Future<void> selectAudioOutputDevice(String deviceId) async {}

  @override
  Future<void> refreshProcessingConfig() async {}

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

  void emitRemoteVideoTrack() {
    _remoteTrackController.add(
      CallRemoteMediaTrack(
        track: _FakeMediaStreamTrack('remote-video-track', 'video'),
        streams: <MediaStream>[_FakeMediaStream('remote-video-stream')],
        receivedAt: DateTime.now(),
      ),
    );
  }
}

class _TestVideoCallRendererFactory implements VideoCallRendererFactory {
  const _TestVideoCallRendererFactory();

  @override
  VideoCallRendererHandle create() => _TestVideoCallRendererHandle();
}

class _FailingTestVideoCallRendererFactory implements VideoCallRendererFactory {
  _FailingTestVideoCallRendererFactory({
    this.throwOnCreateAt,
    this.throwOnRemoteAttach = false,
    this.remoteAutoFirstFrame = true,
  });

  final int? throwOnCreateAt;
  final bool throwOnRemoteAttach;
  final bool remoteAutoFirstFrame;
  int _createCount = 0;

  @override
  VideoCallRendererHandle create() {
    _createCount += 1;
    if (throwOnCreateAt == _createCount) {
      throw StateError('Video renderer create failed.');
    }
    return _TestVideoCallRendererHandle(
      throwOnAttach: throwOnRemoteAttach && _createCount == 2,
      autoFirstFrame: _createCount == 2 ? remoteAutoFirstFrame : true,
    );
  }
}

class _TestVideoCallRendererHandle implements VideoCallRendererHandle {
  _TestVideoCallRendererHandle({
    this.throwOnAttach = false,
    this.autoFirstFrame = true,
  });

  final bool throwOnAttach;
  final bool autoFirstFrame;
  MediaStream? _stream;
  void Function()? _onFirstFrameRendered;

  @override
  Future<void> initialize() async {}

  @override
  MediaStream? get srcObject => _stream;

  @override
  set srcObject(MediaStream? stream) {
    if (throwOnAttach && stream != null) {
      throw StateError('Video renderer attach failed.');
    }
    _stream = stream;
    if (stream != null && autoFirstFrame) {
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
  Widget buildView({Key? key, bool mirror = false}) {
    return SizedBox(key: key);
  }

  @override
  Future<void> dispose() async {
    _stream = null;
    _onFirstFrameRendered = null;
  }
}

class _FakeMediaStream extends Fake implements MediaStream {
  _FakeMediaStream(this._id);

  final String _id;

  @override
  String get id => _id;
}

class _FakeMediaStreamTrack extends Fake implements MediaStreamTrack {
  _FakeMediaStreamTrack(this._id, this._kind);

  final String _id;
  final String _kind;

  @override
  String get id => _id;

  @override
  String get kind => _kind;
}
