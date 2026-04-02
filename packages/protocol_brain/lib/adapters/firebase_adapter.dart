import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling_adapter.dart';

class FirebaseSignalingAdapter implements SignalingAdapter {
  FirebaseSignalingAdapter({FirebaseAuth? auth, FirebaseDatabase? database})
    : _auth = auth ?? FirebaseAuth.instance,
      _database = database ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  DatabaseReference get _root => _database.ref();

  static const int _presenceTimeoutMs = 7 * 60 * 1000;
  static const int _searchLimit = 10;

  final Map<String, BackendIdentity> _identityCache =
      <String, BackendIdentity>{};
  int _cacheTimestamp = 0;
  static const int _cacheMaxAgeMs = 30 * 1000;

  bool _isCacheValid() {
    return DateTime.now().millisecondsSinceEpoch - _cacheTimestamp <
        _cacheMaxAgeMs;
  }

  @override
  Future<void> deleteRoom(String roomId) async {
    await ensureAuthenticated();
    await _root.child('rooms/$roomId').remove();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> ensureAuthenticated() async {
    if (_auth.currentUser != null) {
      return;
    }
    await _auth.signInAnonymously();
  }

  @override
  Future<String> currentUid() async {
    await ensureAuthenticated();
    return _auth.currentUser?.uid ?? '';
  }

  @override
  Future<void> signOut() {
    return _auth.signOut();
  }

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async {
    await ensureAuthenticated();
    final snapshot = await _root.child('users/$username').get();
    if (!snapshot.exists || snapshot.value is! Map<Object?, Object?>) {
      return null;
    }
    final value = snapshot.value! as Map<Object?, Object?>;
    final identity = BackendIdentity(
      username: username,
      uid: value['uid'] as String? ?? '',
      displayName: value['displayName'] as String? ?? username,
      registeredAt: (value['registeredAt'] as num?)?.toInt() ?? 0,
      lastSeen: (value['lastSeen'] as num?)?.toInt() ?? 0,
      lastHeartbeat: (value['lastHeartbeat'] as num?)?.toInt() ?? 0,
      online: value['online'] as bool? ?? false,
    );
    _identityCache[username] = identity;
    return identity;
  }

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async {
    if (query.length < 2) {
      return [];
    }

    await ensureAuthenticated();
    final queryLower = query.toLowerCase();

    if (!_isCacheValid()) {
      final snapshot = await _root.child('users').get();
      if (!snapshot.exists || snapshot.value is! Map<Object?, Object?>) {
        return [];
      }

      _identityCache.clear();
      final usersData = snapshot.value! as Map<Object?, Object?>;
      for (final entry in usersData.entries) {
        final username = entry.key as String?;
        if (username != null && entry.value is Map<Object?, Object?>) {
          final value = entry.value as Map<Object?, Object?>;
          _identityCache[username] = BackendIdentity(
            username: username,
            uid: value['uid'] as String? ?? '',
            displayName: value['displayName'] as String? ?? username,
            registeredAt: (value['registeredAt'] as num?)?.toInt() ?? 0,
            lastSeen: (value['lastSeen'] as num?)?.toInt() ?? 0,
            lastHeartbeat: (value['lastHeartbeat'] as num?)?.toInt() ?? 0,
            online: value['online'] as bool? ?? false,
          );
        }
      }
      _cacheTimestamp = DateTime.now().millisecondsSinceEpoch;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    return _identityCache.values
        .where(
          (identity) => identity.username.toLowerCase().contains(queryLower),
        )
        .take(_searchLimit)
        .map(
          (identity) => BackendIdentity(
            username: identity.username,
            uid: identity.uid,
            displayName: identity.displayName,
            registeredAt: identity.registeredAt,
            lastSeen: identity.lastSeen,
            lastHeartbeat: identity.lastHeartbeat,
            online:
                identity.online &&
                (now - identity.lastHeartbeat < _presenceTimeoutMs),
          ),
        )
        .toList();
  }

  @override
  Future<void> addToUserSearch(String username) async {
    await ensureAuthenticated();
    await _root.child('userSearch/$username').set(true);
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    await ensureAuthenticated();
    final snapshot = await _root.child('users/$username').get();
    if (!snapshot.exists || snapshot.value is! Map<Object?, Object?>) {
      return true;
    }
    final value = snapshot.value! as Map<Object?, Object?>;
    return value['uid'] == _auth.currentUser?.uid;
  }

  @override
  Stream<SDPPayload> onAnswer(String roomId) {
    return _root
        .child('rooms/$roomId/answer')
        .onValue
        .map((DatabaseEvent event) => event.snapshot.value)
        .where((Object? value) => value is Map<Object?, Object?>)
        .map(
          (Object? value) =>
              SDPPayload.fromJson(value! as Map<Object?, Object?>),
        );
  }

  @override
  Stream<String> onFriendRequest(String username) {
    return _root
        .child('friendRequests/$username')
        .onChildAdded
        .map((DatabaseEvent event) => event.snapshot.key ?? '')
        .where((String value) => value.isNotEmpty);
  }

  @override
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role) {
    final path = role == IceRole.caller ? 'callerICE' : 'calleeICE';
    return _root.child('rooms/$roomId/$path').onChildAdded.map((
      DatabaseEvent event,
    ) {
      final value =
          event.snapshot.value as Map<Object?, Object?>? ??
          <Object?, Object?>{};
      return iceCandidateFromJson(value);
    });
  }

  @override
  Stream<SDPPayload> onOffer(String roomId) {
    return _root
        .child('rooms/$roomId/offer')
        .onValue
        .map((DatabaseEvent event) => event.snapshot.value)
        .where((Object? value) => value is Map<Object?, Object?>)
        .map(
          (Object? value) =>
              SDPPayload.fromJson(value! as Map<Object?, Object?>),
        );
  }

  @override
  Future<void> setPresence(String username, bool online) async {
    await ensureAuthenticated();
    final now = DateTime.now().millisecondsSinceEpoch;
    final uid = _auth.currentUser?.uid ?? '';
    await _root.child('users/$username').update(<String, Object?>{
      'uid': uid,
      'online': online,
      'lastSeen': online ? now : null,
      'lastHeartbeat': now,
    });
  }

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {
    await ensureAuthenticated();
    await _root
        .child('users/${identity.username}')
        .set(identity.toFirebaseJson());
    await _root.child('userSearch/${identity.username}').set(true);
  }

  @override
  Stream<bool> watchPresence(String username) {
    final controller = StreamController<bool>.broadcast();

    final onlineRef = _root.child('users/$username/online');
    final lastHeartbeatRef = _root.child('users/$username/lastHeartbeat');

    late StreamSubscription<DatabaseEvent> onlineSub;
    late StreamSubscription<DatabaseEvent> heartbeatSub;

    bool? currentOnline;
    int? currentHeartbeat;

    void checkPresence() {
      if (currentOnline == null || currentHeartbeat == null) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final isActuallyOnline =
          currentOnline! && (now - currentHeartbeat! < _presenceTimeoutMs);
      controller.add(isActuallyOnline);
    }

    onlineSub = onlineRef.onValue.listen((DatabaseEvent event) {
      currentOnline = event.snapshot.value as bool? ?? false;
      checkPresence();
    });

    heartbeatSub = lastHeartbeatRef.onValue.listen((DatabaseEvent event) {
      currentHeartbeat = (event.snapshot.value as num?)?.toInt();
      checkPresence();
    });

    controller.onCancel = () {
      onlineSub.cancel();
      heartbeatSub.cancel();
    };

    return controller.stream;
  }

  Future<void> sendHeartbeat(String username) async {
    await ensureAuthenticated();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _root.child('users/$username/lastHeartbeat').set(now);
  }

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) async {
    await ensureAuthenticated();
    await _root.child('rooms/$roomId/answer').set(answer.toJson());
  }

  @override
  Future<void> writeFriendRequest(String to, String from) async {
    await ensureAuthenticated();
    await _root.child('friendRequests/$to/$from').set(<String, Object?>{
      'sentAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    RTCIceCandidate candidate,
  ) async {
    await ensureAuthenticated();
    final path = role == IceRole.caller ? 'callerICE' : 'calleeICE';
    await _root
        .child('rooms/$roomId/$path')
        .push()
        .set(iceCandidateToJson(candidate));
  }

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {
    await ensureAuthenticated();
    await _root.child('rooms/$roomId/offer').set(offer.toJson());
  }
}
