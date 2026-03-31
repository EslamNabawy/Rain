import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/rain_database.dart';
import 'message_envelope.dart';

enum IncomingMessageDisposition { stored, duplicate, gap, late }

class StoredMessage {
  const StoredMessage({
    required this.id,
    required this.peerId,
    required this.content,
    required this.sentAt,
    required this.seq,
    required this.type,
    required this.status,
    required this.isOutgoing,
  });

  final String id;
  final String peerId;
  final String content;
  final int sentAt;
  final int seq;
  final MessageType type;
  final MessageStatus status;
  final bool isOutgoing;
}

class IncomingMessageResult {
  const IncomingMessageResult({
    required this.disposition,
    this.message,
  });

  final IncomingMessageDisposition disposition;
  final StoredMessage? message;
}

class MessageStore {
  MessageStore(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final RainDatabase _database;
  final Uuid _uuid;

  Stream<List<StoredMessage>> watchConversation(String peerId) {
    final query = _database.select(_database.messages)
      ..where((Messages row) => row.peerId.equals(peerId))
      ..orderBy(<OrderingTerm Function(Messages)>[
        (Messages row) => OrderingTerm.asc(row.seq),
        (Messages row) => OrderingTerm.asc(row.sentAt),
      ]);
    return query.watch().map(
      (List<Message> rows) => rows.map(_mapStoredMessage).toList(growable: false),
    );
  }

  Future<bool> containsMessage(String id) async {
    final query = _database.select(_database.messages)
      ..where((Messages row) => row.id.equals(id))
      ..limit(1);
    return await query.getSingleOrNull() != null;
  }

  Future<MessageEnvelope> composeOutgoingEnvelope({
    required String from,
    required String to,
    required String content,
    MessageType type = MessageType.text,
  }) async {
    final seq = await nextOutgoingSeq(to);
    return MessageEnvelope(
      id: _uuid.v4(),
      from: from,
      to: to,
      content: content,
      sentAt: DateTime.now().millisecondsSinceEpoch,
      seq: seq,
      type: type,
    );
  }

  Future<int> nextOutgoingSeq(String peerId) {
    return _database.transaction(() async {
      final key = _outgoingSeqKey(peerId);
      final current = await _loadTrackedSeq(key);
      final next = current + 1;
      await _upsertTrackedSeq(key, next);
      return next;
    });
  }

  Future<IncomingMessageResult> storeIncomingEnvelope(
    MessageEnvelope envelope, {
    required DateTime receivedAt,
  }) {
    return _database.transaction(() async {
      if (await containsMessage(envelope.id)) {
        return const IncomingMessageResult(
          disposition: IncomingMessageDisposition.duplicate,
        );
      }

      final lastSeq = await _loadTrackedSeq(_incomingSeqKey(envelope.from));
      if (envelope.seq <= lastSeq) {
        return const IncomingMessageResult(
          disposition: IncomingMessageDisposition.late,
        );
      }
      if (envelope.seq > lastSeq + 1) {
        return const IncomingMessageResult(
          disposition: IncomingMessageDisposition.gap,
        );
      }

      final message = await _persistIncoming(
        envelope,
        sentAt: displayTime(envelope, receivedAt).millisecondsSinceEpoch,
      );
      await _upsertTrackedSeq(_incomingSeqKey(envelope.from), envelope.seq);
      return IncomingMessageResult(
        disposition: IncomingMessageDisposition.stored,
        message: message,
      );
    });
  }

  Future<StoredMessage> forceStoreIncomingEnvelope(
    MessageEnvelope envelope, {
    required DateTime receivedAt,
  }) {
    return _database.transaction(() async {
      final message = await _persistIncoming(
        envelope,
        sentAt: displayTime(envelope, receivedAt).millisecondsSinceEpoch,
      );
      await _upsertTrackedSeq(_incomingSeqKey(envelope.from), envelope.seq);
      return message;
    });
  }

  Future<StoredMessage> storeOutgoingEnvelope(
    MessageEnvelope envelope, {
    MessageStatus status = MessageStatus.sent,
  }) {
    return _database.transaction(() async {
      final message = StoredMessage(
        id: envelope.id,
        peerId: envelope.to,
        content: envelope.content,
        sentAt: envelope.sentAt,
        seq: envelope.seq,
        type: envelope.type,
        status: status,
        isOutgoing: true,
      );
      await _database.into(_database.messages).insertOnConflictUpdate(
        MessagesCompanion.insert(
          id: message.id,
          peerId: message.peerId,
          content: message.content,
          sentAt: message.sentAt,
          seq: message.seq,
          type: message.type.name,
          status: message.status.name,
          isOutgoing: message.isOutgoing,
        ),
      );
      return message;
    });
  }

  Future<void> markMessageStatus(String id, MessageStatus status) {
    return (_database.update(_database.messages)
          ..where((Messages row) => row.id.equals(id)))
        .write(
          MessagesCompanion(status: Value<String>(status.name)),
        );
  }

  Future<int> lastIncomingSeq(String peerId) {
    return _loadTrackedSeq(_incomingSeqKey(peerId));
  }

  Future<void> setIncomingSeq(String peerId, int seq) {
    return _upsertTrackedSeq(_incomingSeqKey(peerId), seq);
  }

  Future<int> _loadTrackedSeq(String peerId) async {
    final query = _database.select(_database.messageSeqTracker)
      ..where((MessageSeqTracker row) => row.peerId.equals(peerId))
      ..limit(1);
    final existing = await query.getSingleOrNull();
    return existing?.lastSeq ?? 0;
  }

  Future<StoredMessage> _persistIncoming(
    MessageEnvelope envelope, {
    required int sentAt,
  }) async {
    final message = StoredMessage(
      id: envelope.id,
      peerId: envelope.from,
      content: envelope.content,
      sentAt: sentAt,
      seq: envelope.seq,
      type: envelope.type,
      status: MessageStatus.delivered,
      isOutgoing: false,
    );
    await _database.into(_database.messages).insert(
      MessagesCompanion.insert(
        id: message.id,
        peerId: message.peerId,
        content: message.content,
        sentAt: message.sentAt,
        seq: message.seq,
        type: message.type.name,
        status: message.status.name,
        isOutgoing: message.isOutgoing,
      ),
    );
    return message;
  }

  Future<void> _upsertTrackedSeq(String peerId, int seq) {
    return _database.into(_database.messageSeqTracker).insertOnConflictUpdate(
      MessageSeqTrackerCompanion.insert(
        peerId: peerId,
        lastSeq: seq,
      ),
    );
  }

  StoredMessage _mapStoredMessage(Message row) {
    return StoredMessage(
      id: row.id,
      peerId: row.peerId,
      content: row.content,
      sentAt: row.sentAt,
      seq: row.seq,
      type: MessageType.values.byName(row.type),
      status: MessageStatus.values.byName(row.status),
      isOutgoing: row.isOutgoing,
    );
  }

  String _incomingSeqKey(String peerId) => 'in:$peerId';
  String _outgoingSeqKey(String peerId) => 'out:$peerId';
}

