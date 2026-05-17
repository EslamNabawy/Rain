import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling_adapter.dart';
import 'signaling_cipher.dart';

class FirebaseSignalingAdapter implements SignalingAdapter {
  FirebaseSignalingAdapter({
    FirebaseAuth? auth,
    FirebaseDatabase? database,
    SignalingCipher? signalingCipher,
    bool useEmulator = false,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _database = database ?? FirebaseDatabase.instance,
       _signalingCipher = signalingCipher ?? SignalingCipher.demo(),
       _useEmulator = useEmulator;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;
  final SignalingCipher _signalingCipher;
  final bool _useEmulator;
  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(
    36,
  );
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

  static const int _presenceTimeoutMs = 90 * 1000;
  static const int _roomTtlMs = 15 * 60 * 1000;
  static const int _searchLimit = 10;

  Map<String, Object?> _identityJson({
    required String username,
    required String uid,
    required String displayName,
    required String? gender,
    required int registeredAt,
  }) {
    return <String, Object?>{
      'uid': uid,
      'displayName': displayName,
      'gender': gender,
      'registeredAt': registeredAt,
      'username': username,
    };
  }

  Map<String, Object?> _presenceJson({
    required String uid,
    required bool online,
    required int now,
  }) {
    return <String, Object?>{
      'uid': uid,
      'online': online,
      'lastHeartbeat': now,
      'lastSeen': now,
      'updatedAt': now,
      'sessionId': _sessionId,
      'platform': 'flutter',
    };
  }

  Map<String, Object?> _roomLifecycle({
    required String roomId,
    required int timestamp,
    bool newAttempt = false,
  }) {
    return <String, Object?>{
      if (newAttempt) ...<String, Object?>{
        'attemptId': '$roomId:$timestamp',
        'createdAt': timestamp,
      },
      'updatedAt': timestamp,
      'expiresAt': timestamp + _roomTtlMs,
    };
  }

  bool _isFreshPresence(bool online, int lastHeartbeat) {
    return online &&
        DateTime.now().millisecondsSinceEpoch - lastHeartbeat <
            _presenceTimeoutMs;
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

    await _root
        .child('users/$normalizedUsername')
        .set(
          _identityJson(
            username: normalizedUsername,
            uid: uid,
            displayName: normalizedUsername,
            gender: null,
            registeredAt: now,
          ),
        );

    await _root.child('userSearch/$normalizedUsername').set(true);
    await setPresence(normalizedUsername, true);
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
    final presenceSnapshot = await _root.child('presence/$username').get();
    final presence = presenceSnapshot.value is Map<Object?, Object?>
        ? presenceSnapshot.value! as Map<Object?, Object?>
        : const <Object?, Object?>{};
    final lastHeartbeat = (presence['lastHeartbeat'] as num?)?.toInt() ?? 0;
    final online = _isFreshPresence(
      presence['online'] as bool? ?? false,
      lastHeartbeat,
    );
    final identity = BackendIdentity(
      username: username,
      uid: value['uid'] as String? ?? '',
      displayName: value['displayName'] as String? ?? username,
      gender: value['gender'] as String?,
      registeredAt: (value['registeredAt'] as num?)?.toInt() ?? 0,
      lastSeen: (presence['lastSeen'] as num?)?.toInt() ?? 0,
      lastHeartbeat: lastHeartbeat,
      online: online,
    );
    return identity;
  }

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async {
    if (query.length < 2) return [];

    await ensureAuthenticated();
    final queryLower = query.toLowerCase();
    final snapshot = await _root
        .child('userSearch')
        .orderByKey()
        .startAt(queryLower)
        .endAt('$queryLower\uf8ff')
        .limitToFirst(_searchLimit)
        .get();
    if (!snapshot.exists) {
      return const <BackendIdentity>[];
    }

    final usernames = <String>{};
    for (final child in snapshot.children) {
      final key = child.key;
      if (key != null && key.isNotEmpty) {
        usernames.add(key);
      }
    }
    if (usernames.isEmpty && snapshot.value is Map<Object?, Object?>) {
      for (final key in (snapshot.value! as Map<Object?, Object?>).keys) {
        if (key is String && key.isNotEmpty) {
          usernames.add(key);
        }
      }
    }

    final identities = <BackendIdentity>[];
    for (final username in usernames.take(_searchLimit)) {
      final identity = await fetchIdentity(username);
      if (identity != null) {
        identities.add(identity);
      }
    }
    return identities;
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
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    await _ensureSignedInAsUsername(normalizedFirstUser);
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
  Future<void> blockUser(String blocker, String blocked) async {
    final normalizedBlocker = _normalizedUsername(blocker);
    final normalizedBlocked = _normalizedUsername(blocked);
    await _ensureSignedInAsUsername(normalizedBlocker);
    if (normalizedBlocker == normalizedBlocked) {
      throw Exception('Cannot block yourself');
    }
    final payload = <String, Object?>{
      'blockedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _root.update(<String, Object?>{
      'blocks/$normalizedBlocker/$normalizedBlocked': payload,
      'blockedBy/$normalizedBlocked/$normalizedBlocker': payload,
      'friendships/$normalizedBlocker/$normalizedBlocked': null,
      'friendships/$normalizedBlocked/$normalizedBlocker': null,
      'friendRequests/$normalizedBlocker/$normalizedBlocked': null,
      'friendRequests/$normalizedBlocked/$normalizedBlocker': null,
      'outgoingFriendRequests/$normalizedBlocker/$normalizedBlocked': null,
      'outgoingFriendRequests/$normalizedBlocked/$normalizedBlocker': null,
    });
  }

  @override
  Future<void> unblockUser(String blocker, String blocked) async {
    final normalizedBlocker = _normalizedUsername(blocker);
    final normalizedBlocked = _normalizedUsername(blocked);
    await _ensureSignedInAsUsername(normalizedBlocker);
    await _root.update(<String, Object?>{
      'blocks/$normalizedBlocker/$normalizedBlocked': null,
      'blockedBy/$normalizedBlocked/$normalizedBlocker': null,
    });
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
  Future<List<String>> loadBlockedUsers(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    final snapshot = await _root.child('blocks/$normalizedUsername').get();
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
  Future<List<String>> loadUsersBlocking(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    final snapshot = await _root.child('blockedBy/$normalizedUsername').get();
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
        .asyncMap((Object? value) async {
          final payload = await _signalingCipher.decryptPayload(
            roomId: roomId,
            purpose: SignalingCipher.answerPurpose,
            payload: value! as Map<Object?, Object?>,
          );
          return SDPPayload.fromJson(payload);
        });
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
  Stream<String> onRelationshipChanged(String username) {
    final normalizedUsername = _normalizedUsername(username);
    late final StreamController<String> controller;
    final subscriptions = <StreamSubscription<DatabaseEvent>>[];

    void emitPeer(DatabaseEvent event) {
      final key = event.snapshot.key;
      if (key != null && key.isNotEmpty && !controller.isClosed) {
        controller.add(key);
      }
    }

    void listenTo(DatabaseReference reference) {
      subscriptions.add(reference.onChildAdded.listen(emitPeer));
      subscriptions.add(reference.onChildChanged.listen(emitPeer));
      subscriptions.add(reference.onChildRemoved.listen(emitPeer));
    }

    controller = StreamController<String>.broadcast(
      onListen: () {
        listenTo(_root.child('friendships/$normalizedUsername'));
        listenTo(_root.child('friendRequests/$normalizedUsername'));
        listenTo(_root.child('outgoingFriendRequests/$normalizedUsername'));
        listenTo(_root.child('blocks/$normalizedUsername'));
        listenTo(_root.child('blockedBy/$normalizedUsername'));
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
      },
    );

    return controller.stream;
  }

  @override
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role) {
    final path = role == IceRole.caller ? 'callerICE' : 'calleeICE';
    final purpose = role == IceRole.caller
        ? SignalingCipher.callerIcePurpose
        : SignalingCipher.calleeIcePurpose;
    return _root
        .child('rooms/$roomId/$path')
        .onChildAdded
        .map((DatabaseEvent event) => event.snapshot.value)
        .where((Object? value) => value is Map<Object?, Object?>)
        .asyncMap((Object? value) async {
          final payload = await _signalingCipher.decryptPayload(
            roomId: roomId,
            purpose: purpose,
            payload: value! as Map<Object?, Object?>,
          );
          return iceCandidateFromJson(payload);
        });
  }

  @override
  Stream<SDPPayload> onOffer(String roomId) {
    return _root
        .child('rooms/$roomId/offer')
        .onValue
        .map((DatabaseEvent event) => event.snapshot.value)
        .where((Object? value) => value is Map<Object?, Object?>)
        .asyncMap((Object? value) async {
          final payload = await _signalingCipher.decryptPayload(
            roomId: roomId,
            purpose: SignalingCipher.offerPurpose,
            payload: value! as Map<Object?, Object?>,
          );
          return SDPPayload.fromJson(payload);
        });
  }

  @override
  Future<void> setPresence(String username, bool online) async {
    await _ensureSignedInAsUsername(username);
    final now = DateTime.now().millisecondsSinceEpoch;
    final uid = _auth.currentUser?.uid ?? '';
    await _root
        .child('presence/$username')
        .update(_presenceJson(uid: uid, online: online, now: now));
  }

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {
    await _ensureSignedInAsUsername(identity.username);
    await _root
        .child('users/${identity.username}')
        .update(
          _identityJson(
            username: identity.username,
            uid: identity.uid,
            displayName: identity.displayName,
            gender: identity.gender,
            registeredAt: identity.registeredAt,
          ),
        );
    await _root.child('userSearch/${identity.username}').set(true);
  }

  @override
  Stream<bool> watchPresence(String username) {
    final controller = StreamController<bool>.broadcast();
    final presenceRef = _root.child('presence/$username');

    late StreamSubscription<DatabaseEvent> presenceSub;
    Timer? expiryTimer;

    bool? lastEmitted;

    void emitPresence(bool online, int lastHeartbeat) {
      expiryTimer?.cancel();
      expiryTimer = null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiresIn = _presenceTimeoutMs - (now - lastHeartbeat);
      final isActuallyOnline = online && expiresIn > 0;
      if (lastEmitted != isActuallyOnline && !controller.isClosed) {
        lastEmitted = isActuallyOnline;
        controller.add(isActuallyOnline);
      }
      if (isActuallyOnline) {
        expiryTimer = Timer(
          Duration(milliseconds: expiresIn),
          () => emitPresence(online, lastHeartbeat),
        );
      }
    }

    presenceSub = presenceRef.onValue.listen((DatabaseEvent event) {
      if (event.snapshot.value is! Map<Object?, Object?>) {
        emitPresence(false, 0);
        return;
      }
      final value = event.snapshot.value! as Map<Object?, Object?>;
      emitPresence(
        value['online'] as bool? ?? false,
        (value['lastHeartbeat'] as num?)?.toInt() ?? 0,
      );
    });

    controller.onCancel = () {
      expiryTimer?.cancel();
      presenceSub.cancel();
    };

    return controller.stream;
  }

  @override
  Future<void> sendHeartbeat(String username) async {
    await _ensureSignedInAsUsername(username);
    final now = DateTime.now().millisecondsSinceEpoch;
    final uid = _auth.currentUser?.uid ?? '';
    await _root
        .child('presence/$username')
        .update(_presenceJson(uid: uid, online: true, now: now));
  }

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) async {
    await ensureAuthenticated();
    final timestamp = answer.ts == 0
        ? DateTime.now().millisecondsSinceEpoch
        : answer.ts;
    final encryptedAnswer = await _signalingCipher.encryptPayload(
      roomId: roomId,
      purpose: SignalingCipher.answerPurpose,
      timestamp: timestamp,
      payload: answer.toJson(),
    );
    await _root.child('rooms/$roomId').update(<String, Object?>{
      ..._roomParticipants(roomId),
      ..._roomLifecycle(roomId: roomId, timestamp: timestamp),
      'answer': encryptedAnswer,
    });
  }

  @override
  Future<void> writeFriendRequest(String to, String from) async {
    final normalizedTo = _normalizedUsername(to);
    final normalizedFrom = _normalizedUsername(from);
    await _ensureSignedInAsUsername(normalizedFrom);
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
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    await _ensureSignedInAsUsername(normalizedFirstUser);
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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = role == IceRole.caller ? 'callerICE' : 'calleeICE';
    final candidateRef = _root.child('rooms/$roomId/$path').push();
    final candidateKey = candidateRef.key;
    if (candidateKey == null || candidateKey.isEmpty) {
      throw Exception('Failed to allocate ICE candidate key');
    }
    final encryptedCandidate = await _signalingCipher.encryptPayload(
      roomId: roomId,
      purpose: role == IceRole.caller
          ? SignalingCipher.callerIcePurpose
          : SignalingCipher.calleeIcePurpose,
      timestamp: timestamp,
      payload: iceCandidateToJson(candidate),
    );
    await _root.child('rooms/$roomId').update(<String, Object?>{
      ..._roomParticipants(roomId),
      ..._roomLifecycle(roomId: roomId, timestamp: timestamp),
      '$path/$candidateKey': encryptedCandidate,
    });
  }

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {
    await ensureAuthenticated();
    final timestamp = offer.ts == 0
        ? DateTime.now().millisecondsSinceEpoch
        : offer.ts;
    final encryptedOffer = await _signalingCipher.encryptPayload(
      roomId: roomId,
      purpose: SignalingCipher.offerPurpose,
      timestamp: timestamp,
      payload: offer.toJson(),
    );
    await _root.child('rooms/$roomId').update(<String, Object?>{
      ..._roomParticipants(roomId),
      ..._roomLifecycle(roomId: roomId, timestamp: timestamp, newAttempt: true),
      'offer': encryptedOffer,
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
      'invalid-credential' || 'wrong-password' => Exception(
        'Wrong password. Check the password and try again.',
      ),
      'user-not-found' => Exception(
        'Unknown user. Check the unique username or create an account.',
      ),
      'email-already-in-use' => Exception(
        'Username is already taken. Choose another unique username.',
      ),
      'user-disabled' => Exception(
        'This account is disabled. Contact the project owner.',
      ),
      'network-request-failed' => Exception(
        'Network connection failed. Check your internet and try again.',
      ),
      'too-many-requests' => Exception(
        'Too many attempts. Wait a moment, then try again.',
      ),
      'weak-password' => Exception('Password must be at least 6 characters.'),
      _ => Exception(error.message ?? error.code),
    };
  }
}
