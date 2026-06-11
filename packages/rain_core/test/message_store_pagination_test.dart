/// # message_store_pagination_test.dart — rain_core package
///
/// Tests for MessageStore cursor-based pagination ensuring correct page ordering, no duplicates across pages, and proper limit enforcement.
///
/// **Key types:** None (test file)
///
/// **Package:** rain_core
///
/// **Depends on:** drift/native.dart, flutter_test, rain_core
///
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  late RainDatabase database;
  late MessageStore store;

  setUp(() {
    database = RainDatabase(NativeDatabase.memory());
    store = MessageStore(database);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'conversation pages load latest rows first without duplicates',
    () async {
      const peerId = 'bob';
      const base = 1770000000000;
      for (var index = 1; index <= 75; index += 1) {
        await store.storeOutgoingEnvelope(
          MessageEnvelope(
            id: 'm-$index',
            from: 'alice',
            to: peerId,
            content: 'message $index',
            sentAt: base + index,
            seq: index,
            type: MessageType.text,
          ),
        );
      }

      final latest = await store.loadConversationPage(peerId, limit: 20);
      final older = await store.loadConversationPage(
        peerId,
        limit: 20,
        before: MessagePageCursor.fromMessage(latest.first),
      );

      expect(
        latest.map((message) => message.id).toList(growable: false),
        List<String>.generate(20, (index) => 'm-${index + 56}'),
      );
      expect(
        older.map((message) => message.id).toList(growable: false),
        List<String>.generate(20, (index) => 'm-${index + 36}'),
      );
      expect(
        <String>{
          ...latest.map((message) => message.id),
        }.intersection(<String>{...older.map((message) => message.id)}),
        isEmpty,
      );
    },
  );

  test('live conversation tail is bounded to the newest page', () async {
    const peerId = 'bob';
    const base = 1770000000000;
    for (var index = 1; index <= 5; index += 1) {
      await store.storeOutgoingEnvelope(
        MessageEnvelope(
          id: 'tail-$index',
          from: 'alice',
          to: peerId,
          content: 'message $index',
          sentAt: base + index,
          seq: index,
          type: MessageType.text,
        ),
      );
    }

    final messages = await store.watchConversationTail(peerId, limit: 3).first;

    expect(
      messages.map((message) => message.id).toList(growable: false),
      <String>['tail-3', 'tail-4', 'tail-5'],
    );
  });
}
