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
        ackedIds.add(
          (jsonDecode(rawAck) as Map<String, dynamic>)['ackId'] as String,
        );
      },
    );

    expect(await messageStore.containsMessage(seq2.id), isFalse);
    expect(ackedIds, isEmpty);

    await service.handleIncomingEnvelope(
      seq1,
      receivedAt: DateTime.now(),
      sendAck: (String rawAck) async {
        ackedIds.add(
          (jsonDecode(rawAck) as Map<String, dynamic>)['ackId'] as String,
        );
      },
    );

    expect(await messageStore.containsMessage(seq1.id), isTrue);
    expect(await messageStore.containsMessage(seq2.id), isTrue);
    expect(ackedIds, <String>['msg-1', 'msg-2']);

    final rows =
        await (database.select(database.messages)
              ..where((tbl) => tbl.peerId.equals('alice'))
              ..orderBy([(tbl) => OrderingTerm.asc(tbl.seq)]))
            .get();
    expect(rows.map((row) => row.id).toList(growable: false), <String>[
      'msg-1',
      'msg-2',
    ]);
    service.dispose();
  });

  test('onStored callback runs only when a message is persisted', () async {
    final service = MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      gapWait: const Duration(milliseconds: 100),
    );

    final storedIds = <String>[];
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

    await service.handleIncomingEnvelope(
      seq2,
      receivedAt: DateTime.now(),
      sendAck: (_) async {},
      onStored: (MessageEnvelope envelope) {
        storedIds.add(envelope.id);
      },
    );
    expect(storedIds, isEmpty);

    await service.handleIncomingEnvelope(
      seq1,
      receivedAt: DateTime.now(),
      sendAck: (_) async {},
      onStored: (MessageEnvelope envelope) {
        storedIds.add(envelope.id);
      },
    );
    expect(storedIds, <String>['msg-1', 'msg-2']);

    await service.handleIncomingEnvelope(
      seq1,
      receivedAt: DateTime.now(),
      sendAck: (_) async {},
      onStored: (MessageEnvelope envelope) {
        storedIds.add(envelope.id);
      },
    );
    expect(storedIds, <String>['msg-1', 'msg-2']);
    service.dispose();
  });

  test(
    'late unknown messages are stored before ack to avoid false delivery',
    () async {
      final service = MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      );
      await messageStore.setIncomingSeq('alice', 5);

      final envelope = MessageEnvelope(
        id: 'late-but-new',
        from: 'alice',
        to: 'bob',
        content: 'still must appear',
        sentAt: DateTime.now().millisecondsSinceEpoch,
        seq: 3,
        type: MessageType.text,
      );
      final storedIds = <String>[];
      final ackedIds = <String>[];

      await service.handleIncomingEnvelope(
        envelope,
        receivedAt: DateTime.now(),
        sendAck: (String rawAck) async {
          final ack = jsonDecode(rawAck) as Map<String, dynamic>;
          ackedIds.add(ack['ackId'] as String);
          expect(await messageStore.containsMessage(envelope.id), isTrue);
        },
        onStored: (MessageEnvelope envelope) {
          storedIds.add(envelope.id);
        },
      );

      expect(storedIds, <String>['late-but-new']);
      expect(ackedIds, <String>['late-but-new']);
      expect(await messageStore.lastIncomingSeq('alice'), 5);
      final rows = await database.select(database.messages).get();
      expect(rows.single.content, 'still must appear');
      service.dispose();
    },
  );

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

    final messageRow =
        await (database.select(database.messages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(messageRow.status, MessageStatus.failed.name);

    final queuedRow =
        await (database.select(database.queuedMessages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(queuedRow.status, QueuedMessageStatus.failed.name);
    service.dispose();
  });

  test('send failure keeps the outgoing message locally queued', () async {
    final service = MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
    );

    final envelope = MessageEnvelope(
      id: 'out-send-fails',
      from: 'alice',
      to: 'bob',
      content: 'send this later',
      sentAt: DateTime.now().millisecondsSinceEpoch,
      seq: 1,
      type: MessageType.text,
    );

    final sent = await service.sendEnvelope(
      envelope,
      sendChat: (_) => throw StateError('data channel closed'),
    );
    expect(sent, isFalse);

    final messageRow =
        await (database.select(database.messages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(messageRow.status, MessageStatus.queued.name);

    final queuedRow =
        await (database.select(database.queuedMessages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(queuedRow.status, QueuedMessageStatus.queued.name);
    service.dispose();
  });

  test(
    'flushQueue sends queued messages but leaves failed ones for manual retry',
    () async {
      final service = MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
        flushDelay: Duration.zero,
      );

      await offlineQueueStore.enqueue(
        MessageEnvelope(
          id: 'queued-1',
          from: 'alice',
          to: 'bob',
          content: 'queued',
          sentAt: 1,
          seq: 1,
          type: MessageType.text,
        ),
      );
      await offlineQueueStore.enqueue(
        MessageEnvelope(
          id: 'failed-1',
          from: 'alice',
          to: 'bob',
          content: 'failed',
          sentAt: 2,
          seq: 2,
          type: MessageType.text,
        ),
      );
      await offlineQueueStore.markStatus(
        'failed-1',
        QueuedMessageStatus.failed,
      );

      final sentPayloads = <String>[];
      await service.flushQueue(
        'alice',
        'bob',
        sendChat: (String payload) async => sentPayloads.add(payload),
      );

      expect(sentPayloads, hasLength(1));
      final sentEnvelope = MessageEnvelope.fromWireString(sentPayloads.single);
      expect(sentEnvelope.id, 'queued-1');

      final failedRow =
          await (database.select(database.queuedMessages)
                ..where((tbl) => tbl.id.equals('failed-1'))
                ..limit(1))
              .getSingle();
      expect(failedRow.status, QueuedMessageStatus.failed.name);
      service.dispose();
    },
  );

  test('in-flight queued messages recover to queued after restart', () async {
    final envelope = MessageEnvelope(
      id: 'stuck-sending',
      from: 'alice',
      to: 'bob',
      content: 'recover me',
      sentAt: DateTime.now().millisecondsSinceEpoch,
      seq: 1,
      type: MessageType.text,
    );
    await messageStore.storeOutgoingEnvelope(
      envelope,
      status: MessageStatus.sent,
    );
    await offlineQueueStore.enqueue(envelope);
    await offlineQueueStore.markStatus(
      envelope.id,
      QueuedMessageStatus.sending,
    );

    final recovered = await offlineQueueStore.recoverInFlightMessages();

    expect(recovered, 1);
    final messageRow =
        await (database.select(database.messages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(messageRow.status, MessageStatus.queued.name);

    final queuedRow =
        await (database.select(database.queuedMessages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(queuedRow.status, QueuedMessageStatus.queued.name);
  });

  test('offline queue is loaded in seq order', () async {
    await offlineQueueStore.enqueue(
      MessageEnvelope(
        id: 'msg-2',
        from: 'alice',
        to: 'bob',
        content: 'second',
        sentAt: 1,
        seq: 2,
        type: MessageType.text,
      ),
    );
    await offlineQueueStore.enqueue(
      MessageEnvelope(
        id: 'msg-1',
        from: 'alice',
        to: 'bob',
        content: 'first',
        sentAt: 2,
        seq: 1,
        type: MessageType.text,
      ),
    );

    final queued = await offlineQueueStore.loadQueue('bob');
    expect(
      queued
          .map((QueuedEnvelope message) => message.id)
          .toList(growable: false),
      <String>['msg-1', 'msg-2'],
    );
  });
}
