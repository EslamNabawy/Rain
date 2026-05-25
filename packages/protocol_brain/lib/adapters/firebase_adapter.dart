import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../src/voice_call_frame.dart';
import '../src/voice_signaling_contract.dart';
import 'signaling_adapter.dart';
import 'signaling_cipher.dart';

class FirebaseSignalingAdapter
    implements SignalingAdapter, VoiceSignalingAdapter {
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
  static const int _orphanVoiceLockGraceMs = 15000;
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
  Future<VoiceCallRoom> createOutgoingCall({
    required String callId,
    required String caller,
    required String callee,
    required int createdAt,
    required int expiresAt,
    CallMediaMode mediaMode = CallMediaMode.audio,
  }) async {
    await _configureEmulatorsIfNeeded();
    final normalizedCallId = callId.trim();
    final normalizedCaller = normalizeVoiceCallUsername(caller);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    await _ensureSignedInAsUsername(normalizedCaller);

    final pairId = voiceCallPairId(normalizedCaller, normalizedCallee);
    final room = VoiceCallRoom(
      v: VoiceCallRoom.version,
      callId: normalizedCallId,
      pairId: pairId,
      caller: normalizedCaller,
      callee: normalizedCallee,
      status: VoiceCallSignalingStatus.ringing,
      mediaMode: mediaMode,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
      muted: Map<String, bool>.unmodifiable(<String, bool>{
        normalizedCaller: false,
        normalizedCallee: false,
      }),
      cameraMuted: mediaMode == CallMediaMode.video
          ? Map<String, bool>.unmodifiable(<String, bool>{
              normalizedCaller: false,
              normalizedCallee: false,
            })
          : const <String, bool>{},
    );
    room.validate();
    final lock = VoiceActivePairLock(
      pairId: pairId,
      callId: normalizedCallId,
      caller: normalizedCaller,
      callee: normalizedCallee,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
    );
    final inbox = VoiceCallInboxEntry(
      callId: normalizedCallId,
      from: normalizedCaller,
      to: normalizedCallee,
      pairId: pairId,
      status: VoiceCallSignalingStatus.ringing,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
    );

    final lockRef = _root.child('activeVoicePairs/$pairId');
    var claimed = await _claimActiveVoicePairLock(
      lockRef: lockRef,
      lock: lock,
      createdAt: createdAt,
    );
    if (!claimed &&
        await _tryReclaimStaleActiveVoicePair(
          lockRef: lockRef,
          pairId: pairId,
          caller: normalizedCaller,
          callee: normalizedCallee,
          createdAt: createdAt,
        )) {
      claimed = await _claimActiveVoicePairLock(
        lockRef: lockRef,
        lock: lock,
        createdAt: createdAt,
      );
    }
    if (!claimed) {
      throw VoiceSignalingException(
        'Active voice call already exists for pair $pairId.',
      );
    }

    try {
      await _root.update(<String, Object?>{
        'voiceCalls/$normalizedCallId': room.toJson(),
        'voiceCallInboxes/$normalizedCallee/$normalizedCallId': inbox.toJson(),
      });
    } catch (_) {
      await _removeActiveVoicePairLockIfUnchanged(lockRef: lockRef, lock: lock);
      rethrow;
    }
    return room;
  }

  Future<bool> _claimActiveVoicePairLock({
    required DatabaseReference lockRef,
    required VoiceActivePairLock lock,
    required int createdAt,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final transaction = await lockRef.runTransaction((Object? current) {
      if (current is Map) {
        try {
          final existing = VoiceActivePairLock.fromJson(
            pairId: lock.pairId,
            json: _asObjectMap(current),
          );
          if (existing.expiresAt > createdAt && existing.expiresAt > now) {
            return Transaction.abort();
          }
        } catch (_) {
          return Transaction.abort();
        }
      }
      return Transaction.success(lock.toJson());
    }, applyLocally: false);
    return transaction.committed;
  }

  Future<bool> _tryReclaimStaleActiveVoicePair({
    required DatabaseReference lockRef,
    required String pairId,
    required String caller,
    required String callee,
    required int createdAt,
  }) async {
    final snapshot = await lockRef.get();
    final value = snapshot.value;
    if (value is! Map) {
      return false;
    }

    final VoiceActivePairLock existing;
    try {
      existing = VoiceActivePairLock.fromJson(
        pairId: pairId,
        json: _asObjectMap(value),
      );
    } catch (_) {
      return false;
    }
    if (!_lockMatchesVoicePair(existing, caller, callee)) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final VoiceCallRoom? room;
    try {
      room = await fetchCall(existing.callId);
    } catch (_) {
      if (!_shouldReclaimUnreadableActiveVoicePairLock(
        lock: existing,
        caller: caller,
        createdAt: createdAt,
        now: now,
      )) {
        return false;
      }
      return _removeActiveVoicePairLockIfUnchanged(
        lockRef: lockRef,
        lock: existing,
      );
    }
    if (!_shouldReclaimActiveVoicePairLock(
      lock: existing,
      room: room,
      caller: caller,
      createdAt: createdAt,
      now: now,
    )) {
      return false;
    }

    final removed = await _removeActiveVoicePairLockIfUnchanged(
      lockRef: lockRef,
      lock: existing,
    );
    if (!removed) {
      return false;
    }

    if (room != null &&
        _shouldDeleteReclaimedVoiceRoom(room, createdAt, now, caller: caller)) {
      try {
        await _deleteVoiceCallRoomArtifacts(room);
      } catch (_) {
        // The lock is the user-visible blocker; stale room cleanup can wait for
        // the scheduled Firebase cleanup if permissions or connectivity fail.
      }
    }
    return true;
  }

  bool _shouldReclaimUnreadableActiveVoicePairLock({
    required VoiceActivePairLock lock,
    required String caller,
    required int createdAt,
    required int now,
  }) {
    if (lock.expiresAt <= createdAt || lock.expiresAt <= now) {
      return true;
    }
    if (lock.caller == normalizeVoiceCallUsername(caller)) {
      return true;
    }
    return createdAt - lock.updatedAt >= _orphanVoiceLockGraceMs ||
        now - lock.updatedAt >= _orphanVoiceLockGraceMs;
  }

  bool _shouldReclaimActiveVoicePairLock({
    required VoiceActivePairLock lock,
    required VoiceCallRoom? room,
    required String caller,
    required int createdAt,
    required int now,
  }) {
    if (lock.expiresAt <= createdAt || lock.expiresAt <= now) {
      return true;
    }
    if (room == null) {
      if (lock.caller == normalizeVoiceCallUsername(caller)) {
        return true;
      }
      return createdAt - lock.updatedAt >= _orphanVoiceLockGraceMs ||
          now - lock.updatedAt >= _orphanVoiceLockGraceMs;
    }
    if (!room.isTerminal &&
        room.status != VoiceCallSignalingStatus.connected &&
        lock.caller == normalizeVoiceCallUsername(caller)) {
      return true;
    }
    if (room.isTerminal) {
      return true;
    }
    return room.status != VoiceCallSignalingStatus.connected &&
        (room.expiresAt <= createdAt || room.expiresAt <= now);
  }

  bool _shouldDeleteReclaimedVoiceRoom(
    VoiceCallRoom room,
    int createdAt,
    int now, {
    required String caller,
  }) {
    if (room.isTerminal) {
      return true;
    }
    if (room.status != VoiceCallSignalingStatus.connected &&
        room.caller == normalizeVoiceCallUsername(caller)) {
      return true;
    }
    return room.status != VoiceCallSignalingStatus.connected &&
        (room.expiresAt <= createdAt || room.expiresAt <= now);
  }

  Future<bool> _removeActiveVoicePairLockIfUnchanged({
    required DatabaseReference lockRef,
    required VoiceActivePairLock lock,
  }) async {
    final transaction = await lockRef.runTransaction((Object? current) {
      if (current is! Map) {
        return Transaction.abort();
      }
      try {
        final existing = VoiceActivePairLock.fromJson(
          pairId: lock.pairId,
          json: _asObjectMap(current),
        );
        if (_sameActiveVoicePairLock(existing, lock)) {
          return Transaction.success(null);
        }
      } catch (_) {
        return Transaction.abort();
      }
      return Transaction.abort();
    }, applyLocally: false);
    return transaction.committed;
  }

  Future<void> _deleteVoiceCallRoomArtifacts(VoiceCallRoom room) async {
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}': null,
      'voiceCallInboxes/${room.callee}/${room.callId}': null,
    });
  }

  Future<void> _removeActiveVoicePairLockForRoomIfCurrent(
    VoiceCallRoom room,
  ) async {
    await _removeActiveVoicePairLockIfUnchanged(
      lockRef: _root.child('activeVoicePairs/${room.pairId}'),
      lock: _activeVoicePairLockForRoom(room),
    );
  }

  VoiceActivePairLock _activeVoicePairLockForRoom(VoiceCallRoom room) {
    return VoiceActivePairLock(
      pairId: room.pairId,
      callId: room.callId,
      caller: room.caller,
      callee: room.callee,
      createdAt: room.createdAt,
      updatedAt: room.createdAt,
      expiresAt: room.expiresAt,
    );
  }

  bool _lockMatchesVoicePair(
    VoiceActivePairLock lock,
    String caller,
    String callee,
  ) {
    final normalizedCaller = normalizeVoiceCallUsername(caller);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    return lock.pairId == voiceCallPairId(normalizedCaller, normalizedCallee) &&
        ((lock.caller == normalizedCaller && lock.callee == normalizedCallee) ||
            (lock.caller == normalizedCallee &&
                lock.callee == normalizedCaller));
  }

  bool _sameActiveVoicePairLock(
    VoiceActivePairLock left,
    VoiceActivePairLock right,
  ) {
    return left.pairId == right.pairId &&
        left.callId == right.callId &&
        left.caller == right.caller &&
        left.callee == right.callee &&
        left.createdAt == right.createdAt &&
        left.updatedAt == right.updatedAt &&
        left.expiresAt == right.expiresAt;
  }

  @override
  Future<VoiceCallRoom?> fetchCall(String callId) async {
    await _configureEmulatorsIfNeeded();
    await ensureAuthenticated();
    final normalizedCallId = callId.trim();
    final snapshot = await _root.child('voiceCalls/$normalizedCallId').get();
    return _voiceCallRoomFromSnapshot(normalizedCallId, snapshot.value);
  }

  @override
  Stream<VoiceCallRoom?> watchCall(String callId) {
    final normalizedCallId = callId.trim();
    return _root
        .child('voiceCalls/$normalizedCallId')
        .onValue
        .map(
          (DatabaseEvent event) => _voiceCallRoomFromSnapshot(
            normalizedCallId,
            event.snapshot.value,
          ),
        );
  }

  @override
  Stream<VoiceCallInboxEntry> watchIncomingCalls(String username) {
    final normalizedUsername = normalizeVoiceCallUsername(username);
    late final StreamController<VoiceCallInboxEntry> controller;
    final subscriptions = <StreamSubscription<DatabaseEvent>>[];

    void emitEntry(DatabaseEvent event) {
      final key = event.snapshot.key;
      final value = event.snapshot.value;
      if (key == null || key.isEmpty || value is! Map) {
        return;
      }
      try {
        final entry = VoiceCallInboxEntry.fromJson(
          callId: key,
          json: _asObjectMap(value),
        );
        if (!controller.isClosed) {
          controller.add(entry);
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<VoiceCallInboxEntry>.broadcast(
      onListen: () {
        final ref = _root.child('voiceCallInboxes/$normalizedUsername');
        subscriptions.add(ref.onChildAdded.listen(emitEntry));
        subscriptions.add(ref.onChildChanged.listen(emitEntry));
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
  Future<void> acceptCall({
    required String callId,
    required String callee,
    required int acceptedAt,
  }) async {
    final room = await _requireVoiceCall(callId);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    await _ensureSignedInAsUsername(normalizedCallee);
    _ensureVoiceRole(room, normalizedCallee, VoiceCallRole.callee);
    _ensureVoiceStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.ringing,
    });
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}/status':
          VoiceCallSignalingStatus.accepted.name,
      'voiceCalls/${room.callId}/acceptedAt': acceptedAt,
      'voiceCalls/${room.callId}/updatedAt': acceptedAt,
      'voiceCallInboxes/${room.callee}/${room.callId}/status':
          VoiceCallSignalingStatus.accepted.name,
      'voiceCallInboxes/${room.callee}/${room.callId}/updatedAt': acceptedAt,
    });
  }

  @override
  Future<void> markConnected({
    required String callId,
    required String username,
    required int connectedAt,
  }) async {
    final room = await _requireVoiceCall(callId);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    await _ensureSignedInAsUsername(normalizedUsername);
    _ensureVoiceParticipant(room, normalizedUsername);
    _ensureVoiceStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.accepted,
      VoiceCallSignalingStatus.negotiating,
      VoiceCallSignalingStatus.connected,
    });
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}/status':
          VoiceCallSignalingStatus.connected.name,
      'voiceCalls/${room.callId}/connectedAt': connectedAt,
      'voiceCalls/${room.callId}/updatedAt': connectedAt,
      'voiceCallInboxes/${room.callee}/${room.callId}/status':
          VoiceCallSignalingStatus.connected.name,
      'voiceCallInboxes/${room.callee}/${room.callId}/updatedAt': connectedAt,
    });
  }

  @override
  Future<void> endCall({
    required String callId,
    required String username,
    required VoiceCallSignalingStatus status,
    required int endedAt,
    String? reasonCode,
    String? reason,
  }) async {
    if (!status.isTerminal) {
      throw const VoiceSignalingException(
        'Voice call end status must be terminal.',
      );
    }
    final room = await _requireVoiceCall(callId);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    await _ensureSignedInAsUsername(normalizedUsername);
    _ensureVoiceParticipant(room, normalizedUsername);
    if (room.status.isTerminal) {
      await _removeActiveVoicePairLockForRoomIfCurrent(room);
      return;
    }
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}/status': status.name,
      'voiceCalls/${room.callId}/endedAt': endedAt,
      'voiceCalls/${room.callId}/endedBy': normalizedUsername,
      'voiceCalls/${room.callId}/updatedAt': endedAt,
      'voiceCalls/${room.callId}/reasonCode': reasonCode,
      'voiceCalls/${room.callId}/reason': reason,
      'voiceCallInboxes/${room.callee}/${room.callId}/status': status.name,
      'voiceCallInboxes/${room.callee}/${room.callId}/updatedAt': endedAt,
      'activeVoicePairs/${room.pairId}': null,
    });
  }

  @override
  Future<void> setMuted({
    required String callId,
    required String username,
    required bool muted,
    required int updatedAt,
  }) async {
    final room = await _requireVoiceCall(callId);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    await _ensureSignedInAsUsername(normalizedUsername);
    _ensureVoiceParticipant(room, normalizedUsername);
    _ensureVoiceNonTerminal(room);
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}/muted/$normalizedUsername': muted,
      'voiceCalls/${room.callId}/updatedAt': updatedAt,
    });
  }

  @override
  Future<void> setCameraMuted({
    required String callId,
    required String username,
    required bool cameraMuted,
    required int updatedAt,
  }) async {
    final room = await _requireVoiceCall(callId);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    await _ensureSignedInAsUsername(normalizedUsername);
    _ensureVoiceParticipant(room, normalizedUsername);
    _ensureVoiceNonTerminal(room);
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}/cameraMuted/$normalizedUsername': cameraMuted,
      'voiceCalls/${room.callId}/updatedAt': updatedAt,
    });
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
  Future<void> writeVoiceOffer({
    required String callId,
    required String caller,
    required VoiceSignalingEnvelope offer,
    required int updatedAt,
  }) async {
    offer.validate(
      maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
    );
    final room = await _requireVoiceCall(callId);
    final normalizedCaller = normalizeVoiceCallUsername(caller);
    await _ensureSignedInAsUsername(normalizedCaller);
    _ensureVoiceRole(room, normalizedCaller, VoiceCallRole.caller);
    _ensureVoiceStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.accepted,
      VoiceCallSignalingStatus.negotiating,
    });
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}/status':
          VoiceCallSignalingStatus.negotiating.name,
      'voiceCalls/${room.callId}/offer': offer.toJson(
        maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
      ),
      'voiceCalls/${room.callId}/updatedAt': updatedAt,
      'voiceCallInboxes/${room.callee}/${room.callId}/status':
          VoiceCallSignalingStatus.negotiating.name,
      'voiceCallInboxes/${room.callee}/${room.callId}/updatedAt': updatedAt,
    });
  }

  @override
  Future<void> writeVoiceAnswer({
    required String callId,
    required String callee,
    required VoiceSignalingEnvelope answer,
    required int updatedAt,
  }) async {
    answer.validate(
      maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
    );
    final room = await _requireVoiceCall(callId);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    await _ensureSignedInAsUsername(normalizedCallee);
    _ensureVoiceRole(room, normalizedCallee, VoiceCallRole.callee);
    _ensureVoiceStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.negotiating,
    });
    if (room.offer == null) {
      throw const VoiceSignalingException(
        'Cannot write voice answer before offer.',
      );
    }
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}/answer': answer.toJson(
        maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
      ),
      'voiceCalls/${room.callId}/updatedAt': updatedAt,
    });
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceOffer(String callId) {
    final normalizedCallId = callId.trim();
    return _root
        .child('voiceCalls/$normalizedCallId/offer')
        .onValue
        .map((DatabaseEvent event) => event.snapshot.value)
        .where((Object? value) => value is Map)
        .map(
          (Object? value) => VoiceSignalingEnvelope.fromJson(
            _asObjectMap(value),
            maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
          ),
        );
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceAnswer(String callId) {
    final normalizedCallId = callId.trim();
    return _root
        .child('voiceCalls/$normalizedCallId/answer')
        .onValue
        .map((DatabaseEvent event) => event.snapshot.value)
        .where((Object? value) => value is Map)
        .map(
          (Object? value) => VoiceSignalingEnvelope.fromJson(
            _asObjectMap(value),
            maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
          ),
        );
  }

  @override
  Future<String> writeIceCandidate({
    required String callId,
    required String username,
    required VoiceCallRole role,
    required VoiceSignalingEnvelope candidate,
    required int createdAt,
  }) async {
    candidate.validate(
      maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength,
    );
    final room = await _requireVoiceCall(callId);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    await _ensureSignedInAsUsername(normalizedUsername);
    _ensureVoiceRole(room, normalizedUsername, role);
    _ensureVoiceStatus(room, const <VoiceCallSignalingStatus>{
      VoiceCallSignalingStatus.accepted,
      VoiceCallSignalingStatus.negotiating,
      VoiceCallSignalingStatus.connected,
    });
    final candidateRef = _root
        .child('voiceCalls/${room.callId}/${_voiceIcePath(role)}')
        .push();
    final candidateId = candidateRef.key;
    if (candidateId == null || candidateId.isEmpty) {
      throw const VoiceSignalingException(
        'Failed to allocate voice ICE candidate key.',
      );
    }
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}/${_voiceIcePath(role)}/$candidateId': candidate
          .toJson(
            maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength,
          ),
      'voiceCalls/${room.callId}/updatedAt': createdAt,
    });
    return candidateId;
  }

  @override
  Stream<VoiceCallIceCandidateRecord> watchIceCandidates({
    required String callId,
    required VoiceCallRole role,
  }) {
    final normalizedCallId = callId.trim();
    return _root
        .child('voiceCalls/$normalizedCallId/${_voiceIcePath(role)}')
        .onChildAdded
        .where((DatabaseEvent event) => event.snapshot.value is Map)
        .map(
          (DatabaseEvent event) => VoiceCallIceCandidateRecord.fromJson(
            callId: normalizedCallId,
            candidateId: event.snapshot.key ?? '',
            role: role,
            json: _asObjectMap(event.snapshot.value),
          ),
        );
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

  @override
  Future<void> deleteCall(String callId) async {
    await _configureEmulatorsIfNeeded();
    await ensureAuthenticated();
    final normalizedCallId = callId.trim();
    final room = await fetchCall(normalizedCallId);
    if (room == null) {
      await _root.child('voiceCalls/$normalizedCallId').remove();
      return;
    }
    await _removeActiveVoicePairLockForRoomIfCurrent(room);
    await _root.update(<String, Object?>{
      'voiceCalls/${room.callId}': null,
      'voiceCallInboxes/${room.callee}/${room.callId}': null,
    });
  }

  VoiceCallRoom? _voiceCallRoomFromSnapshot(String callId, Object? value) {
    if (value is! Map) {
      return null;
    }
    return VoiceCallRoom.fromJson(callId: callId, json: _asObjectMap(value));
  }

  Future<VoiceCallRoom> _requireVoiceCall(String callId) async {
    final room = await fetchCall(callId);
    if (room == null) {
      throw VoiceSignalingException('Unknown voice call: ${callId.trim()}');
    }
    return room;
  }

  void _ensureVoiceParticipant(VoiceCallRoom room, String username) {
    final normalizedUsername = normalizeVoiceCallUsername(username);
    if (normalizedUsername != room.caller &&
        normalizedUsername != room.callee) {
      throw VoiceSignalingException(
        '@$normalizedUsername is not a participant in ${room.callId}.',
      );
    }
  }

  void _ensureVoiceRole(
    VoiceCallRoom room,
    String username,
    VoiceCallRole role,
  ) {
    final normalizedUsername = normalizeVoiceCallUsername(username);
    final expectedUsername = voiceCallRoleUsername(room, role);
    if (normalizedUsername != expectedUsername) {
      throw VoiceSignalingException(
        '@$normalizedUsername cannot write ${role.name} signaling for ${room.callId}.',
      );
    }
  }

  void _ensureVoiceStatus(
    VoiceCallRoom room,
    Set<VoiceCallSignalingStatus> allowed,
  ) {
    if (!allowed.contains(room.status)) {
      throw VoiceSignalingException(
        'Voice call ${room.callId} is ${room.status.name}.',
      );
    }
  }

  void _ensureVoiceNonTerminal(VoiceCallRoom room) {
    if (room.status.isTerminal) {
      throw VoiceSignalingException('Voice call ${room.callId} already ended.');
    }
  }

  String _voiceIcePath(VoiceCallRole role) {
    return switch (role) {
      VoiceCallRole.caller => 'ice/caller',
      VoiceCallRole.callee => 'ice/callee',
    };
  }

  Map<Object?, Object?> _asObjectMap(Object? value) {
    if (value is Map<Object?, Object?>) {
      return value;
    }
    if (value is Map) {
      return Map<Object?, Object?>.from(value);
    }
    throw ArgumentError.value(value, 'value', 'Expected a JSON map');
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
