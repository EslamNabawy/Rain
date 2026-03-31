import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  late RainDatabase database;
  late MessageStore messageStore;
  late OfflineQueueStore offlineQueueStore;

  setUp(() {
    database = RainDatabase(NativeDatabase.memory());
    messageStore = MessageStore(database);
    offlineQueueStore = OfflineQueueStore(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('incoming message is stored before ack is sent', () async {
    final service = MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
    );

    final envelope = MessageEnvelope(
      id: 'msg-1',
      from: 'alice',
      to: 'bob',
      content: 'hello',
      sentAt: DateTime.now().millisecondsSinceEpoch,
      seq: 1,
      type: MessageType.text,
    );

    var ackSent = false;
    await service.handleIncomingEnvelope(
      envelope,
      receivedAt: DateTime.now(),
      sendAck: (String rawAck) async {
        ackSent = true;
        final ack = jsonDecode(rawAck) as Map<String, dynamic>;
        expect(ack['type'], 'ack');
        expect(ack['ackId'], envelope.id);
        expect(await messageStore.containsMessage(envelope.id), isTrue);
      },
    );

    expect(ackSent, isTrue);
    expect(await messageStore.lastIncomingSeq('alice'), 1);
    service.dispose();
  });

  test('gap messages are buffered and flushed in seq order', () async {
    final service = MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      gapWait: const Duration(milliseconds: 100),
    );

    final seq2 = MessageEnvelope(
      id: 'msg-2',
      from: 'alice',
      to: 'bob',
      content: 'second',
      sentAt: DateTime.now().millisecondsSinceEpoch,
      seq: 2,
      type: MessageType.text,
    );
    final seq1 = MessageEnvelope(
      id: 'msg-1',
      from: 'alice',
      to: 'bob',
      content: 'first',
      sentAt: DateTime.now().millisecondsSinceEpoch,
      seq: 1,
      type: MessageType.text,
    );

    final ackedIds = <String>[];

    await service.handleIncomingEnvelope(
      seq2,
      receivedAt: DateTime.now(),
      sendAck: (String rawAck) async {
        ackedIds.add((jsonDecode(rawAck) as Map<String, dynamic>)['ackId'] as String);
      },
    );

    expect(await messageStore.containsMessage(seq2.id), isFalse);
    expect(ackedIds, isEmpty);

    await service.handleIncomingEnvelope(
      seq1,
      receivedAt: DateTime.now(),
      sendAck: (String rawAck) async {
        ackedIds.add((jsonDecode(rawAck) as Map<String, dynamic>)['ackId'] as String);
      },
    );

    expect(await messageStore.containsMessage(seq1.id), isTrue);
    expect(await messageStore.containsMessage(seq2.id), isTrue);
    expect(ackedIds, <String>['msg-1', 'msg-2']);

    final rows = await (database.select(database.messages)
          ..where((tbl) => tbl.peerId.equals('alice'))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.seq)]))
        .get();
    expect(rows.map((row) => row.id).toList(growable: false), <String>['msg-1', 'msg-2']);
    service.dispose();
  });

  test('ack timeout retries once and then marks the message failed', () async {
    final service = MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      ackTimeout: const Duration(milliseconds: 20),
      autoResendLimit: 1,
    );

    final envelope = MessageEnvelope(
      id: 'out-1',
      from: 'bob',
      to: 'alice',
      content: 'still there?',
      sentAt: DateTime.now().millisecondsSinceEpoch,
      seq: 1,
      type: MessageType.text,
    );

    final sentPayloads = <String>[];
    await service.sendEnvelope(
      envelope,
      sendChat: (String payload) async {
        sentPayloads.add(payload);
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(sentPayloads.length, 2);

    final messageRow = await (database.select(database.messages)
          ..where((tbl) => tbl.id.equals(envelope.id))
          ..limit(1))
        .getSingle();
    expect(messageRow.status, MessageStatus.failed.name);

    final queuedRow = await (database.select(database.queuedMessages)
          ..where((tbl) => tbl.id.equals(envelope.id))
          ..limit(1))
        .getSingle();
    expect(queuedRow.status, QueuedMessageStatus.failed.name);
    service.dispose();
  });
}
