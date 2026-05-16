import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'serialized_runtime_mutations.dart';

enum FriendRequestResult { sent, acceptedExisting }

class RainRuntimeController with WidgetsBindingObserver {
  RainRuntimeController({
    required this.selfIdentity,
    required this.adapter,
    required this.brain,
    required this.database,
    required this.friendStore,
    required this.messageStore,
    required this.offlineQueueStore,
    required this.messageDeliveryService,
    this.heartbeatInterval = const Duration(minutes: 3),
    this.friendRequestRefreshInterval = Duration.zero,
  });

  final RainIdentity selfIdentity;
  final SignalingAdapter adapter;
  final SessionManager? brain;
  final RainDatabase database;
  final FriendStore friendStore;
  final MessageStore messageStore;
  final OfflineQueueStore offlineQueueStore;
  final MessageDeliveryService messageDeliveryService;
  final Duration heartbeatInterval;
  final Duration friendRequestRefreshInterval;
  final Set<String> _manualDisconnectedPeers = <String>{};
  final Map<String, StreamSubscription<bool>> _presenceSubscriptions =
      <String, StreamSubscription<bool>>{};

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  Timer? _heartbeatTimer;
  Timer? _friendRequestRefreshTimer;
  Timer? _backgroundOfflineTimer;
  bool _started = false;
  bool _shutDown = false;
  final SerializedRuntimeMutations _localMutations =
      SerializedRuntimeMutations();

  String _normalizedUsername(String username) {
    return username.trim().toLowerCase();
  }

  RainGender? _backendGender(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final gender in RainGender.values) {
      if (gender.name == normalized) {
        return gender;
      }
    }
    return null;
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    try {
      await adapter.ensureAuthenticated();
      final currentUid = await adapter.currentUid();
      final now = DateTime.now().millisecondsSinceEpoch;
      await adapter.upsertIdentity(
        BackendIdentity(
          username: selfIdentity.username,
          uid: currentUid,
          displayName: selfIdentity.displayName,
          gender: selfIdentity.gender?.name,
          registeredAt: selfIdentity.createdAt,
          lastSeen: now,
          lastHeartbeat: now,
          online: true,
        ),
      );
      await adapter.setPresence(selfIdentity.username, true);
    } on SignalingSessionExpiredException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Could not authenticate signaling backend: $error'),
        stackTrace,
      );
    }
    await _localMutations.run(offlineQueueStore.recoverInFlightMessages);
    await _syncRelationships();

    final existingFriends = await friendStore.loadFriends();
    for (final friend in existingFriends) {
      _watchPresence(friend.username);
    }

    if (friendRequestRefreshInterval > Duration.zero) {
      _friendRequestRefreshTimer = Timer.periodic(
        friendRequestRefreshInterval,
        (_) => _refreshRelationshipsSilently(),
      );
    }

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_shutDown && _started) {
        adapter.sendHeartbeat(selfIdentity.username);
      }
    });

    _subscriptions.add(
      adapter
          .onFriendRequest(selfIdentity.username)
          .listen(
            (String from) async {
              await _processIncomingFriendRequest(from);
            },
            onError: (Object error, StackTrace stackTrace) {
              _refreshRelationshipsSilently();
            },
          ),
    );

    if (brain != null) {
      _subscriptions.add(
        brain!.onPeerConnected.listen((Session session) async {
          if (_manualDisconnectedPeers.contains(session.peerId)) {
            return;
          }
          await _localMutations.run(
            () => messageDeliveryService.flushQueue(
              selfIdentity.username,
              session.peerId,
              sendChat: (String payload) async => session.send(payload),
            ),
          );
        }),
      );

      _subscriptions.add(
        brain!.onPeerMessage.listen((SessionMessage message) async {
          final peerId = message.peerId;
          final text = message.text;
          if (peerId == null || text == null) {
            return;
          }

          if (message.channel == SessionChannel.control) {
            await _localMutations.run(
              () => messageDeliveryService.handleControlMessage(text),
            );
            return;
          }

          if (message.channel == SessionChannel.chat) {
            await _localMutations.run(() async {
              final friend = await friendStore.loadFriend(peerId);
              if (friend?.state != FriendState.friend) {
                return;
              }
              final envelope = MessageEnvelope.fromWireString(text);
              await messageDeliveryService.handleIncomingEnvelope(
                envelope,
                receivedAt: message.receivedAt,
                sendAck: (String rawAck) async {
                  brain!.sendControl(peerId, rawAck);
                },
                onStored: (_) => friendStore.incrementUnread(peerId),
              );
            });
          }
        }),
      );
    }
  }

  Future<void> acceptFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    // Prefer using an existing displayName if available to preserve
    // the user's chosen display name instead of falling back to the username.
    await _syncRelationships(onlyUsername: normalizedUsername);
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state != FriendState.pendingIncoming &&
        existing?.state != FriendState.pendingOutgoing &&
        existing?.state != FriendState.friend) {
      throw StateError(
        'There is no pending friend request from @$normalizedUsername.',
      );
    }
    final displayName = existing?.displayName ?? normalizedUsername;
    await adapter.upsertFriendship(selfIdentity.username, normalizedUsername);
    await _localMutations.run(
      () => friendStore.markAccepted(
        normalizedUsername,
        displayName: displayName,
        gender: existing?.gender,
      ),
    );
    _watchPresence(normalizedUsername);
  }

  Future<void> blockFriend(String username) async {
    await _clearFriendRequests(username);
    await adapter.deleteFriendship(selfIdentity.username, username);
    await _localMutations.run(() => friendStore.block(username));
    await _stopTrackingPeer(username);
  }

  Future<void> unblockFriend(String username) async {
    await _localMutations.run(() => friendStore.unblock(username));
  }

  Future<void> unfriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state != FriendState.friend) {
      await rejectFriend(normalizedUsername);
      return;
    }

    await adapter.deleteFriendship(selfIdentity.username, normalizedUsername);
    await _localMutations.run(() => friendStore.reject(normalizedUsername));
    await _stopTrackingPeer(normalizedUsername);
  }

  Future<void> connectPeer(
    String username, {
    bool interactive = false,
    bool waitForConnected = false,
    Duration connectionTimeout = const Duration(seconds: 15),
  }) async {
    final normalizedUsername = _normalizedUsername(username);
    if (brain == null) {
      if (interactive) {
        throw StateError('Peer connection is unavailable right now.');
      }
      return;
    }
    var friend = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (friend?.state != FriendState.friend) {
      await _syncRelationships(onlyUsername: normalizedUsername);
      friend = await _localMutations.run(
        () => friendStore.loadFriend(normalizedUsername),
      );
    }
    if (friend?.state != FriendState.friend) {
      if (interactive) {
        final message = switch (friend?.state) {
          FriendState.pendingOutgoing =>
            'Wait for @$normalizedUsername to accept your friend request before connecting.',
          FriendState.pendingIncoming =>
            'Accept @$normalizedUsername first before trying to connect.',
          FriendState.blocked =>
            'Unblock @$normalizedUsername before trying to connect.',
          FriendState.friend => null,
          null => 'Could not find @$normalizedUsername in your friends list.',
        };
        if (message != null) {
          throw StateError(message);
        }
      }
      return;
    }
    final current = brain!.getSession(normalizedUsername);
    if (current?.state == SessionState.connected) {
      return;
    }
    if (current?.state == SessionState.connecting ||
        current?.state == SessionState.reconnecting) {
      if (waitForConnected) {
        await _waitForPeerConnection(
          normalizedUsername,
          timeout: connectionTimeout,
        );
      }
      return;
    }
    final backendIdentity = await adapter.fetchIdentity(normalizedUsername);
    final isOnline = backendIdentity?.online ?? friend?.isOnline ?? false;
    await _localMutations.run(
      () => friendStore.updatePresence(normalizedUsername, isOnline),
    );
    if (!isOnline) {
      if (interactive) {
        throw StateError(
          '@$normalizedUsername is offline. Wait for them to come online before connecting.',
        );
      }
      return;
    }
    _manualDisconnectedPeers.remove(normalizedUsername);
    await brain!.registerPeer(normalizedUsername);
    await brain!.connect(normalizedUsername);
    if (waitForConnected) {
      await _waitForPeerConnection(
        normalizedUsername,
        timeout: connectionTimeout,
      );
    }
  }

  Future<void> disconnectPeer(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    _manualDisconnectedPeers.add(normalizedUsername);
    await brain?.disconnect(normalizedUsername);
    await brain?.unregisterPeer(normalizedUsername);
  }

  Future<void> setBackgroundServiceEnabled(bool enabled) async {
    _backgroundOfflineTimer?.cancel();
    if (_started && !_shutDown && !enabled) {
      await adapter.setPresence(selfIdentity.username, true);
    }
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
    return _localMutations.run(() => friendStore.clearUnread(username));
  }

  Future<void> refreshRelationships({String? onlyUsername}) {
    return _syncRelationships(
      onlyUsername: onlyUsername == null
          ? null
          : _normalizedUsername(onlyUsername),
    );
  }

  Future<void> refreshPeer(String username) {
    return refreshRelationships(onlyUsername: username);
  }

  Future<void> rejectFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state == FriendState.friend) {
      await unfriend(normalizedUsername);
      return;
    }
    if (existing?.state == FriendState.pendingIncoming) {
      await adapter.deleteFriendRequest(
        selfIdentity.username,
        normalizedUsername,
      );
    } else if (existing?.state == FriendState.pendingOutgoing) {
      await adapter.deleteFriendRequest(
        normalizedUsername,
        selfIdentity.username,
      );
    }
    await _localMutations.run(() => friendStore.reject(normalizedUsername));
    await _stopTrackingPeer(normalizedUsername);
  }

  Future<void> resendMessage(String messageId) async {
    final queued = await _localMutations.run(
      () => offlineQueueStore.loadById(messageId),
    );
    if (queued == null) {
      return;
    }
    final friend = await _localMutations.run(
      () => friendStore.loadFriend(queued.to),
    );
    if (friend?.state != FriendState.friend) {
      await _localMutations.run(() async {
        await messageStore.markMessageStatus(messageId, MessageStatus.failed);
        await offlineQueueStore.markStatus(
          messageId,
          QueuedMessageStatus.failed,
        );
      });
      return;
    }

    final envelope = queued.toEnvelope(from: selfIdentity.username);
    final session = brain?.getSession(queued.to);
    await _localMutations.run(() async {
      await messageStore.markMessageStatus(messageId, MessageStatus.queued);
      await offlineQueueStore.markStatus(messageId, QueuedMessageStatus.queued);
    });

    if (brain == null || session?.state != SessionState.connected) {
      return;
    }

    await _localMutations.run(
      () => messageDeliveryService.sendEnvelope(
        envelope,
        sendChat: (String payload) async => session!.send(payload),
      ),
    );
  }

  Future<FriendRequestResult> sendFriendRequest(String username) async {
    final targetUsername = _normalizedUsername(username);
    final selfUsername = selfIdentity.username.trim().toLowerCase();
    if (targetUsername.isEmpty || targetUsername == selfUsername) {
      throw Exception('Cannot send friend request to yourself');
    }

    await _syncRelationships(onlyUsername: targetUsername);

    final existing = await _localMutations.run(
      () => friendStore.loadFriend(targetUsername),
    );
    if (existing != null) {
      switch (existing.state) {
        case FriendState.friend:
          throw Exception('You are already friends with @$targetUsername.');
        case FriendState.pendingOutgoing:
          throw Exception(
            'A friend request to @$targetUsername is already pending.',
          );
        case FriendState.pendingIncoming:
          await acceptFriend(targetUsername);
          return FriendRequestResult.acceptedExisting;
        case FriendState.blocked:
          throw Exception('Unblock @$targetUsername before sending a request.');
      }
    }

    final targetIdentity = await adapter.fetchIdentity(targetUsername);
    if (targetIdentity == null) {
      throw Exception(
        'User "@$targetUsername" was not found. Ask them to create an account first.',
      );
    }

    await adapter.writeFriendRequest(targetUsername, selfIdentity.username);
    await _localMutations.run(
      () => friendStore.upsertFriend(
        username: targetUsername,
        displayName: targetIdentity.displayName.isEmpty
            ? targetUsername
            : targetIdentity.displayName,
        state: FriendState.pendingOutgoing,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        gender: _backendGender(targetIdentity.gender),
      ),
    );
    _watchPresence(targetUsername);
    return FriendRequestResult.sent;
  }

  Future<void> sendMessage(String peerId, String content) async {
    var friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      await _syncRelationships(onlyUsername: peerId);
      friend = await _localMutations.run(() => friendStore.loadFriend(peerId));
    }
    if (friend?.state != FriendState.friend) {
      throw StateError('Only friends can chat.');
    }
    final envelope = await _localMutations.run(
      () => messageStore.composeOutgoingEnvelope(
        from: selfIdentity.username,
        to: peerId,
        content: content,
      ),
    );

    final session = brain?.getSession(peerId);
    if (brain == null || session?.state != SessionState.connected) {
      await _localMutations.run(
        () => messageDeliveryService.queueOutgoing(envelope),
      );
      return;
    }

    await _localMutations.run(
      () => messageDeliveryService.sendEnvelope(
        envelope,
        sendChat: (String payload) async => session!.send(payload),
      ),
    );
    await _localMutations.run(() => friendStore.clearUnread(peerId));
  }

  void _watchPresence(String username) {
    if (_presenceSubscriptions.containsKey(username)) {
      return;
    }

    _presenceSubscriptions[username] = adapter.watchPresence(username).listen((
      bool isOnline,
    ) async {
      if (_shutDown) {
        return;
      }
      try {
        await _localMutations.run(
          () => friendStore.updatePresence(username, isOnline),
        );
      } catch (_) {
        // Ignore late presence callbacks during shutdown or store teardown.
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _shutDown) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        _backgroundOfflineTimer?.cancel();
        unawaited(adapter.setPresence(selfIdentity.username, true));
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _backgroundOfflineTimer?.cancel();
        _backgroundOfflineTimer = Timer(const Duration(seconds: 30), () {
          if (_started && !_shutDown) {
            unawaited(adapter.setPresence(selfIdentity.username, false));
          }
        });
        break;
    }
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
    const keepBackgroundPresence = false;

    if (markOffline && _started && !keepBackgroundPresence) {
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
          await brain!.unregisterPeer(session.peerId);
        } catch (error) {
          // Ignore errors during cleanup
        }
      }
    }

    WidgetsBinding.instance.removeObserver(this);
    _backgroundOfflineTimer?.cancel();
    _heartbeatTimer?.cancel();
    _friendRequestRefreshTimer?.cancel();

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
      await _localMutations.run(database.clearSessionData);
    }
  }

  Future<void> _clearFriendRequests(String username) async {
    await adapter.deleteFriendRequest(selfIdentity.username, username);
    await adapter.deleteFriendRequest(username, selfIdentity.username);
  }

  void _refreshRelationshipsSilently({String? onlyUsername}) {
    if (_shutDown || !_started) {
      return;
    }
    unawaited(_safeSyncRelationships(onlyUsername: onlyUsername));
  }

  Future<void> _processIncomingFriendRequest(String from) async {
    if (_shutDown) {
      return;
    }
    final normalizedFrom = _normalizedUsername(from);
    final existing = await _localMutations.run(() {
      if (_shutDown) {
        return Future<FriendRecord?>.value();
      }
      return friendStore.loadFriend(normalizedFrom);
    });
    if (_shutDown) {
      return;
    }
    BackendIdentity? backendIdentity;
    try {
      backendIdentity = await adapter.fetchIdentity(normalizedFrom);
    } catch (_) {
      backendIdentity = null;
    }
    final backendDisplayName = backendIdentity?.displayName.trim() ?? '';
    final displayName = backendDisplayName.isNotEmpty
        ? backendDisplayName
        : (existing?.displayName ?? normalizedFrom);
    final gender = _backendGender(backendIdentity?.gender) ?? existing?.gender;
    if (_shutDown) {
      return;
    }
    if (existing?.state == FriendState.blocked) {
      await _clearFriendRequests(normalizedFrom);
      await adapter.deleteFriendship(selfIdentity.username, normalizedFrom);
      await _stopTrackingPeer(normalizedFrom);
      return;
    }
    if (existing?.state == FriendState.pendingOutgoing ||
        existing?.state == FriendState.friend) {
      await adapter.upsertFriendship(selfIdentity.username, normalizedFrom);
      await _localMutations.run(() {
        if (_shutDown) {
          return Future<void>.value();
        }
        return friendStore.markAccepted(
          normalizedFrom,
          displayName: displayName,
          gender: gender,
        );
      });
    } else if (existing?.state != FriendState.blocked) {
      await _localMutations.run(() {
        if (_shutDown) {
          return Future<void>.value();
        }
        return friendStore.upsertFriend(
          username: normalizedFrom,
          displayName: displayName,
          state: FriendState.pendingIncoming,
          addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
          gender: gender,
        );
      });
    }
    _watchPresence(normalizedFrom);
  }

  Future<void> _safeSyncRelationships({String? onlyUsername}) async {
    try {
      await _syncRelationships(onlyUsername: onlyUsername);
    } catch (_) {
      // Keep the app usable when backend polling or realtime temporarily fails.
    }
  }

  Future<void> _waitForPeerConnection(
    String username, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final session = brain?.getSession(username);
      if (session?.state == SessionState.connected) {
        return;
      }
      if (session?.state == SessionState.failed) {
        final detail = session?.error ?? session?.detail;
        throw StateError(
          detail == null || detail.isEmpty
              ? 'Could not connect to @$username.'
              : 'Could not connect to @$username. $detail',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final session = brain?.getSession(username);
    if (session?.state == SessionState.connected) {
      return;
    }
    try {
      await brain?.disconnect(username);
    } catch (_) {}
    throw StateError(
      'Connection to @$username timed out. Ask them to keep Rain open; in manual mode both users must press Connect.',
    );
  }

  Future<void> _syncRelationships({String? onlyUsername}) async {
    final existingFriends = await _localMutations.run(friendStore.loadFriends);
    final existingByUsername = <String, FriendRecord>{
      for (final friend in existingFriends) friend.username: friend,
    };
    final acceptedFriends = await adapter.loadAcceptedFriends(
      selfIdentity.username,
    );
    final incomingRequests = await adapter.loadIncomingFriendRequests(
      selfIdentity.username,
    );
    final outgoingRequests = await adapter.loadOutgoingFriendRequests(
      selfIdentity.username,
    );

    final incomingSet = incomingRequests.toSet();
    final outgoingSet = outgoingRequests.toSet();
    final acceptedSet = acceptedFriends.toSet();

    final crossedRequests = incomingSet.intersection(outgoingSet);
    for (final username in crossedRequests) {
      await adapter.upsertFriendship(selfIdentity.username, username);
      acceptedSet.add(username);
      incomingSet.remove(username);
      outgoingSet.remove(username);
    }

    final usernames = <String>{
      ...acceptedSet,
      ...incomingSet,
      ...outgoingSet,
      ...existingByUsername.keys,
    };

    for (final username in usernames) {
      if (onlyUsername != null && username != onlyUsername) {
        continue;
      }

      final existing = existingByUsername[username];
      if (existing?.state == FriendState.blocked) {
        await _clearFriendRequests(username);
        await adapter.deleteFriendship(selfIdentity.username, username);
        await _stopTrackingPeer(username);
        continue;
      }

      final nextState = acceptedSet.contains(username)
          ? FriendState.friend
          : incomingSet.contains(username)
          ? FriendState.pendingIncoming
          : outgoingSet.contains(username)
          ? FriendState.pendingOutgoing
          : null;

      if (nextState == null) {
        if (existing != null && existing.state != FriendState.blocked) {
          await _localMutations.run(() => friendStore.reject(username));
          await _stopTrackingPeer(username);
        }
        continue;
      }

      final backendIdentity = await adapter.fetchIdentity(username);
      final backendDisplayName = backendIdentity?.displayName.trim() ?? '';
      final fallbackDisplayName = backendDisplayName.isNotEmpty
          ? backendDisplayName
          : username;
      final displayName =
          backendDisplayName.isNotEmpty && backendDisplayName != username
          ? backendDisplayName
          : (existing?.displayName ?? fallbackDisplayName);
      final gender =
          _backendGender(backendIdentity?.gender) ?? existing?.gender;

      if (nextState == FriendState.friend) {
        await _localMutations.run(
          () => friendStore.upsertFriend(
            username: username,
            displayName: displayName,
            state: FriendState.friend,
            addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
            gender: gender,
          ),
        );
        _watchPresence(username);
        continue;
      }

      await _localMutations.run(
        () => friendStore.upsertFriend(
          username: username,
          displayName: displayName,
          state: nextState,
          addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
          gender: gender,
        ),
      );
      _watchPresence(username);
    }
  }

  Future<void> _stopTrackingPeer(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await _presenceSubscriptions.remove(normalizedUsername)?.cancel();
    _manualDisconnectedPeers.remove(normalizedUsername);
    await brain?.disconnect(normalizedUsername);
    await brain?.unregisterPeer(normalizedUsername);
  }
}
