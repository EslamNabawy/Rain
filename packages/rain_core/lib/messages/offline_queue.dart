import 'package:drift/drift.dart';

import '../database/rain_database.dart';
import 'message_envelope.dart';

enum QueuedMessageStatus { queued, sending, sent, failed }

class QueuedEnvelope {
  const QueuedEnvelope({
    required this.id,
    required this.to,
    required this.content,
    required this.sentAt,
    required this.seq,
    required this.status,
  });

  final String id;
  final String to;
  final String content;
  final int sentAt;
  final int seq;
  final QueuedMessageStatus status;

  MessageEnvelope toEnvelope({
    required String from,
    MessageType type = MessageType.text,
  }) {
    return MessageEnvelope(
      id: id,
      from: from,
      to: to,
      content: content,
      sentAt: sentAt,
      seq: seq,
      type: type,
    );
  }
}

class OfflineQueueStore {
  OfflineQueueStore(this._database);

  final RainDatabase _database;

  Stream<List<QueuedEnvelope>> watchQueue(String peerId) {
    final query = _database.select(_database.queuedMessages)
      ..where((QueuedMessages row) => row.to.equals(peerId))
      ..orderBy(<OrderingTerm Function(QueuedMessages)>[
        (QueuedMessages row) => OrderingTerm.asc(row.sentAt),
      ]);
    return query.watch().map(
      (List<QueuedMessage> rows) => rows.map(_mapQueuedMessage).toList(growable: false),
    );
  }

  Future<List<QueuedEnvelope>> loadQueue(String peerId) async {
    final query = _database.select(_database.queuedMessages)
      ..where((QueuedMessages row) => row.to.equals(peerId))
      ..orderBy(<OrderingTerm Function(QueuedMessages)>[
        (QueuedMessages row) => OrderingTerm.asc(row.sentAt),
      ]);
    return (await query.get()).map(_mapQueuedMessage).toList(growable: false);
  }

  Future<void> enqueue(MessageEnvelope envelope) {
    return _database.into(_database.queuedMessages).insertOnConflictUpdate(
      QueuedMessagesCompanion.insert(
        id: envelope.id,
        to: envelope.to,
        content: envelope.content,
        sentAt: envelope.sentAt,
        seq: envelope.seq,
        status: QueuedMessageStatus.queued.name,
      ),
    );
  }

  Future<void> markStatus(String id, QueuedMessageStatus status) {
    return (_database.update(_database.queuedMessages)
          ..where((QueuedMessages row) => row.id.equals(id)))
        .write(
          QueuedMessagesCompanion(status: Value<String>(status.name)),
        );
  }

  Future<void> remove(String id) {
    return (_database.delete(_database.queuedMessages)
          ..where((QueuedMessages row) => row.id.equals(id)))
        .go();
  }

  QueuedEnvelope _mapQueuedMessage(QueuedMessage row) {
    return QueuedEnvelope(
      id: row.id,
      to: row.to,
      content: row.content,
      sentAt: row.sentAt,
      seq: row.seq,
      status: QueuedMessageStatus.values.byName(row.status),
    );
  }
}
