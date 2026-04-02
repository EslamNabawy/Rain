import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

class RainRuntimeController {
  RainRuntimeController({
    required this.selfIdentity,
    required this.adapter,
    required this.brain,
    required this.database,
    required this.friendStore,
    required this.messageStore,
    required this.offlineQueueStore,
    required this.messageDeliveryService,
  });

  final RainIdentity selfIdentity;
  final SignalingAdapter adapter;
  final ProtocolBrain? brain;
  final RainDatabase database;
  final FriendStore friendStore;
  final MessageStore messageStore;
  final OfflineQueueStore offlineQueueStore;
  final MessageDeliveryService messageDeliveryService;
  final Map<String, StreamSubscription<bool>> _presenceSubscriptions =
      <String, StreamSubscription<bool>>{};

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  Timer? _heartbeatTimer;
  bool _started = false;
  bool _shutDown = false;

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
        gender: selfIdentity.gender?.name,
        registeredAt: selfIdentity.createdAt,
        lastSeen: now,
        lastHeartbeat: now,
        online: true,
      ),
    );
    await adapter.setPresence(selfIdentity.username, true);

    final existingFriends = await friendStore.loadFriends();
    for (final friend in existingFriends) {
      _watchPresence(friend.username);
      if (friend.state == FriendState.friend) {
        await brain?.registerPeer(friend.username);
      }
    }

    _heartbeatTimer = Timer.periodic(const Duration(minutes: 3), (Timer timer) {
      if (!_shutDown && _started) {
        adapter.setPresence(selfIdentity.username, true);
      }
    });

    _subscriptions.add(
      adapter.onFriendRequest(selfIdentity.username).listen((
        String from,
      ) async {
        final existing = await friendStore.loadFriend(from);
        print(
          '[RainRuntime] Received friend request from: $from, existingState=${existing?.state}',
        );
        if (existing?.state == FriendState.pendingOutgoing ||
            existing?.state == FriendState.friend) {
          await friendStore.markAccepted(
            from,
            displayName: existing?.displayName ?? from,
          );
        } else if (existing?.state != FriendState.blocked) {
          await friendStore.upsertFriend(
            username: from,
            displayName: existing?.displayName ?? from,
            state: FriendState.pendingIncoming,
            addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
          );
        }
        _watchPresence(from);
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
    // Prefer using an existing displayName if available to preserve
    // the user's chosen display name instead of falling back to the username.
    final existing = await friendStore.loadFriend(username);
    final displayName = existing?.displayName ?? username;
    await friendStore.markAccepted(username, displayName: displayName);
    _watchPresence(username);
    await brain?.registerPeer(username);
  }

  Future<void> blockFriend(String username) async {
    await friendStore.block(username);
    await brain?.disconnect(username);
  }

  Future<void> unblockFriend(String username) async {
    await friendStore.unblock(username);
    await brain?.registerPeer(username);
  }

  Future<void> connectPeer(String username) async {
    if (brain == null) {
      return;
    }
    final current = brain!.getSession(username);
    if (current?.state == SessionState.connected ||
        current?.state == SessionState.connecting ||
        current?.state == SessionState.reconnecting) {
      return;
    }
    await brain!.registerPeer(username);
    await brain!.connect(username);
  }

  Future<void> dispose() async {
    await _shutdown(
      markOffline: true,
      signOut: false,
      clearLocalSession: false,
    );
  }

  Future<void> logOut() async {
    await _shutdown(markOffline: true, signOut: true, clearLocalSession: true);
  }

  Future<void> markConversationRead(String username) {
    return friendStore.clearUnread(username);
  }

  Future<void> rejectFriend(String username) {
    return friendStore.reject(username);
  }

  Future<void> resendMessage(String messageId) async {
    final queued = await offlineQueueStore.loadById(messageId);
    if (queued == null) {
      return;
    }

    final envelope = queued.toEnvelope(from: selfIdentity.username);
    final session = brain?.getSession(queued.to);
    await messageStore.markMessageStatus(messageId, MessageStatus.queued);
    await offlineQueueStore.markStatus(messageId, QueuedMessageStatus.queued);

    if (brain == null || session?.state != SessionState.connected) {
      await connectPeer(queued.to);
      return;
    }

    await messageDeliveryService.sendEnvelope(
      envelope,
      sendChat: (String payload) async => session!.send(payload),
    );
  }

  Future<void> sendFriendRequest(String username) async {
    if (username == selfIdentity.username) {
      throw Exception('Cannot send friend request to yourself');
    }

    final existing = await friendStore.loadFriend(username);
    if (existing != null &&
        (existing.state == FriendState.friend ||
            existing.state == FriendState.pendingOutgoing ||
            existing.state == FriendState.pendingIncoming)) {
      // If a relationship already exists, fail fast with a clear message
      // to avoid confusing the user.
      throw Exception(
        'Friend request already exists or you are already friends',
      );
    }

    // Debug: log intent to send
    print('[RainRuntime] Sending friend request to: $username');
    await adapter.writeFriendRequest(username, selfIdentity.username);
    await friendStore.upsertFriend(
      username: username,
      displayName: username,
      state: FriendState.pendingOutgoing,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _watchPresence(username);
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

  void _watchPresence(String username) {
    if (_presenceSubscriptions.containsKey(username)) {
      return;
    }

    _presenceSubscriptions[username] = adapter.watchPresence(username).listen((
      bool isOnline,
    ) async {
      await friendStore.updatePresence(username, isOnline);
      final friend = await friendStore.loadFriend(username);
      if (isOnline && friend?.state == FriendState.friend) {
        await connectPeer(username);
      }
    });
  }

  Future<void> _shutdown({
    required bool markOffline,
    required bool signOut,
    required bool clearLocalSession,
  }) async {
    if (_shutDown) {
      return;
    }
    _shutDown = true;

    if (markOffline && _started) {
      try {
        await adapter.setPresence(selfIdentity.username, false);
      } catch (error) {
        // Ignore permission errors during logout
      }
    }

    if (brain != null) {
      for (final session in brain!.getSessions()) {
        try {
          await brain!.disconnect(session.peerId);
        } catch (error) {
          // Ignore errors during cleanup
        }
      }
    }

    _heartbeatTimer?.cancel();

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    for (final subscription in _presenceSubscriptions.values) {
      await subscription.cancel();
    }
    _presenceSubscriptions.clear();

    if (signOut) {
      await adapter.signOut();
    }

    if (clearLocalSession) {
      await database.clearSessionData();
    }
  }
}
