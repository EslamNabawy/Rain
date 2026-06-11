/// # noop_signaling_adapter
///
/// In-memory no-op signaling adapter for local development and testing.
/// Implements the full SignalingAdapter interface with local state for
/// identities, friendships, blocks, and friend requests without any backend.
///
/// **Key types:** NoopSignalingAdapter
///
/// **Depends on:** SignalingAdapter interface, protocol_brain
import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';

class NoopSignalingAdapter implements SignalingAdapter {
  final Map<String, BackendIdentity> _identities = <String, BackendIdentity>{};
  final Map<String, bool> _presence = <String, bool>{};
  final Set<String> _friendRequests = <String>{};
  final Set<String> _friendships = <String>{};
  final Set<String> _blocks = <String>{};
  final Map<String, StreamController<bool>> _presenceControllers =
      <String, StreamController<bool>>{};
  final Map<String, StreamController<String>> _friendRequestControllers =
      <String, StreamController<String>>{};
  final Map<String, StreamController<String>> _relationshipControllers =
      <String, StreamController<String>>{};
  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(
    36,
  );
  final int _sessionStartedAt = DateTime.now().millisecondsSinceEpoch;
  String? _currentUsername;

  String _normalizedUsername(String username) {
    return username.trim().toLowerCase();
  }

  @override
  Future<String> currentUid() async {
    final currentUsername = _currentUsername;
    if (currentUsername == null) {
      return 'local-demo-user';
    }
    return _identities[currentUsername]?.uid ?? 'local-demo-user';
  }

  @override
  Future<void> deleteRoom(String roomId) async {}

  @override
  Future<void> dispose() async {
    for (final controller in _presenceControllers.values) {
      await controller.close();
    }
    for (final controller in _friendRequestControllers.values) {
      await controller.close();
    }
    for (final controller in _relationshipControllers.values) {
      await controller.close();
    }
  }

  @override
  Future<void> ensureAuthenticated() async {}

  @override
  Future<void> ensureSignedInAs(String username) async {
    await ensureAuthenticated();
  }

  @override
  Future<void> signOut() async {
    _currentUsername = null;
  }

  @override
  Future<void> reauthenticate(String username, String password) async {
    final normalizedUsername = _normalizedUsername(username);
    if (_normalizedUsername(_currentUsername ?? '') != normalizedUsername ||
        !_identities.containsKey(normalizedUsername)) {
      throw const SignalingSessionExpiredException(
        'Sign in again before deleting this account.',
      );
    }
  }

  @override
  Future<void> deleteAccount(
    String username, {
    Future<void> Function()? beforeAuthDeletion,
  }) async {
    final normalizedUsername = _normalizedUsername(username);
    await ensureSignedInAs(normalizedUsername);
    final friends = await loadAcceptedFriends(normalizedUsername);
    final incomingRequests = await loadIncomingFriendRequests(
      normalizedUsername,
    );
    final outgoingRequests = await loadOutgoingFriendRequests(
      normalizedUsername,
    );
    final blocked = await loadBlockedUsers(normalizedUsername);
    for (final friend in friends) {
      await deleteFriendship(normalizedUsername, friend);
    }
    for (final from in incomingRequests) {
      await deleteFriendRequest(normalizedUsername, from);
    }
    for (final to in outgoingRequests) {
      await deleteFriendRequest(to, normalizedUsername);
    }
    for (final blockedUser in blocked) {
      await unblockUser(normalizedUsername, blockedUser);
    }
    await beforeAuthDeletion?.call();
    _presence.remove(normalizedUsername);
    _identities.remove(normalizedUsername);
    _currentUsername = null;
    _presenceController(normalizedUsername).add(false);
  }

  @override
  Future<String> register(String username, String password) async {
    final normalizedUsername = _normalizedUsername(username);
    if (_identities.containsKey(normalizedUsername)) {
      throw Exception('Username "$normalizedUsername" is already taken');
    }
    final uid = 'local-${DateTime.now().millisecondsSinceEpoch}';
    _identities[normalizedUsername] = BackendIdentity(
      username: normalizedUsername,
      uid: uid,
      displayName: normalizedUsername,
      gender: null,
      registeredAt: DateTime.now().millisecondsSinceEpoch,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      lastHeartbeat: DateTime.now().millisecondsSinceEpoch,
      online: true,
      presenceSessionId: _sessionId,
      presenceStartedAt: _sessionStartedAt,
      presenceState: 'online',
    );
    _presence[normalizedUsername] = true;
    _currentUsername = normalizedUsername;
    return uid;
  }

  @override
  Future<String> login(String username, String password) async {
    final normalizedUsername = _normalizedUsername(username);
    final identity = _identities[normalizedUsername];
    if (identity == null) {
      throw Exception('User "$normalizedUsername" not found');
    }
    _currentUsername = normalizedUsername;
    return identity.uid;
  }

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    final identity = _identities[normalizedUsername];
    if (identity == null) {
      return null;
    }
    final isOnline = _presence[normalizedUsername] ?? identity.online;
    return BackendIdentity(
      username: identity.username,
      uid: identity.uid,
      displayName: identity.displayName,
      gender: identity.gender,
      registeredAt: identity.registeredAt,
      lastSeen: identity.lastSeen,
      lastHeartbeat: identity.lastHeartbeat,
      online: isOnline,
      presenceSessionId: identity.presenceSessionId,
      presenceStartedAt: identity.presenceStartedAt,
      presenceState: isOnline ? 'online' : 'offline',
    );
  }

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async {
    if (query.length < 2) {
      return [];
    }
    final queryLower = query.toLowerCase();
    return _identities.values
        .where(
          (identity) => identity.username.toLowerCase().contains(queryLower),
        )
        .toList();
  }

  @override
  Future<void> addToUserSearch(String username) async {}

  @override
  Future<void> deleteFriendRequest(String to, String from) async {
    final normalizedTo = _normalizedUsername(to);
    final normalizedFrom = _normalizedUsername(from);
    final removed = _friendRequests.remove('$normalizedFrom->$normalizedTo');
    if (removed) {
      _emitRelationshipChange(normalizedTo, normalizedFrom);
      _emitRelationshipChange(normalizedFrom, normalizedTo);
    }
  }

  @override
  Future<void> deleteFriendship(String firstUser, String secondUser) async {
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    final removed = _friendships.remove(
      _friendshipKey(normalizedFirstUser, normalizedSecondUser),
    );
    await deleteFriendRequest(normalizedFirstUser, normalizedSecondUser);
    await deleteFriendRequest(normalizedSecondUser, normalizedFirstUser);
    if (removed) {
      _emitRelationshipChange(normalizedFirstUser, normalizedSecondUser);
      _emitRelationshipChange(normalizedSecondUser, normalizedFirstUser);
    }
  }

  @override
  Future<List<String>> loadAcceptedFriends(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    return _friendships
        .map((String key) => key.split('::'))
        .where(
          (List<String> pair) =>
              pair.length == 2 && pair.contains(normalizedUsername),
        )
        .map(
          (List<String> pair) =>
              pair.first == normalizedUsername ? pair.last : pair.first,
        )
        .toList(growable: false);
  }

  @override
  Future<List<String>> loadBlockedUsers(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    return _blocks
        .map((String key) => key.split('->'))
        .where(
          (List<String> pair) =>
              pair.length == 2 && pair[0] == normalizedUsername,
        )
        .map((List<String> pair) => pair[1])
        .toList(growable: false);
  }

  @override
  Future<List<String>> loadUsersBlocking(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    return _blocks
        .map((String key) => key.split('->'))
        .where(
          (List<String> pair) =>
              pair.length == 2 && pair[1] == normalizedUsername,
        )
        .map((List<String> pair) => pair[0])
        .toList(growable: false);
  }

  @override
  Future<List<String>> loadIncomingFriendRequests(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    return _friendRequests
        .map((String key) => key.split('->'))
        .where(
          (List<String> pair) =>
              pair.length == 2 && pair[1] == normalizedUsername,
        )
        .map((List<String> pair) => pair[0])
        .toList(growable: false);
  }

  @override
  Future<List<String>> loadOutgoingFriendRequests(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    return _friendRequests
        .map((String key) => key.split('->'))
        .where(
          (List<String> pair) =>
              pair.length == 2 && pair[0] == normalizedUsername,
        )
        .map((List<String> pair) => pair[1])
        .toList(growable: false);
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    return !_identities.containsKey(_normalizedUsername(username));
  }

  @override
  Stream<SDPPayload> onAnswer(String roomId) =>
      const Stream<SDPPayload>.empty();

  @override
  Stream<String> onFriendRequest(String username) =>
      _friendRequestController(username).stream;

  @override
  Stream<String> onRelationshipChanged(String username) =>
      _relationshipController(username).stream;

  @override
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role) =>
      const Stream<RTCIceCandidate>.empty();

  @override
  Stream<SDPPayload> onOffer(String roomId) => const Stream<SDPPayload>.empty();

  @override
  Future<void> setPresence(String username, bool online) async {
    final normalizedUsername = _normalizedUsername(username);
    _presence[normalizedUsername] = online;
    final existing = _identities[normalizedUsername];
    if (existing != null) {
      _identities[normalizedUsername] = BackendIdentity(
        username: existing.username,
        uid: existing.uid,
        displayName: existing.displayName,
        gender: existing.gender,
        registeredAt: existing.registeredAt,
        lastSeen: existing.lastSeen,
        lastHeartbeat: DateTime.now().millisecondsSinceEpoch,
        online: online,
        presenceSessionId: _sessionId,
        presenceStartedAt: _sessionStartedAt,
        presenceState: online ? 'online' : 'offline',
      );
    }
    _presenceController(normalizedUsername).add(online);
  }

  @override
  Future<void> sendHeartbeat(String username) async {
    await setPresence(username, true);
  }

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {
    final normalizedUsername = _normalizedUsername(identity.username);
    _identities[normalizedUsername] = BackendIdentity(
      username: normalizedUsername,
      uid: identity.uid,
      displayName: identity.displayName,
      gender: identity.gender,
      registeredAt: identity.registeredAt,
      lastSeen: identity.lastSeen,
      lastHeartbeat: identity.lastHeartbeat,
      online: identity.online,
      presenceSessionId: identity.presenceSessionId,
      presenceStartedAt: identity.presenceStartedAt,
      presenceState: identity.presenceState,
    );
    _presence[normalizedUsername] = identity.online;
    _currentUsername ??= normalizedUsername;
  }

  @override
  Stream<bool> watchPresence(String username) async* {
    final normalizedUsername = _normalizedUsername(username);
    yield _presence[normalizedUsername] ?? false;
    yield* _presenceController(normalizedUsername).stream;
  }

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) async {}

  @override
  Future<void> writeFriendRequest(String to, String from) async {
    final normalizedTo = _normalizedUsername(to);
    final normalizedFrom = _normalizedUsername(from);
    if (normalizedTo == normalizedFrom) {
      throw Exception('Cannot send friend request to yourself');
    }
    final added = _friendRequests.add('$normalizedFrom->$normalizedTo');
    if (added) {
      _friendRequestController(normalizedTo).add(normalizedFrom);
      _emitRelationshipChange(normalizedTo, normalizedFrom);
      _emitRelationshipChange(normalizedFrom, normalizedTo);
    }
  }

  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) async {
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    final added = _friendships.add(
      _friendshipKey(normalizedFirstUser, normalizedSecondUser),
    );
    await deleteFriendRequest(normalizedFirstUser, normalizedSecondUser);
    await deleteFriendRequest(normalizedSecondUser, normalizedFirstUser);
    if (added) {
      _emitRelationshipChange(normalizedFirstUser, normalizedSecondUser);
      _emitRelationshipChange(normalizedSecondUser, normalizedFirstUser);
    }
  }

  @override
  Future<void> blockUser(String blocker, String blocked) async {
    final normalizedBlocker = _normalizedUsername(blocker);
    final normalizedBlocked = _normalizedUsername(blocked);
    if (normalizedBlocker == normalizedBlocked) {
      throw Exception('Cannot block yourself');
    }
    final added = _blocks.add('$normalizedBlocker->$normalizedBlocked');
    await deleteFriendship(normalizedBlocker, normalizedBlocked);
    await deleteFriendRequest(normalizedBlocker, normalizedBlocked);
    await deleteFriendRequest(normalizedBlocked, normalizedBlocker);
    if (added) {
      _emitRelationshipChange(normalizedBlocker, normalizedBlocked);
      _emitRelationshipChange(normalizedBlocked, normalizedBlocker);
    }
  }

  @override
  Future<void> unblockUser(String blocker, String blocked) async {
    final normalizedBlocker = _normalizedUsername(blocker);
    final normalizedBlocked = _normalizedUsername(blocked);
    final removed = _blocks.remove('$normalizedBlocker->$normalizedBlocked');
    if (removed) {
      _emitRelationshipChange(normalizedBlocker, normalizedBlocked);
      _emitRelationshipChange(normalizedBlocked, normalizedBlocker);
    }
  }

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    RTCIceCandidate candidate,
  ) async {}

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {}

  StreamController<String> _friendRequestController(String username) {
    return _friendRequestControllers.putIfAbsent(
      username,
      () => StreamController<String>.broadcast(sync: true),
    );
  }

  StreamController<String> _relationshipController(String username) {
    return _relationshipControllers.putIfAbsent(
      _normalizedUsername(username),
      () => StreamController<String>.broadcast(sync: true),
    );
  }

  StreamController<bool> _presenceController(String username) {
    return _presenceControllers.putIfAbsent(
      username,
      () => StreamController<bool>.broadcast(sync: true),
    );
  }

  String _friendshipKey(String firstUser, String secondUser) {
    final users = <String>[
      _normalizedUsername(firstUser),
      _normalizedUsername(secondUser),
    ]..sort();
    return '${users[0]}::${users[1]}';
  }

  void _emitRelationshipChange(String username, String peerUsername) {
    _relationshipController(username).add(_normalizedUsername(peerUsername));
  }
}
