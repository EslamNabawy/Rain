import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  test('clearSessionData removes all persisted local session state', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await IdentityRepository(database).saveIdentity(
      const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: RainGender.male,
      ),
    );

    await database
        .into(database.friends)
        .insert(
          FriendsCompanion.insert(
            username: 'bob',
            displayName: 'Bob',
            state: 'friend',
            addedAt: 2,
          ),
        );
    await database
        .into(database.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'm1',
            peerId: 'bob',
            content: 'hello',
            sentAt: 3,
            seq: 1,
            type: 'text',
            status: 'sent',
            isOutgoing: true,
          ),
        );
    await database
        .into(database.queuedMessages)
        .insert(
          QueuedMessagesCompanion.insert(
            id: 'q1',
            to: 'bob',
            content: 'queued',
            sentAt: 4,
            seq: 2,
            status: 'queued',
          ),
        );
    await database
        .into(database.connectionMemoryTable)
        .insert(
          ConnectionMemoryTableCompanion.insert(
            peerId: 'bob',
            lastConnectedAt: 5,
            cachedIce: '[]',
            fingerprint: 'fp',
          ),
        );
    await database
        .into(database.messageSeqTracker)
        .insert(MessageSeqTrackerCompanion.insert(peerId: 'bob', lastSeq: 2));

    await database.clearSessionData();

    expect(await IdentityRepository(database).loadIdentity(), isNull);
    expect(await database.select(database.friends).get(), isEmpty);
    expect(await database.select(database.messages).get(), isEmpty);
    expect(await database.select(database.queuedMessages).get(), isEmpty);
    expect(
      await database.select(database.connectionMemoryTable).get(),
      isEmpty,
    );
    expect(await database.select(database.messageSeqTracker).get(), isEmpty);
  });
}
