import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling_adapter.dart';

class FirebaseSignalingAdapter implements SignalingAdapter {
  FirebaseSignalingAdapter({
    FirebaseAuth? auth,
    FirebaseDatabase? database,
    bool useEmulator = false,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _database = database ?? FirebaseDatabase.instance,
       _useEmulator = useEmulator;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final bool _useEmulator;
  bool _emulatorsConfigured = false;
  String _emailFromUsername(String username) => '$username@rain.local';

  String _normalizedUsername(String username) {
    return username.trim().toLowerCase();
  }

  String _canonicalRoomId(String firstUser, String secondUser) {
    final users = <String>[
      _normalizedUsername(firstUser),
      _normalizedUsername(secondUser),
    ]..sort();
    return '${users[0]}:${users[1]}';
  }

  List<String> _roomUsers(String roomId) {
    final parts = roomId.split(':');
    if (parts.length != 2 || parts.any((String value) => value.isEmpty)) {
      throw ArgumentError.value(roomId, 'roomId', 'Expected exactly two peers');
    }
    final canonical = _canonicalRoomId(parts[0], parts[1]);
    if (canonical != roomId) {
      throw ArgumentError.value(
        roomId,
        'roomId',
        'Expected canonical room id ordering',
      );
    }
    return parts;
  }

  Map<String, Object?> _roomParticipants(String roomId) {
    final users = _roomUsers(roomId);
    return <String, Object?>{'userA': users[0], 'userB': users[1]};
  }

  Future<void> _configureEmulatorsIfNeeded() async {
    if (!_useEmulator || _emulatorsConfigured) return;
    try {
      // Prefer localhost emulators in CI/dev environments.
      const String host = 'localhost';
      const int authPort = 9099; // Firebase Auth emulator default
      const int dbPort = 9000; // Firebase Realtime Database emulator default
      // Configure auth and database emulators. These calls are idempotent.
      _auth.useAuthEmulator(host, authPort);
      _database.useDatabaseEmulator(host, dbPort);
    } catch (_) {
      // If emulators are not available, fall back gracefully.
    }
    _emulatorsConfigured = true;
  }

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
    await _configureEmulatorsIfNeeded();
    await ensureAuthenticated();
    await _root.child('rooms/$roomId').remove();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> ensureAuthenticated() async {
    await _configureEmulatorsIfNeeded();
    final user = _auth.currentUser;
    if (user != null && !user.isAnonymous) {
      return;
    }
    if (user?.isAnonymous ?? false) {
      await _auth.signOut();
    }
    throw const SignalingSessionExpiredException(
      'Firebase sign-in required. Sign in again to continue chatting.',
    );
  }

  @override
  Future<String> register(String username, String password) async {
    await _configureEmulatorsIfNeeded();
    final normalizedUsername = _normalizedUsername(username);

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    final email = _emailFromUsername(normalizedUsername);
    final UserCredential userCredential;
    try {
      userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        throw Exception('Username "$normalizedUsername" is already taken');
      }
      throw _normalizeFirebaseAuthException(error);
    }
    final uid = userCredential.user?.uid ?? '';
    final now = DateTime.now().millisecondsSinceEpoch;

    await _root.child('users/$normalizedUsername').set(<String, Object?>{
      'uid': uid,
      'displayName': normalizedUsername,
      'gender': null,
      'registeredAt': now,
      'lastSeen': now,
      'lastHeartbeat': now,
      'online': true,
      'username': normalizedUsername,
    });

    await _root.child('userSearch/$normalizedUsername').set(true);
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    return uid;
  }

  @override
  Future<String> login(String username, String password) async {
    await _configureEmulatorsIfNeeded();
    final email = _emailFromUsername(username);
    final UserCredential result;
    try {
      result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw _normalizeFirebaseAuthException(error);
    }
    final uid = result.user?.uid ?? _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      throw Exception('Failed to sign in Firebase user');
    }
    return uid;
  }

  @override
  Future<String> currentUid() async {
    await _configureEmulatorsIfNeeded();
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
      gender: value['gender'] as String?,
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
    if (query.length < 2) return [];

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
            gender: value['gender'] as String?,
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
            gender: identity.gender,
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
  Future<void> deleteFriendRequest(String to, String from) async {
    await ensureAuthenticated();
    final normalizedTo = _normalizedUsername(to);
    final normalizedFrom = _normalizedUsername(from);
    await _root.update(<String, Object?>{
      'friendRequests/$normalizedTo/$normalizedFrom': null,
      'outgoingFriendRequests/$normalizedFrom/$normalizedTo': null,
    });
  }

  @override
  Future<void> deleteFriendship(String firstUser, String secondUser) async {
    await ensureAuthenticated();
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    await _root
        .child('friendships/$normalizedFirstUser/$normalizedSecondUser')
        .remove();
    await _root
        .child('friendships/$normalizedSecondUser/$normalizedFirstUser')
        .remove();
    await deleteFriendRequest(normalizedFirstUser, normalizedSecondUser);
    await deleteFriendRequest(normalizedSecondUser, normalizedFirstUser);
  }

  @override
  Future<List<String>> loadAcceptedFriends(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    final snapshot = await _root.child('friendships/$normalizedUsername').get();
    if (!snapshot.exists || snapshot.value is! Map<Object?, Object?>) {
      return const <String>[];
    }

    final values = snapshot.value! as Map<Object?, Object?>;
    return values.keys
        .whereType<String>()
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<String>> loadIncomingFriendRequests(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    final snapshot = await _root
        .child('friendRequests/$normalizedUsername')
        .get();
    if (!snapshot.exists || snapshot.value is! Map<Object?, Object?>) {
      return const <String>[];
    }

    final values = snapshot.value! as Map<Object?, Object?>;
    return values.keys
        .whereType<String>()
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<String>> loadOutgoingFriendRequests(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    final snapshot = await _root
        .child('outgoingFriendRequests/$normalizedUsername')
        .get();
    if (!snapshot.exists || snapshot.value is! Map<Object?, Object?>) {
      return const <String>[];
    }

    final values = snapshot.value! as Map<Object?, Object?>;
    return values.keys
        .whereType<String>()
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
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
    await _ensureSignedInAsUsername(username);
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
    await _ensureSignedInAsUsername(identity.username);
    await _root
        .child('users/${identity.username}')
        .update(identity.toFirebaseJson());
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
    await _root.child('rooms/$roomId').update(<String, Object?>{
      ..._roomParticipants(roomId),
      'answer': answer.toJson(),
    });
  }

  @override
  Future<void> writeFriendRequest(String to, String from) async {
    await ensureAuthenticated();
    final normalizedTo = _normalizedUsername(to);
    final normalizedFrom = _normalizedUsername(from);
    if (normalizedTo == normalizedFrom) {
      throw Exception('Cannot send friend request to yourself');
    }
    final payload = <String, Object?>{
      'sentAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _root.update(<String, Object?>{
      'friendRequests/$normalizedTo/$normalizedFrom': payload,
      'outgoingFriendRequests/$normalizedFrom/$normalizedTo': payload,
    });
  }

  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) async {
    await ensureAuthenticated();
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    final payload = <String, Object?>{
      'acceptedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _root
        .child('friendships/$normalizedFirstUser/$normalizedSecondUser')
        .set(payload);
    await _root
        .child('friendships/$normalizedSecondUser/$normalizedFirstUser')
        .set(payload);
    await deleteFriendRequest(normalizedFirstUser, normalizedSecondUser);
    await deleteFriendRequest(normalizedSecondUser, normalizedFirstUser);
  }

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    RTCIceCandidate candidate,
  ) async {
    await ensureAuthenticated();
    final path = role == IceRole.caller ? 'callerICE' : 'calleeICE';
    final candidateRef = _root.child('rooms/$roomId/$path').push();
    final candidateKey = candidateRef.key;
    if (candidateKey == null || candidateKey.isEmpty) {
      throw Exception('Failed to allocate ICE candidate key');
    }
    await _root.child('rooms/$roomId').update(<String, Object?>{
      ..._roomParticipants(roomId),
      '$path/$candidateKey': iceCandidateToJson(candidate),
    });
  }

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {
    await ensureAuthenticated();
    await _root.child('rooms/$roomId').update(<String, Object?>{
      ..._roomParticipants(roomId),
      'offer': offer.toJson(),
    });
  }

  Future<void> _ensureSignedInAsUsername(String username) async {
    await ensureAuthenticated();
    final expectedEmail = _emailFromUsername(_normalizedUsername(username));
    final actualEmail = _auth.currentUser?.email?.toLowerCase();
    if (actualEmail != expectedEmail) {
      await _auth.signOut();
      throw SignalingSessionExpiredException(
        'Firebase is signed in as ${actualEmail ?? 'another account'}; sign in as @$username to continue.',
      );
    }
  }

  Exception _normalizeFirebaseAuthException(FirebaseAuthException error) {
    return switch (error.code) {
      'operation-not-allowed' => Exception(
        'Enable Email/Password sign-in in Firebase Console > Authentication > Sign-in method.',
      ),
      _ => Exception(error.message ?? error.code),
    };
  }
}
