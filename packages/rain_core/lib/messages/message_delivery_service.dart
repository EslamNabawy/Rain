import 'dart:async';
import 'dart:convert';

import 'message_envelope.dart';
import 'message_store.dart';
import 'offline_queue.dart';

class MessageDeliveryService {
  MessageDeliveryService({
    required MessageStore messageStore,
    required OfflineQueueStore offlineQueueStore,
    Duration ackTimeout = const Duration(milliseconds: ackTimeoutMs),
    Duration gapWait = const Duration(milliseconds: gapWaitMs),
    Duration flushDelay = const Duration(milliseconds: 10),
    int autoResendLimit = maxAutoResends,
  }) : _messageStore = messageStore,
       _offlineQueueStore = offlineQueueStore,
       _ackTimeout = ackTimeout,
       _gapWait = gapWait,
       _flushDelay = flushDelay,
       _autoResendLimit = autoResendLimit;

  final MessageStore _messageStore;
  final OfflineQueueStore _offlineQueueStore;
  final Duration _ackTimeout;
  final Duration _gapWait;
  final Duration _flushDelay;
  final int _autoResendLimit;
  final Map<String, _AckTracker> _ackTrackers = <String, _AckTracker>{};
  final Map<String, Map<int, _BufferedEnvelope>> _gapBuffers =
      <String, Map<int, _BufferedEnvelope>>{};

  Future<void> handleIncomingEnvelope(
    MessageEnvelope envelope, {
    required DateTime receivedAt,
    required FutureOr<void> Function(String rawAck) sendAck,
  }) async {
    final result = await _messageStore.storeIncomingEnvelope(
      envelope,
      receivedAt: receivedAt,
    );

    switch (result.disposition) {
      case IncomingMessageDisposition.duplicate:
      case IncomingMessageDisposition.late:
        await sendAck(_encodeAck(envelope.id));
        break;
      case IncomingMessageDisposition.gap:
        _bufferGap(envelope, receivedAt, sendAck);
        break;
      case IncomingMessageDisposition.stored:
        await sendAck(_encodeAck(envelope.id));
        await _flushBuffered(envelope.from, sendAck);
        break;
    }
  }

  Future<void> handleControlMessage(String rawMessage) async {
    final json = jsonDecode(rawMessage) as Map<String, dynamic>;
    if (json['type'] != 'ack') {
      return;
    }
    final ackId = json['ackId'] as String;
    await _acknowledge(ackId);
  }

  Future<void> queueOutgoing(MessageEnvelope envelope) async {
    await _messageStore.storeOutgoingEnvelope(
      envelope,
      status: MessageStatus.queued,
    );
    await _offlineQueueStore.enqueue(envelope);
  }

  Future<void> sendEnvelope(
    MessageEnvelope envelope, {
    required Future<void> Function(String payload) sendChat,
  }) async {
    await _offlineQueueStore.enqueue(envelope);
    await _offlineQueueStore.markStatus(envelope.id, QueuedMessageStatus.sending);
    await _messageStore.storeOutgoingEnvelope(
      envelope,
      status: MessageStatus.sent,
    );
    await sendChat(envelope.toWireString());
    _armAckTimer(envelope, sendChat);
  }

  Future<void> flushQueue(
    String selfUsername,
    String peerId, {
    required Future<void> Function(String payload) sendChat,
  }) async {
    final queued = await _offlineQueueStore.loadQueue(peerId);
    for (final message in queued) {
      await Future<void>.delayed(_flushDelay);
      await _offlineQueueStore.markStatus(message.id, QueuedMessageStatus.sending);
      final envelope = message.toEnvelope(from: selfUsername);
      await sendEnvelope(envelope, sendChat: sendChat);
    }
  }

  void dispose() {
    for (final tracker in _ackTrackers.values) {
      tracker.timer.cancel();
    }
    _ackTrackers.clear();

    for (final byPeer in _gapBuffers.values) {
      for (final pending in byPeer.values) {
        pending.timer.cancel();
      }
    }
    _gapBuffers.clear();
  }

  void _armAckTimer(
    MessageEnvelope envelope,
    Future<void> Function(String payload) sendChat,
  ) {
    _ackTrackers.remove(envelope.id)?.timer.cancel();
    _ackTrackers[envelope.id] = _AckTracker(
      envelope: envelope,
      retries: 0,
      timer: Timer(_ackTimeout, () async {
        await _handleAckTimeout(envelope.id, sendChat);
      }),
    );
  }

  Future<void> _acknowledge(String ackId) async {
    final tracker = _ackTrackers.remove(ackId);
    tracker?.timer.cancel();
    await _messageStore.markMessageStatus(ackId, MessageStatus.delivered);
    await _offlineQueueStore.remove(ackId);
  }

  void _bufferGap(
    MessageEnvelope envelope,
    DateTime receivedAt,
    FutureOr<void> Function(String rawAck) sendAck,
  ) {
    final byPeer = _gapBuffers.putIfAbsent(
      envelope.from,
      () => <int, _BufferedEnvelope>{},
    );
    byPeer[envelope.seq] = _BufferedEnvelope(
      envelope: envelope,
      receivedAt: receivedAt,
      timer: Timer(_gapWait, () async {
        final pending = byPeer.remove(envelope.seq);
        if (pending == null) {
          return;
        }
        await _messageStore.forceStoreIncomingEnvelope(
          pending.envelope,
          receivedAt: pending.receivedAt,
        );
        await sendAck(_encodeAck(pending.envelope.id));
        await _flushBuffered(pending.envelope.from, sendAck);
      }),
    );
  }

  String _encodeAck(String messageId) {
    return jsonEncode(<String, String>{'type': 'ack', 'ackId': messageId});
  }

  Future<void> _flushBuffered(
    String peerId,
    FutureOr<void> Function(String rawAck) sendAck,
  ) async {
    final byPeer = _gapBuffers[peerId];
    if (byPeer == null || byPeer.isEmpty) {
      return;
    }

    var expected = await _messageStore.lastIncomingSeq(peerId) + 1;
    while (byPeer.containsKey(expected)) {
      final pending = byPeer.remove(expected)!;
      pending.timer.cancel();
      await _messageStore.forceStoreIncomingEnvelope(
        pending.envelope,
        receivedAt: pending.receivedAt,
      );
      await sendAck(_encodeAck(pending.envelope.id));
      expected += 1;
    }

    if (byPeer.isEmpty) {
      _gapBuffers.remove(peerId);
    }
  }

  Future<void> _handleAckTimeout(
    String messageId,
    Future<void> Function(String payload) sendChat,
  ) async {
    final tracker = _ackTrackers[messageId];
    if (tracker == null) {
      return;
    }
    if (tracker.retries >= _autoResendLimit) {
      _ackTrackers.remove(messageId)?.timer.cancel();
      await _messageStore.markMessageStatus(messageId, MessageStatus.failed);
      await _offlineQueueStore.markStatus(messageId, QueuedMessageStatus.failed);
      return;
    }

    await _messageStore.markMessageStatus(messageId, MessageStatus.pendingAck);
    await sendChat(tracker.envelope.toWireString());
    _ackTrackers[messageId] = tracker.copyWith(
      retries: tracker.retries + 1,
      timer: Timer(_ackTimeout, () async {
        await _handleAckTimeout(messageId, sendChat);
      }),
    );
  }
}

class _AckTracker {
  const _AckTracker({
    required this.envelope,
    required this.retries,
    required this.timer,
  });

  final MessageEnvelope envelope;
  final int retries;
  final Timer timer;

  _AckTracker copyWith({int? retries, Timer? timer}) {
    return _AckTracker(
      envelope: envelope,
      retries: retries ?? this.retries,
      timer: timer ?? this.timer,
    );
  }
}

class _BufferedEnvelope {
  const _BufferedEnvelope({
    required this.envelope,
    required this.receivedAt,
    required this.timer,
  });

  final MessageEnvelope envelope;
  final DateTime receivedAt;
  final Timer timer;
}
