/// # friend_runtime.dart
///
/// [FriendRuntime] extension on [RainRuntimeController] watches peer presence
/// streams, persists presence to the local friend store, triggers automatic
/// reconnection for accepted friends when they come online, and handles
/// presence-expired cleanup (ending active calls, disconnecting sessions).
///
/// **Key types:** (extension methods on RainRuntimeController)
///
/// **Part of:** friend_runtime.dart (extension)
///
/// **Depends on:** protocol_brain, rain_core, voice call state

import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'connection_attempt_coordinator.dart';
import 'rain_runtime_controller.dart';
import 'voice_call_state.dart';

extension FriendRuntime on RainRuntimeController {
  void watchPresence(String username) {
    if (presenceSubscriptions.containsKey(username)) {
      return;
    }

    presenceSubscriptions[username] = adapter.watchPresence(username).listen((
      bool isOnline,
    ) async {
      if (runtimeShutDown) {
        return;
      }
      try {
        cachePresenceStreamValue(username, isOnline);
        await localMutations.run(
          () => friendStore.updatePresence(username, isOnline),
        );
        if (isOnline) {
          final friend = await localMutations.run(
            () => friendStore.loadFriend(username),
          );
          if (friend?.state == FriendState.friend &&
              !mutableManualDisconnectedPeers.contains(username)) {
            unawaited(_trackAcceptedPeer(username));
          }
        } else {
          unawaited(_handlePeerPresenceExpired(username));
        }
      } catch (_) {
        // Ignore late presence callbacks during shutdown or store teardown.
      }
    });
  }

  Future<void> _handlePeerPresenceExpired(String username) async {
    final peerId = normalizeUsername(username);
    recordRuntimeEvent(
      category: 'presence',
      name: 'presence_session_expired',
      severity: 'warning',
      message: 'Peer presence expired.',
      context: <String, Object?>{'peerId': peerId},
    );
    recoverableDisconnectedPeers.remove(peerId);
    final call = voiceCallState;
    final callMatchesPeer = call.peerId == peerId;
    final isEstablishedCall =
        call.phase == VoiceCallPhase.active ||
        (call.phase == VoiceCallPhase.ending && call.startedAt != null);
    if (callMatchesPeer && call.hasCall && !isEstablishedCall) {
      await endVoiceCallForPeer(
        peerId,
        notifyPeer: false,
        detail: 'Call could not connect. Try again.',
        failureReason: VoiceCallFailureReason.mediaConnectionFailed,
        failureDetail: 'Call could not connect. Try again.',
      );
    } else {
      await endVoiceCallForPeer(
        peerId,
        notifyPeer: false,
        detail: 'Peer closed Rain. Connection ended.',
        failureReason: VoiceCallFailureReason.networkLost,
        failureDetail: 'Peer closed Rain. Connection ended.',
      );
    }
    unawaited(
      failActiveTransfersForPeer(
        peerId,
        'Peer closed Rain. Transfer canceled.',
      ),
    );
    try {
      await disconnectBrainPeer(peerId, PeerDisconnectIntent.presenceExpired);
      await unregisterPeerListener(peerId);
    } catch (_) {
      // Presence expiry cleanup is best effort; the peer is already stale.
    }
  }

  Future<void> _trackAcceptedPeer(String username) async {
    final normalizedUsername = normalizeUsername(username);
    watchPresence(normalizedUsername);
    if (mutableManualDisconnectedPeers.contains(normalizedUsername)) {
      return;
    }
    await registerPeerListener(
      normalizedUsername,
      bestEffort: true,
      passive: true,
    );
  }

  Future<void> refreshPassivePeerListeners() async {
    final friends = await localMutations.run(friendStore.loadFriends);
    await reconcilePassivePeerListeners(friends);
  }

  Future<void> reconcilePassivePeerListeners(List<FriendRecord> friends) async {
    final selectedPeerIds = connectionCoordinator
        .selectPassivePeerIds(
          friends,
          manualDisconnectedPeers: mutableManualDisconnectedPeers,
        )
        .toSet();

    for (final peerId in passivePeerListeners.toList()) {
      if (selectedPeerIds.contains(peerId)) {
        continue;
      }
      if (_hasActiveSession(peerId)) {
        passivePeerListeners.remove(peerId);
        continue;
      }
      await unregisterPeerListener(peerId);
    }

    for (final peerId in selectedPeerIds) {
      await _trackAcceptedPeer(peerId);
    }

    connectionCoordinator.updatePassiveListenerCount(
      passivePeerListeners.length,
    );
  }

  bool _hasActiveSession(String peerId) {
    final state = brain?.getSession(peerId)?.state;
    return state == SessionState.connected ||
        state == SessionState.connecting ||
        state == SessionState.reconnecting;
  }

  Future<void> registerPeerListener(
    String username, {
    required bool bestEffort,
    bool passive = false,
  }) async {
    final normalizedUsername = normalizeUsername(username);
    if (brain == null || registeredPeerListeners.contains(normalizedUsername)) {
      if (passive && registeredPeerListeners.contains(normalizedUsername)) {
        passivePeerListeners.add(normalizedUsername);
        connectionCoordinator.updatePassiveListenerCount(
          passivePeerListeners.length,
        );
      }
      return;
    }
    if (passive &&
        !connectionCoordinator.canRegisterPassivePeer(
          normalizedUsername,
          passivePeerIds: passivePeerListeners,
        )) {
      return;
    }
    try {
      await brain!.registerPeer(
        normalizedUsername,
        incomingOfferGuard: _authorizeIncomingOffer,
      );
      registeredPeerListeners.add(normalizedUsername);
      if (passive) {
        passivePeerListeners.add(normalizedUsername);
        connectionCoordinator.updatePassiveListenerCount(
          passivePeerListeners.length,
        );
      }
    } catch (_) {
      if (!bestEffort) {
        rethrow;
      }
      // Passive answering is best effort. Manual connect still reports errors.
    }
  }

  Future<void> unregisterPeerListener(String username) async {
    final normalizedUsername = normalizeUsername(username);
    registeredPeerListeners.remove(normalizedUsername);
    passivePeerListeners.remove(normalizedUsername);
    connectionCoordinator.updatePassiveListenerCount(
      passivePeerListeners.length,
    );
    await brain?.unregisterPeer(normalizedUsername);
  }

  Future<IncomingOfferDecision> _authorizeIncomingOffer(String username) async {
    final normalizedUsername = normalizeUsername(username);
    connectionCoordinator.recordInboundOffer(normalizedUsername);
    if (runtimeShutDown || !runtimeStarted) {
      return const IncomingOfferDecision.deny('Rain is not running.');
    }
    if (mutableManualDisconnectedPeers.contains(normalizedUsername)) {
      return const IncomingOfferDecision.deny(
        'Manual disconnect is active. Press Connect to open the peer lane again.',
      );
    }
    final friend = await localMutations.run(
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

  Future<void> clearFriendRequests(String username) async {
    final normalizedUsername = normalizeUsername(username);
    await adapter.deleteFriendRequest(
      selfIdentity.username,
      normalizedUsername,
    );
    await adapter.deleteFriendRequest(
      normalizedUsername,
      selfIdentity.username,
    );
  }

  void refreshRelationshipsSilently({String? onlyUsername}) {
    if (runtimeShutDown || !runtimeStarted) {
      return;
    }
    unawaited(safeSyncRelationships(onlyUsername: onlyUsername));
  }

  Future<void> processIncomingFriendRequest(String from) async {
    if (runtimeShutDown) {
      return;
    }
    final normalizedFrom = normalizeUsername(from);
    var existing = await localMutations.run(() {
      if (runtimeShutDown) {
        return Future<FriendRecord?>.value();
      }
      return friendStore.loadFriend(normalizedFrom);
    });
    if (runtimeShutDown) {
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
    final gender = backendGender(backendIdentity?.gender) ?? existing?.gender;
    if (runtimeShutDown) {
      return;
    }
    if (existing?.state == FriendState.blockedByPeer) {
      await syncRelationships(onlyUsername: normalizedFrom);
      existing = await localMutations.run(
        () => friendStore.loadFriend(normalizedFrom),
      );
    }
    if (existing?.state == FriendState.blocked) {
      await adapter.blockUser(selfIdentity.username, normalizedFrom);
      await clearFriendRequests(normalizedFrom);
      await adapter.deleteFriendship(selfIdentity.username, normalizedFrom);
      await stopTrackingPeer(normalizedFrom);
      return;
    }
    if (existing?.state == FriendState.blockedByPeer) {
      await clearFriendRequests(normalizedFrom);
      await adapter.deleteFriendship(selfIdentity.username, normalizedFrom);
      await stopTrackingPeer(normalizedFrom);
      return;
    }
    if (existing?.state == FriendState.pendingOutgoing ||
        existing?.state == FriendState.friend) {
      await adapter.upsertFriendship(selfIdentity.username, normalizedFrom);
      await localMutations.run(() {
        if (runtimeShutDown) {
          return Future<void>.value();
        }
        return friendStore.markAccepted(
          normalizedFrom,
          displayName: displayName,
          gender: gender,
        );
      });
      await _seedFriendPresenceFromBackend(normalizedFrom, backendIdentity);
    } else if (!isBlockedState(existing?.state)) {
      await localMutations.run(() {
        if (runtimeShutDown) {
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
      await _seedFriendPresenceFromBackend(normalizedFrom, backendIdentity);
    }
    if (existing?.state == FriendState.pendingOutgoing ||
        existing?.state == FriendState.friend) {
      await refreshPassivePeerListeners();
    } else {
      watchPresence(normalizedFrom);
    }
  }

  Future<void> safeSyncRelationships({String? onlyUsername}) async {
    try {
      await syncRelationships(onlyUsername: onlyUsername);
    } catch (_) {
      // Keep the app usable when backend polling or realtime temporarily fails.
    }
  }

  Future<void> waitForPeerConnection(
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

  Future<void> syncRelationships({String? onlyUsername}) async {
    final existingFriends = await localMutations.run(friendStore.loadFriends);
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
      final unblocking = unblockingPeers.contains(username);
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
        await clearFriendRequests(username);
        await adapter.deleteFriendship(selfIdentity.username, username);
        await localMutations.run(() => friendStore.block(username));
        await stopTrackingPeer(username);
        continue;
      }

      if (blockedMeSet.contains(username)) {
        await clearFriendRequests(username);
        await adapter.deleteFriendship(selfIdentity.username, username);
        await localMutations.run(() => friendStore.markBlockedByPeer(username));
        await stopTrackingPeer(username);
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
        if (existing != null && !isBlockedState(existing.state)) {
          await localMutations.run(() => friendStore.reject(username));
          await stopTrackingPeer(username);
        } else if (existing?.state == FriendState.blockedByPeer) {
          await localMutations.run(() => friendStore.reject(username));
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
      final gender = backendGender(backendIdentity?.gender) ?? existing?.gender;

      if (nextState == FriendState.friend) {
        await localMutations.run(
          () => friendStore.upsertFriend(
            username: username,
            displayName: displayName,
            state: FriendState.friend,
            addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
            gender: gender,
          ),
        );
        await _seedFriendPresenceFromBackend(username, backendIdentity);
        watchPresence(username);
        continue;
      }

      await localMutations.run(
        () => friendStore.upsertFriend(
          username: username,
          displayName: displayName,
          state: nextState,
          addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
          gender: gender,
        ),
      );
      await _seedFriendPresenceFromBackend(username, backendIdentity);
      watchPresence(username);
    }
    await refreshPassivePeerListeners();
    await reconcileConnectionRequestsWithRelationships();
  }

  Future<void> _seedFriendPresenceFromBackend(
    String username,
    BackendIdentity? backendIdentity,
  ) async {
    if (runtimeShutDown || backendIdentity == null) {
      return;
    }
    final presence = resolveBackendPresence(backendIdentity);
    cacheResolvedPeerPresence(username, presence);
    if (presence.staleRawOnline) {
      recordRuntimeEvent(
        category: 'presence',
        name: 'backend_presence_stale_resolved_offline',
        severity: 'warning',
        message: 'Backend presence heartbeat is stale.',
        context: <String, Object?>{
          'peerId': normalizeUsername(username),
          ...presence.toDiagnostics(),
        },
      );
    }
    await localMutations.run(() {
      if (runtimeShutDown) {
        return Future<void>.value();
      }
      return friendStore.updatePresence(username, presence.online);
    });
  }

  Future<void> stopTrackingPeer(String username) async {
    final normalizedUsername = normalizeUsername(username);
    await endVoiceCallForPeer(
      normalizedUsername,
      notifyPeer: true,
      detail: 'Call ended because the relationship changed.',
    );
    await failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer link closed.',
    );
    await presenceSubscriptions.remove(normalizedUsername)?.cancel();
    if (peerPresenceSnapshotCache.remove(normalizedUsername) != null) {
      notifyPeerConnectivityChanged();
    }
    if (mutableManualDisconnectedPeers.remove(normalizedUsername)) {
      notifyPeerConnectivityChanged();
    }
    recoverableDisconnectedPeers.remove(normalizedUsername);
    connectionCoordinator.clearRetry(normalizedUsername);
    await brain?.disconnect(normalizedUsername);
    await unregisterPeerListener(normalizedUsername);
  }

  bool isBlockedState(FriendState? state) {
    return state == FriendState.blocked || state == FriendState.blockedByPeer;
  }
}
