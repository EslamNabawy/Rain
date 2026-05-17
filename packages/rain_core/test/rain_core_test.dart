import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  test('username validation matches spec constraints', () {
    expect(RainIdentity.isValidUsername('alice_01'), isTrue);
    expect(RainIdentity.isValidUsername('ALICE'), isFalse);
    expect(RainIdentity.isValidUsername('ab'), isFalse);
  });

  test('displayTime falls back to receipt time when skew is large', () {
    final envelope = MessageEnvelope(
      id: '1',
      from: 'alice',
      to: 'bob',
      content: 'hi',
      sentAt: DateTime.now()
          .subtract(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      seq: 1,
      type: MessageType.text,
    );

    final receipt = DateTime.now();
    expect(displayTime(envelope, receipt), receipt);
  });

  test('identity repository preserves gender', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await IdentityRepository(database).saveIdentity(
      const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: RainGender.female,
      ),
    );

    final loaded = await IdentityRepository(database).loadIdentity();
    expect(loaded?.gender, RainGender.female);
  });

  test('friend store preserves gender', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final store = FriendStore(database);
    await store.upsertFriend(
      username: 'bob',
      displayName: 'Bob',
      state: FriendState.pendingIncoming,
      addedAt: 1,
      gender: RainGender.male,
    );

    final pending = await store.loadFriend('bob');
    expect(pending?.gender, RainGender.male);

    await store.markAccepted('bob', gender: RainGender.female);

    final accepted = await store.loadFriend('bob');
    expect(accepted?.state, FriendState.friend);
    expect(accepted?.gender, RainGender.female);

    await store.upsertFriend(
      username: 'bob',
      displayName: 'Bobby',
      state: FriendState.friend,
      addedAt: 1,
    );

    final renamed = await store.loadFriend('bob');
    expect(renamed?.displayName, 'Bobby');
    expect(renamed?.gender, RainGender.female);
  });

  test('friend presence keeps the last offline timestamp', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final store = FriendStore(database);
    await store.upsertFriend(
      username: 'bob',
      displayName: 'Bob',
      state: FriendState.friend,
      addedAt: 1,
    );

    await store.updatePresence('bob', true);
    final online = await store.loadFriend('bob');
    expect(online?.isOnline, isTrue);
    expect(online?.lastOnlineAt, isNull);

    await store.updatePresence('bob', false);
    final offline = await store.loadFriend('bob');
    expect(offline?.isOnline, isFalse);
    expect(offline?.lastOnlineAt, isNotNull);
  });

  test(
    'conversation timeline is ordered by timestamp, not peer sequence',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final store = MessageStore(database);
      final base = DateTime.now().millisecondsSinceEpoch;

      await store.storeOutgoingEnvelope(
        MessageEnvelope(
          id: 'out-1',
          from: 'alice',
          to: 'bob',
          content: 'first',
          sentAt: base,
          seq: 2,
          type: MessageType.text,
        ),
        status: MessageStatus.sent,
      );
      await store.storeIncomingEnvelope(
        MessageEnvelope(
          id: 'in-1',
          from: 'bob',
          to: 'alice',
          content: 'second',
          sentAt: base + 1000,
          seq: 1,
          type: MessageType.text,
        ),
        receivedAt: DateTime.fromMillisecondsSinceEpoch(base + 1000),
      );

      final messages = await store.watchConversation('bob').first;
      expect(messages.map((m) => m.id), <String>['out-1', 'in-1']);
    },
  );

  test(
    'unsequenced file messages do not move chat sequence trackers',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);

      final store = MessageStore(database);
      final outgoing = await store.composeOutgoingEnvelope(
        from: 'alice',
        to: 'bob',
        content: 'file',
        type: MessageType.file,
        trackSequence: false,
      );

      expect(outgoing.seq, 0);
      expect(await store.nextOutgoingSeq('bob'), 1);

      await store.forceStoreIncomingEnvelope(
        MessageEnvelope(
          id: 'file-1',
          from: 'bob',
          to: 'alice',
          content: 'file',
          sentAt: DateTime.now().millisecondsSinceEpoch,
          seq: 0,
          type: MessageType.file,
        ),
        receivedAt: DateTime.now(),
        trackSequence: false,
      );

      expect(await store.lastIncomingSeq('bob'), 0);
      final textResult = await store.storeIncomingEnvelope(
        MessageEnvelope(
          id: 'text-1',
          from: 'bob',
          to: 'alice',
          content: 'hello',
          sentAt: DateTime.now().millisecondsSinceEpoch,
          seq: 1,
          type: MessageType.text,
        ),
        receivedAt: DateTime.now(),
      );
      expect(textResult.disposition, IncomingMessageDisposition.stored);
    },
  );
}
