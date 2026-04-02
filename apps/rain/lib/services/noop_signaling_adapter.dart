import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';

class NoopSignalingAdapter implements SignalingAdapter {
  final Map<String, BackendIdentity> _identities = <String, BackendIdentity>{};
  final Map<String, bool> _presence = <String, bool>{};
  final Set<String> _friendRequests = <String>{};
  final Map<String, StreamController<bool>> _presenceControllers =
      <String, StreamController<bool>>{};
  final Map<String, StreamController<String>> _friendRequestControllers =
      <String, StreamController<String>>{};

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
    return _identities[username];
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
    _friendRequests.remove('$from->$to');
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
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role) =>
      const Stream<RTCIceCandidate>.empty();

  @override
  Stream<SDPPayload> onOffer(String roomId) => const Stream<SDPPayload>.empty();

  @override
  Future<void> setPresence(String username, bool online) async {
    _presence[username] = online;
    _presenceController(username).add(online);
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
    _friendRequests.add('$from->$to');
    _friendRequestController(to).add(from);
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
      () => StreamController<String>.broadcast(),
    );
  }

  StreamController<bool> _presenceController(String username) {
    return _presenceControllers.putIfAbsent(
      username,
      () => StreamController<bool>.broadcast(),
    );
  }
}
