part of 'rain_runtime_controller.dart';

extension FriendRuntime on RainRuntimeController {
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
        if (!isOnline) {
          unawaited(
            _endVoiceCallForPeer(
              username,
              notifyPeer: false,
              detail: 'Peer went offline. Call ended.',
              failureReason: VoiceCallFailureReason.networkLost,
              failureDetail: 'Network connection lost. Call ended.',
            ),
          );
        }
      } catch (_) {
        // Ignore late presence callbacks during shutdown or store teardown.
      }
    });
  }

  Future<void> _trackAcceptedPeer(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    _watchPresence(normalizedUsername);
    if (_manualDisconnectedPeers.contains(normalizedUsername)) {
      return;
    }
    await _registerPeerListener(
      normalizedUsername,
      bestEffort: true,
      passive: true,
    );
  }

  Future<void> _refreshPassivePeerListeners() async {
    final friends = await _localMutations.run(friendStore.loadFriends);
    await _reconcilePassivePeerListeners(friends);
  }

  Future<void> _reconcilePassivePeerListeners(
    List<FriendRecord> friends,
  ) async {
    final selectedPeerIds = _connectionCoordinator
        .selectPassivePeerIds(
          friends,
          manualDisconnectedPeers: _manualDisconnectedPeers,
        )
        .toSet();

    for (final peerId in _passivePeerListeners.toList()) {
      if (selectedPeerIds.contains(peerId)) {
        continue;
      }
      if (_hasActiveSession(peerId)) {
        _passivePeerListeners.remove(peerId);
        continue;
      }
      await _unregisterPeerListener(peerId);
    }

    for (final peerId in selectedPeerIds) {
      await _trackAcceptedPeer(peerId);
    }

    _connectionCoordinator.updatePassiveListenerCount(
      _passivePeerListeners.length,
    );
  }

  bool _hasActiveSession(String peerId) {
    final state = brain?.getSession(peerId)?.state;
    return state == SessionState.connected ||
        state == SessionState.connecting ||
        state == SessionState.reconnecting;
  }

  Future<void> _registerPeerListener(
    String username, {
    required bool bestEffort,
    bool passive = false,
  }) async {
    final normalizedUsername = _normalizedUsername(username);
    if (brain == null ||
        _registeredPeerListeners.contains(normalizedUsername)) {
      if (passive && _registeredPeerListeners.contains(normalizedUsername)) {
        _passivePeerListeners.add(normalizedUsername);
        _connectionCoordinator.updatePassiveListenerCount(
          _passivePeerListeners.length,
        );
      }
      return;
    }
    if (passive &&
        !_connectionCoordinator.canRegisterPassivePeer(
          normalizedUsername,
          passivePeerIds: _passivePeerListeners,
        )) {
      return;
    }
    try {
      await brain!.registerPeer(
        normalizedUsername,
        incomingOfferGuard: _authorizeIncomingOffer,
      );
      _registeredPeerListeners.add(normalizedUsername);
      if (passive) {
        _passivePeerListeners.add(normalizedUsername);
        _connectionCoordinator.updatePassiveListenerCount(
          _passivePeerListeners.length,
        );
      }
    } catch (_) {
      if (!bestEffort) {
        rethrow;
      }
      // Passive answering is best effort. Manual connect still reports errors.
    }
  }

  Future<void> _unregisterPeerListener(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    _registeredPeerListeners.remove(normalizedUsername);
    _passivePeerListeners.remove(normalizedUsername);
    _connectionCoordinator.updatePassiveListenerCount(
      _passivePeerListeners.length,
    );
    await brain?.unregisterPeer(normalizedUsername);
  }

  Future<IncomingOfferDecision> _authorizeIncomingOffer(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    _connectionCoordinator.recordInboundOffer(normalizedUsername);
    if (_shutDown || !_started) {
      return const IncomingOfferDecision.deny('Rain is not running.');
    }
    if (_manualDisconnectedPeers.contains(normalizedUsername)) {
      return const IncomingOfferDecision.deny(
        'Manual disconnect is active. Press Connect to open the peer lane again.',
      );
    }
    final friend = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    return switch (friend?.state) {
      FriendState.friend => const IncomingOfferDecision.allow(),
      FriendState.blocked => const IncomingOfferDecision.deny(
        'Incoming offer rejected because this user is blocked.',
      ),
      FriendState.blockedByPeer => const IncomingOfferDecision.deny(
        'Incoming offer rejected because this user blocked you.',
      ),
      FriendState.pendingIncoming ||
      FriendState.pendingOutgoing => const IncomingOfferDecision.deny(
        'Incoming offer rejected because this user is not an accepted friend.',
      ),
      null => const IncomingOfferDecision.deny(
        'Incoming offer rejected because this user is no longer in your friends list.',
      ),
    };
  }

  Future<void> _clearFriendRequests(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await adapter.deleteFriendRequest(
      selfIdentity.username,
      normalizedUsername,
    );
    await adapter.deleteFriendRequest(
      normalizedUsername,
      selfIdentity.username,
    );
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
    var existing = await _localMutations.run(() {
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
    if (existing?.state == FriendState.blockedByPeer) {
      await _syncRelationships(onlyUsername: normalizedFrom);
      existing = await _localMutations.run(
        () => friendStore.loadFriend(normalizedFrom),
      );
    }
    if (existing?.state == FriendState.blocked) {
      await adapter.blockUser(selfIdentity.username, normalizedFrom);
      await _clearFriendRequests(normalizedFrom);
      await adapter.deleteFriendship(selfIdentity.username, normalizedFrom);
      await _stopTrackingPeer(normalizedFrom);
      return;
    }
    if (existing?.state == FriendState.blockedByPeer) {
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
    } else if (!_isBlockedState(existing?.state)) {
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
    if (existing?.state == FriendState.pendingOutgoing ||
        existing?.state == FriendState.friend) {
      await _refreshPassivePeerListeners();
    } else {
      _watchPresence(normalizedFrom);
    }
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
    final blockedByMe = await adapter.loadBlockedUsers(selfIdentity.username);
    final blockedMe = await adapter.loadUsersBlocking(selfIdentity.username);

    final incomingSet = incomingRequests.toSet();
    final outgoingSet = outgoingRequests.toSet();
    final acceptedSet = acceptedFriends.toSet();
    final blockedByMeSet = blockedByMe.toSet();
    final blockedMeSet = blockedMe.toSet();

    final crossedRequests = incomingSet
        .intersection(outgoingSet)
        .difference(blockedByMeSet)
        .difference(blockedMeSet);
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
      ...blockedByMeSet,
      ...blockedMeSet,
      ...existingByUsername.keys,
    };

    for (final username in usernames) {
      if (onlyUsername != null && username != onlyUsername) {
        continue;
      }

      final existing = existingByUsername[username];
      final locallyBlockedByMe = existing?.state == FriendState.blocked;
      final unblocking = _unblockingPeers.contains(username);
      if (locallyBlockedByMe &&
          !blockedByMeSet.contains(username) &&
          !unblocking) {
        await adapter.blockUser(selfIdentity.username, username);
        blockedByMeSet.add(username);
        incomingSet.remove(username);
        outgoingSet.remove(username);
        acceptedSet.remove(username);
      }

      if (blockedByMeSet.contains(username) ||
          (locallyBlockedByMe && !unblocking)) {
        await _clearFriendRequests(username);
        await adapter.deleteFriendship(selfIdentity.username, username);
        await _localMutations.run(() => friendStore.block(username));
        await _stopTrackingPeer(username);
        continue;
      }

      if (blockedMeSet.contains(username)) {
        await _clearFriendRequests(username);
        await adapter.deleteFriendship(selfIdentity.username, username);
        await _localMutations.run(
          () => friendStore.markBlockedByPeer(username),
        );
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
        if (existing != null && !_isBlockedState(existing.state)) {
          await _localMutations.run(() => friendStore.reject(username));
          await _stopTrackingPeer(username);
        } else if (existing?.state == FriendState.blockedByPeer) {
          await _localMutations.run(() => friendStore.reject(username));
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
    await _refreshPassivePeerListeners();
    await _reconcileConnectionRequestsWithRelationships();
  }

  Future<void> _stopTrackingPeer(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await _endVoiceCallForPeer(
      normalizedUsername,
      notifyPeer: true,
      detail: 'Call ended because the relationship changed.',
    );
    await _failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer link closed.',
    );
    await _presenceSubscriptions.remove(normalizedUsername)?.cancel();
    _manualDisconnectedPeers.remove(normalizedUsername);
    _recoverableDisconnectedPeers.remove(normalizedUsername);
    _connectionCoordinator.clearRetry(normalizedUsername);
    await brain?.disconnect(normalizedUsername);
    await _unregisterPeerListener(normalizedUsername);
  }

  bool _isBlockedState(FriendState? state) {
    return state == FriendState.blocked || state == FriendState.blockedByPeer;
  }
}
