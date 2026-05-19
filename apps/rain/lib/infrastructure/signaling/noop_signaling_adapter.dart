import 'dart:async';

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

  String _normalizedUsername(String username) {
    return username.trim().toLowerCase();
  }

  @override
  Future<String> currentUid() async => 'local-demo-user';

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
  Future<void> signOut() async {}

  @override
  Future<String> register(String username, String password) async {
    if (_identities.containsKey(username)) {
      throw Exception('Username "$username" is already taken');
    }
    final uid = 'local-${DateTime.now().millisecondsSinceEpoch}';
    _identities[username] = BackendIdentity(
      username: username,
      uid: uid,
      displayName: username,
      gender: null,
      registeredAt: DateTime.now().millisecondsSinceEpoch,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      lastHeartbeat: DateTime.now().millisecondsSinceEpoch,
      online: true,
    );
    _presence[username] = true;
    return uid;
  }

  @override
  Future<String> login(String username, String password) async {
    final identity = _identities[username];
    if (identity == null) {
      throw Exception('User "$username" not found');
    }
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
    return !_identities.containsKey(username);
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
  Stream<IceCandidatePayload> onICE(String roomId, IceRole role) =>
      const Stream<IceCandidatePayload>.empty();

  @override
  Stream<IrohAddressPayload> onIrohAddress(String roomId) =>
      const Stream<IrohAddressPayload>.empty();

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
    _identities[identity.username] = identity;
    _presence[identity.username] = identity.online;
  }

  @override
  Stream<bool> watchPresence(String username) async* {
    yield _presence[username] ?? false;
    yield* _presenceController(username).stream;
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
    IceCandidatePayload candidate,
  ) async {}

  @override
  Future<void> writeIrohAddress(
    String roomId,
    IrohAddressPayload payload,
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
