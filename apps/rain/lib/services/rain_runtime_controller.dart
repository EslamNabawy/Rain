import 'dart:async';

import 'package:peer_core/peer_core.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

class RainRuntimeController {
  RainRuntimeController({
    required this.selfIdentity,
    required this.adapter,
    required this.brain,
    required this.friendStore,
    required this.messageStore,
    required this.offlineQueueStore,
    required this.messageDeliveryService,
  });

  final RainIdentity selfIdentity;
  final SignalingAdapter adapter;
  final ProtocolBrain? brain;
  final FriendStore friendStore;
  final MessageStore messageStore;
  final OfflineQueueStore offlineQueueStore;
  final MessageDeliveryService messageDeliveryService;

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    await adapter.ensureAuthenticated();
    final now = DateTime.now().millisecondsSinceEpoch;
    await adapter.upsertIdentity(
      BackendIdentity(
        username: selfIdentity.username,
        uid: await adapter.currentUid(),
        displayName: selfIdentity.displayName,
        registeredAt: selfIdentity.createdAt,
        lastSeen: now,
        lastHeartbeat: now,
        online: true,
      ),
    );
    await adapter.setPresence(selfIdentity.username, true);

    final existingFriends = await friendStore.loadFriends();
    for (final friend in existingFriends) {
      if (friend.state == FriendState.friend) {
        await brain?.registerPeer(friend.username);
      }
    }

    _subscriptions.add(
      adapter.onFriendRequest(selfIdentity.username).listen((String from) async {
        await friendStore.upsertFriend(
          username: from,
          displayName: from,
          state: FriendState.pendingIncoming,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await brain?.registerPeer(from);
      }),
    );

    if (brain != null) {
      _subscriptions.add(
        brain!.onPeerConnected.listen((Session session) async {
          await messageDeliveryService.flushQueue(
            selfIdentity.username,
            session.peerId,
            sendChat: (String payload) async => session.send(payload),
          );
        }),
      );

      _subscriptions.add(
        brain!.onPeerMessage.listen((PeerMessage message) async {
          final peerId = message.peerId;
          final text = message.text;
          if (peerId == null || text == null) {
            return;
          }

          if (message.channelId == PeerChannels.control) {
            await messageDeliveryService.handleControlMessage(text);
            return;
          }

          if (message.channelId == PeerChannels.chat) {
            final envelope = MessageEnvelope.fromWireString(text);
            await messageDeliveryService.handleIncomingEnvelope(
              envelope,
              receivedAt: message.receivedAt,
              sendAck: (String rawAck) async {
                brain!.sendControl(peerId, rawAck);
              },
            );
            await friendStore.incrementUnread(peerId);
          }
        }),
      );
    }
  }

  Future<void> acceptFriend(String username) async {
    await adapter.writeFriendRequest(username, selfIdentity.username);
    await friendStore.markAccepted(username, displayName: username);
    await brain?.registerPeer(username);
  }

  Future<void> connectPeer(String username) async {
    if (brain == null) {
      return;
    }
    await brain!.registerPeer(username);
    await brain!.connect(username);
  }

  Future<void> dispose() async {
    await adapter.setPresence(selfIdentity.username, false);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> sendFriendRequest(String username) async {
    await adapter.writeFriendRequest(username, selfIdentity.username);
    await friendStore.upsertFriend(
      username: username,
      displayName: username,
      state: FriendState.pendingOutgoing,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await brain?.registerPeer(username);
  }

  Future<void> sendMessage(String peerId, String content) async {
    final envelope = await messageStore.composeOutgoingEnvelope(
      from: selfIdentity.username,
      to: peerId,
      content: content,
    );

    final session = brain?.getSession(peerId);
    if (brain == null || session?.state != SessionState.connected) {
      await messageDeliveryService.queueOutgoing(envelope);
      if (brain != null) {
        await brain!.registerPeer(peerId);
        await brain!.connect(peerId);
      }
      return;
    }

    await messageDeliveryService.sendEnvelope(
      envelope,
      sendChat: (String payload) async => session!.send(payload),
    );
    await friendStore.clearUnread(peerId);
  }
}
