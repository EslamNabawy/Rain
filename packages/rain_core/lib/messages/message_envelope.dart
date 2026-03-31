import 'dart:convert';

enum MessageType { text, system }

enum MessageStatus {
  queued,
  sending,
  sent,
  pendingAck,
  delivered,
  failed,
}

class MessageEnvelope {
  const MessageEnvelope({
    required this.id,
    required this.from,
    required this.to,
    required this.content,
    required this.sentAt,
    required this.seq,
    required this.type,
  });

  final String id;
  final String from;
  final String to;
  final String content;
  final int sentAt;
  final int seq;
  final MessageType type;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'from': from,
      'to': to,
      'content': content,
      'sentAt': sentAt,
      'seq': seq,
      'type': type.name,
    };
  }

  String toWireString() => jsonEncode(toJson());

  static MessageEnvelope fromWireString(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return MessageEnvelope(
      id: json['id'] as String,
      from: json['from'] as String,
      to: json['to'] as String,
      content: json['content'] as String,
      sentAt: (json['sentAt'] as num).toInt(),
      seq: (json['seq'] as num).toInt(),
      type: MessageType.values.byName(json['type'] as String),
    );
  }
}

const clockSkewToleranceMs = 60 * 1000;
const gapWaitMs = 5000;
const ackTimeoutMs = 10000;
const maxAutoResends = 1;

DateTime displayTime(MessageEnvelope envelope, DateTime receivedAt) {
  final sentAt = DateTime.fromMillisecondsSinceEpoch(envelope.sentAt);
  final skew = receivedAt.difference(sentAt).abs();
  return skew > const Duration(milliseconds: clockSkewToleranceMs)
      ? receivedAt
      : sentAt;
}

