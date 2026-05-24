import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';

class FirebaseEmulatorSignalingAdapter
    implements SignalingAdapter, VoiceSignalingAdapter {
  FirebaseEmulatorSignalingAdapter({
    this.databaseNamespace = 'rain-8fb4b-default-rtdb',
    this.authHost = '127.0.0.1',
    this.authPort = 9099,
    this.databaseHost = '127.0.0.1',
    this.databasePort = 9000,
    SignalingCipher? signalingCipher,
  }) : _signalingCipher = signalingCipher ?? SignalingCipher.demo();

  final String databaseNamespace;
  final String authHost;
  final int authPort;
  final String databaseHost;
  final int databasePort;
  final SignalingCipher _signalingCipher;
  final HttpClient _client = HttpClient();
  final List<StreamController<dynamic>> _controllers =
      <StreamController<dynamic>>[];
  final List<Timer> _timers = <Timer>[];
  static const int _orphanVoiceLockGraceMs = 15000;
  final String _sessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(
    36,
  );

  String? _idToken;
  String? _uid;
  String? _email;
  int _pushCounter = 0;

  String _normalizedUsername(String username) {
    return username.trim().toLowerCase();
  }

  String _emailFromUsername(String username) {
    return '${_normalizedUsername(username)}@rain.local';
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
    if (_canonicalRoomId(parts[0], parts[1]) != roomId) {
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
      'expiresAt': timestamp + 15 * 60 * 1000,
    };
  }

  @override
  Future<void> ensureAuthenticated() async {
    if (_idToken == null || _uid == null) {
      throw const SignalingSessionExpiredException(
        'Firebase emulator sign-in required.',
      );
    }
  }

  @override
  Future<String> currentUid() async {
    await ensureAuthenticated();
    return _uid!;
  }

  @override
  Future<void> signOut() async {
    _idToken = null;
    _uid = null;
    _email = null;
  }

  @override
  Future<String> register(String username, String password) async {
    final normalizedUsername = _normalizedUsername(username);
    final response = await _authRequest('accounts:signUp', <String, Object?>{
      'email': _emailFromUsername(normalizedUsername),
      'password': password,
      'returnSecureToken': true,
    });
    _setAuth(response);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _put(
      <String>['users', normalizedUsername],
      <String, Object?>{
        'uid': _uid,
        'displayName': normalizedUsername,
        'gender': null,
        'registeredAt': now,
        'username': normalizedUsername,
      },
    );
    await _put(<String>['userSearch', normalizedUsername], true);
    await setPresence(normalizedUsername, true);
    return _uid!;
  }

  @override
  Future<String> login(String username, String password) async {
    final response =
        await _authRequest('accounts:signInWithPassword', <String, Object?>{
          'email': _emailFromUsername(username),
          'password': password,
          'returnSecureToken': true,
        });
    _setAuth(response);
    return _uid!;
  }

  void _setAuth(Map<String, Object?> response) {
    _idToken = response['idToken'] as String?;
    _uid = response['localId'] as String?;
    _email = (response['email'] as String?)?.toLowerCase();
    if (_idToken == null ||
        _uid == null ||
        _idToken!.isEmpty ||
        _uid!.isEmpty) {
      throw StateError('Firebase Auth emulator did not return a valid token.');
    }
  }

  Future<Map<String, Object?>> _authRequest(
    String method,
    Map<String, Object?> body,
  ) async {
    final uri = Uri.parse(
      'http://$authHost:$authPort/identitytoolkit.googleapis.com/v1/$method?key=fake-api-key',
    );
    final response = await _sendJson('POST', uri, body);
    if (response is! Map<String, Object?>) {
      throw StateError('Unexpected Auth emulator response: $response');
    }
    return response;
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
    await _patch(
      <String>['rooms', roomId],
      <String, Object?>{
        ..._roomParticipants(roomId),
        ..._roomLifecycle(
          roomId: roomId,
          timestamp: timestamp,
          newAttempt: true,
        ),
        'offer': encryptedOffer,
      },
    );
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
    await _patch(
      <String>['rooms', roomId],
      <String, Object?>{
        ..._roomParticipants(roomId),
        ..._roomLifecycle(roomId: roomId, timestamp: timestamp),
        'answer': encryptedAnswer,
      },
    );
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
    final purpose = role == IceRole.caller
        ? SignalingCipher.callerIcePurpose
        : SignalingCipher.calleeIcePurpose;
    final encryptedCandidate = await _signalingCipher.encryptPayload(
      roomId: roomId,
      purpose: purpose,
      timestamp: timestamp,
      payload: iceCandidateToJson(candidate),
    );
    final key = '${timestamp.toRadixString(36)}_${_pushCounter++}';
    await _put(<String>['rooms', roomId, path, key], encryptedCandidate);
  }

  @override
  Stream<SDPPayload> onOffer(String roomId) {
    return _pollValue<SDPPayload>(
      read: () async {
        final value = await _get(<String>['rooms', roomId, 'offer']);
        if (value is! Map) return null;
        final payload = await _signalingCipher.decryptPayload(
          roomId: roomId,
          purpose: SignalingCipher.offerPurpose,
          payload: _asObjectMap(value),
        );
        return SDPPayload.fromJson(payload);
      },
    );
  }

  @override
  Stream<SDPPayload> onAnswer(String roomId) {
    return _pollValue<SDPPayload>(
      read: () async {
        final value = await _get(<String>['rooms', roomId, 'answer']);
        if (value is! Map) return null;
        final payload = await _signalingCipher.decryptPayload(
          roomId: roomId,
          purpose: SignalingCipher.answerPurpose,
          payload: _asObjectMap(value),
        );
        return SDPPayload.fromJson(payload);
      },
    );
  }

  @override
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role) {
    final path = role == IceRole.caller ? 'callerICE' : 'calleeICE';
    final purpose = role == IceRole.caller
        ? SignalingCipher.callerIcePurpose
        : SignalingCipher.calleeIcePurpose;
    return _pollChildren<RTCIceCandidate>(
      <String>['rooms', roomId, path],
      parse: (Object? value, _) async {
        if (value is! Map) return null;
        final payload = await _signalingCipher.decryptPayload(
          roomId: roomId,
          purpose: purpose,
          payload: _asObjectMap(value),
        );
        return iceCandidateFromJson(payload);
      },
    );
  }

  @override
  Future<void> setPresence(String username, bool online) async {
    await _ensureSignedInAsUsername(username);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _patch(
      <String>['presence', _normalizedUsername(username)],
      {
        'uid': _uid,
        'online': online,
        'lastHeartbeat': now,
        'lastSeen': now,
        'updatedAt': now,
        'sessionId': _sessionId,
        'platform': 'flutter-test',
      },
    );
  }

  @override
  Future<void> sendHeartbeat(String username) async {
    await setPresence(username, true);
  }

  @override
  Stream<bool> watchPresence(String username) {
    return _pollValue<bool>(
      read: () async {
        final value = await _get(<String>[
          'presence',
          _normalizedUsername(username),
        ]);
        if (value is! Map) return false;
        return value['online'] == true;
      },
    );
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    await ensureAuthenticated();
    final value = await _get(<String>['users', _normalizedUsername(username)]);
    if (value is! Map) return true;
    return value['uid'] == _uid;
  }

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {
    await _ensureSignedInAsUsername(identity.username);
    await _patch(
      <String>['users', _normalizedUsername(identity.username)],
      {
        'uid': identity.uid,
        'displayName': identity.displayName,
        'gender': identity.gender,
        'registeredAt': identity.registeredAt,
        'username': _normalizedUsername(identity.username),
      },
    );
    await _put(<String>[
      'userSearch',
      _normalizedUsername(identity.username),
    ], true);
  }

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    final identity = await _get(<String>['users', normalizedUsername]);
    if (identity is! Map) return null;
    final presence = await _get(<String>['presence', normalizedUsername]);
    final presenceMap = presence is Map ? presence : const <Object?, Object?>{};
    return BackendIdentity(
      username: normalizedUsername,
      uid: identity['uid'] as String? ?? '',
      displayName: identity['displayName'] as String? ?? normalizedUsername,
      gender: identity['gender'] as String?,
      registeredAt: (identity['registeredAt'] as num?)?.toInt() ?? 0,
      lastSeen: (presenceMap['lastSeen'] as num?)?.toInt() ?? 0,
      lastHeartbeat: (presenceMap['lastHeartbeat'] as num?)?.toInt() ?? 0,
      online: presenceMap['online'] == true,
    );
  }

  @override
  Future<void> addToUserSearch(String username) async {
    await ensureAuthenticated();
    await _put(<String>['userSearch', _normalizedUsername(username)], true);
  }

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async {
    await ensureAuthenticated();
    if (query.length < 2) return const <BackendIdentity>[];
    final queryLower = query.toLowerCase();
    final value = await _get(<String>['userSearch']);
    if (value is! Map) return const <BackendIdentity>[];
    final matches = value.keys
        .whereType<String>()
        .where((String username) => username.startsWith(queryLower))
        .take(10);
    final identities = <BackendIdentity>[];
    for (final username in matches) {
      final identity = await fetchIdentity(username);
      if (identity != null) identities.add(identity);
    }
    return identities;
  }

  @override
  Future<void> writeFriendRequest(String to, String from) async {
    await _ensureSignedInAsUsername(from);
    final normalizedTo = _normalizedUsername(to);
    final normalizedFrom = _normalizedUsername(from);
    final payload = <String, Object?>{
      'sentAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _put(<String>[
      'friendRequests',
      normalizedTo,
      normalizedFrom,
    ], payload);
    await _put(<String>[
      'outgoingFriendRequests',
      normalizedFrom,
      normalizedTo,
    ], payload);
  }

  @override
  Future<void> deleteFriendRequest(String to, String from) async {
    await ensureAuthenticated();
    final normalizedTo = _normalizedUsername(to);
    final normalizedFrom = _normalizedUsername(from);
    await _delete(<String>['friendRequests', normalizedTo, normalizedFrom]);
    await _delete(<String>[
      'outgoingFriendRequests',
      normalizedFrom,
      normalizedTo,
    ]);
  }

  @override
  Future<List<String>> loadIncomingFriendRequests(String username) async {
    await ensureAuthenticated();
    return _keysAt(<String>['friendRequests', _normalizedUsername(username)]);
  }

  @override
  Future<List<String>> loadOutgoingFriendRequests(String username) async {
    await ensureAuthenticated();
    return _keysAt(<String>[
      'outgoingFriendRequests',
      _normalizedUsername(username),
    ]);
  }

  @override
  Future<List<String>> loadAcceptedFriends(String username) async {
    await ensureAuthenticated();
    return _keysAt(<String>['friendships', _normalizedUsername(username)]);
  }

  @override
  Future<List<String>> loadBlockedUsers(String username) async {
    await ensureAuthenticated();
    return _keysAt(<String>['blocks', _normalizedUsername(username)]);
  }

  @override
  Future<List<String>> loadUsersBlocking(String username) async {
    await ensureAuthenticated();
    return _keysAt(<String>['blockedBy', _normalizedUsername(username)]);
  }

  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) async {
    await _ensureSignedInAsUsername(firstUser);
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    final payload = <String, Object?>{
      'acceptedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _put(<String>[
      'friendships',
      normalizedFirstUser,
      normalizedSecondUser,
    ], payload);
    await _put(<String>[
      'friendships',
      normalizedSecondUser,
      normalizedFirstUser,
    ], payload);
    await deleteFriendRequest(normalizedFirstUser, normalizedSecondUser);
    await deleteFriendRequest(normalizedSecondUser, normalizedFirstUser);
  }

  @override
  Future<void> deleteFriendship(String firstUser, String secondUser) async {
    await ensureAuthenticated();
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    await _delete(<String>[
      'friendships',
      normalizedFirstUser,
      normalizedSecondUser,
    ]);
    await _delete(<String>[
      'friendships',
      normalizedSecondUser,
      normalizedFirstUser,
    ]);
    await deleteFriendRequest(normalizedFirstUser, normalizedSecondUser);
    await deleteFriendRequest(normalizedSecondUser, normalizedFirstUser);
  }

  @override
  Future<void> blockUser(String blocker, String blocked) async {
    await _ensureSignedInAsUsername(blocker);
    final normalizedBlocker = _normalizedUsername(blocker);
    final normalizedBlocked = _normalizedUsername(blocked);
    final payload = <String, Object?>{
      'blockedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _put(<String>[
      'blocks',
      normalizedBlocker,
      normalizedBlocked,
    ], payload);
    await _put(<String>[
      'blockedBy',
      normalizedBlocked,
      normalizedBlocker,
    ], payload);
    await deleteFriendship(normalizedBlocker, normalizedBlocked);
  }

  @override
  Future<void> unblockUser(String blocker, String blocked) async {
    await _ensureSignedInAsUsername(blocker);
    final normalizedBlocker = _normalizedUsername(blocker);
    final normalizedBlocked = _normalizedUsername(blocked);
    await _delete(<String>['blocks', normalizedBlocker, normalizedBlocked]);
    await _delete(<String>['blockedBy', normalizedBlocked, normalizedBlocker]);
  }

  @override
  Stream<String> onFriendRequest(String username) {
    return _pollChildren<String>(<String>[
      'friendRequests',
      _normalizedUsername(username),
    ], parse: (_, String key) async => key);
  }

  @override
  Stream<String> onRelationshipChanged(String username) {
    final normalizedUsername = _normalizedUsername(username);
    return _pollValue<Set<String>>(
      read: () async {
        final keys = <String>{};
        for (final path in <List<String>>[
          <String>['friendships', normalizedUsername],
          <String>['friendRequests', normalizedUsername],
          <String>['outgoingFriendRequests', normalizedUsername],
          <String>['blocks', normalizedUsername],
          <String>['blockedBy', normalizedUsername],
        ]) {
          keys.addAll(await _keysAt(path));
        }
        return keys;
      },
    ).asyncExpand(
      (Set<String> usernames) => Stream<String>.fromIterable(usernames),
    );
  }

  @override
  Future<void> deleteRoom(String roomId) async {
    await ensureAuthenticated();
    await _delete(<String>['rooms', roomId]);
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
    final normalizedCallId = callId.trim();
    final normalizedCaller = normalizeVoiceCallUsername(caller);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    await _ensureSignedInAsUsername(normalizedCaller);
    final pairId = voiceCallPairId(normalizedCaller, normalizedCallee);
    final existingLockValue = await _get(<String>['activeVoicePairs', pairId]);
    if (existingLockValue is Map &&
        !await _reclaimActiveVoicePairLockIfStale(
          pairId: pairId,
          value: existingLockValue,
          caller: normalizedCaller,
          createdAt: createdAt,
        )) {
      throw VoiceSignalingException(
        'Active voice call already exists for pair $pairId.',
      );
    }
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
    await _put(<String>['activeVoicePairs', pairId], lock.toJson());
    try {
      await _patch(<String>[], <String, Object?>{
        'voiceCalls/$normalizedCallId': room.toJson(),
        'voiceCallInboxes/$normalizedCallee/$normalizedCallId': inbox.toJson(),
      });
    } catch (_) {
      await _delete(<String>['activeVoicePairs', pairId]);
      rethrow;
    }
    return room;
  }

  @override
  Future<VoiceCallRoom?> fetchCall(String callId) async {
    await ensureAuthenticated();
    return _voiceCallRoomFromValue(
      callId.trim(),
      await _get(<String>['voiceCalls', callId.trim()]),
    );
  }

  @override
  Stream<VoiceCallRoom?> watchCall(String callId) {
    final normalizedCallId = callId.trim();
    return _pollValue<VoiceCallRoom?>(
      read: () async => _voiceCallRoomFromValue(
        normalizedCallId,
        await _get(<String>['voiceCalls', normalizedCallId]),
      ),
    );
  }

  @override
  Stream<VoiceCallInboxEntry> watchIncomingCalls(String username) {
    return _pollChildren<VoiceCallInboxEntry>(
      <String>['voiceCallInboxes', normalizeVoiceCallUsername(username)],
      parse: (Object? value, String key) async {
        if (value is! Map) return null;
        return VoiceCallInboxEntry.fromJson(
          callId: key,
          json: _asObjectMap(value),
        );
      },
    );
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
    await _patch(<String>[], <String, Object?>{
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
    await _patch(<String>[], <String, Object?>{
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
    final room = await _requireVoiceCall(callId);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    await _ensureSignedInAsUsername(normalizedUsername);
    _ensureVoiceParticipant(room, normalizedUsername);
    if (room.status.isTerminal) {
      await _deleteActiveVoicePairLockForRoomIfCurrent(room);
      return;
    }
    await _patch(<String>[], <String, Object?>{
      'voiceCalls/${room.callId}/status': status.name,
      'voiceCalls/${room.callId}/endedAt': endedAt,
      'voiceCalls/${room.callId}/endedBy': normalizedUsername,
      'voiceCalls/${room.callId}/updatedAt': endedAt,
      'voiceCalls/${room.callId}/reasonCode': reasonCode,
      'voiceCalls/${room.callId}/reason': reason,
      'voiceCallInboxes/${room.callee}/${room.callId}/status': status.name,
      'voiceCallInboxes/${room.callee}/${room.callId}/updatedAt': endedAt,
    });
    await _deleteActiveVoicePairLockForRoomIfCurrent(room);
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
    await _patch(<String>[], <String, Object?>{
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
    await _patch(<String>[], <String, Object?>{
      'voiceCalls/${room.callId}/cameraMuted/$normalizedUsername': cameraMuted,
      'voiceCalls/${room.callId}/updatedAt': updatedAt,
    });
  }

  @override
  Future<void> writeVoiceOffer({
    required String callId,
    required String caller,
    required VoiceSignalingEnvelope offer,
    required int updatedAt,
  }) async {
    final room = await _requireVoiceCall(callId);
    final normalizedCaller = normalizeVoiceCallUsername(caller);
    await _ensureSignedInAsUsername(normalizedCaller);
    _ensureVoiceRole(room, normalizedCaller, VoiceCallRole.caller);
    await _patch(<String>[], <String, Object?>{
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
    final room = await _requireVoiceCall(callId);
    final normalizedCallee = normalizeVoiceCallUsername(callee);
    await _ensureSignedInAsUsername(normalizedCallee);
    _ensureVoiceRole(room, normalizedCallee, VoiceCallRole.callee);
    await _patch(<String>[], <String, Object?>{
      'voiceCalls/${room.callId}/answer': answer.toJson(
        maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
      ),
      'voiceCalls/${room.callId}/updatedAt': updatedAt,
    });
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceOffer(String callId) {
    final normalizedCallId = callId.trim();
    return _pollValue<VoiceSignalingEnvelope>(
      read: () async => _voiceEnvelopeFromValue(
        await _get(<String>['voiceCalls', normalizedCallId, 'offer']),
        maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
      ),
    );
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceAnswer(String callId) {
    final normalizedCallId = callId.trim();
    return _pollValue<VoiceSignalingEnvelope>(
      read: () async => _voiceEnvelopeFromValue(
        await _get(<String>['voiceCalls', normalizedCallId, 'answer']),
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
    final room = await _requireVoiceCall(callId);
    final normalizedUsername = normalizeVoiceCallUsername(username);
    await _ensureSignedInAsUsername(normalizedUsername);
    _ensureVoiceRole(room, normalizedUsername, role);
    final candidateId = '${createdAt.toRadixString(36)}_${_pushCounter++}';
    await _patch(<String>[], <String, Object?>{
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
    return _pollChildren<VoiceCallIceCandidateRecord>(
      <String>[
        'voiceCalls',
        normalizedCallId,
        ..._voiceIcePath(role).split('/'),
      ],
      parse: (Object? value, String key) async {
        if (value is! Map) return null;
        return VoiceCallIceCandidateRecord.fromJson(
          callId: normalizedCallId,
          candidateId: key,
          role: role,
          json: _asObjectMap(value),
        );
      },
    );
  }

  @override
  Future<void> deleteCall(String callId) async {
    final room = await fetchCall(callId);
    if (room == null) {
      await _delete(<String>['voiceCalls', callId.trim()]);
      return;
    }
    await _deleteActiveVoicePairLockForRoomIfCurrent(room);
    await _patch(<String>[], <String, Object?>{
      'voiceCalls/${room.callId}': null,
      'voiceCallInboxes/${room.callee}/${room.callId}': null,
    });
  }

  @override
  Future<void> dispose() async {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    for (final controller in _controllers) {
      await controller.close();
    }
    _controllers.clear();
    _client.close(force: true);
  }

  Future<List<String>> _keysAt(List<String> path) async {
    final value = await _get(path);
    if (value is! Map) return const <String>[];
    return value.keys.whereType<String>().toList(growable: false);
  }

  VoiceCallRoom? _voiceCallRoomFromValue(String callId, Object? value) {
    if (value is! Map) return null;
    return VoiceCallRoom.fromJson(callId: callId, json: _asObjectMap(value));
  }

  Future<bool> _reclaimActiveVoicePairLockIfStale({
    required String pairId,
    required Map<dynamic, dynamic> value,
    required String caller,
    required int createdAt,
  }) async {
    final VoiceActivePairLock lock;
    try {
      lock = VoiceActivePairLock.fromJson(
        pairId: pairId,
        json: _asObjectMap(value),
      );
    } catch (_) {
      return false;
    }
    if (lock.expiresAt <= createdAt) {
      await _delete(<String>['activeVoicePairs', pairId]);
      final room = await fetchCall(lock.callId);
      if (room != null && _shouldDeleteReclaimedVoiceRoom(room, createdAt)) {
        await _deleteVoiceCallRoomArtifacts(room);
      }
      return true;
    }

    final room = await fetchCall(lock.callId);
    if (room == null) {
      if (lock.caller == normalizeVoiceCallUsername(caller)) {
        await _delete(<String>['activeVoicePairs', pairId]);
        return true;
      }
      if (createdAt - lock.updatedAt < _orphanVoiceLockGraceMs) {
        return false;
      }
      await _delete(<String>['activeVoicePairs', pairId]);
      return true;
    }

    final setupExpired =
        room.status != VoiceCallSignalingStatus.connected &&
        room.expiresAt <= createdAt;
    if (!room.isTerminal && !setupExpired) {
      return false;
    }

    await _delete(<String>['activeVoicePairs', pairId]);
    await _deleteVoiceCallRoomArtifacts(room);
    return true;
  }

  Future<void> _deleteActiveVoicePairLockForRoomIfCurrent(
    VoiceCallRoom room,
  ) async {
    final value = await _get(<String>['activeVoicePairs', room.pairId]);
    if (value is! Map) {
      return;
    }
    final lock = VoiceActivePairLock.fromJson(
      pairId: room.pairId,
      json: _asObjectMap(value),
    );
    if (lock.callId == room.callId) {
      await _delete(<String>['activeVoicePairs', room.pairId]);
    }
  }

  bool _shouldDeleteReclaimedVoiceRoom(VoiceCallRoom room, int createdAt) {
    if (room.isTerminal) {
      return true;
    }
    return room.status != VoiceCallSignalingStatus.connected &&
        room.expiresAt <= createdAt;
  }

  Future<void> _deleteVoiceCallRoomArtifacts(VoiceCallRoom room) async {
    await _patch(<String>[], <String, Object?>{
      'voiceCalls/${room.callId}': null,
      'voiceCallInboxes/${room.callee}/${room.callId}': null,
    });
  }

  VoiceSignalingEnvelope? _voiceEnvelopeFromValue(
    Object? value, {
    required int maxCiphertextLength,
  }) {
    if (value is! Map) return null;
    return VoiceSignalingEnvelope.fromJson(
      _asObjectMap(value),
      maxCiphertextLength: maxCiphertextLength,
    );
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

  String _voiceIcePath(VoiceCallRole role) {
    return switch (role) {
      VoiceCallRole.caller => 'ice/caller',
      VoiceCallRole.callee => 'ice/callee',
    };
  }

  Future<void> _ensureSignedInAsUsername(String username) async {
    await ensureAuthenticated();
    final expectedEmail = _emailFromUsername(username);
    if (_email != expectedEmail) {
      throw SignalingSessionExpiredException(
        'Firebase emulator is signed in as ${_email ?? 'another account'}; expected @$username.',
      );
    }
  }

  Stream<T> _pollValue<T>({
    required Future<T?> Function() read,
    Duration interval = const Duration(milliseconds: 75),
  }) {
    late final StreamController<T> controller;
    String? lastMarker;
    var running = false;

    Future<void> tick() async {
      if (running || controller.isClosed) return;
      running = true;
      try {
        final value = await read();
        if (value == null) return;
        final marker = _markerFor(value);
        if (marker == lastMarker) return;
        lastMarker = marker;
        controller.add(value);
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        running = false;
      }
    }

    controller = StreamController<T>.broadcast(
      onListen: () {
        unawaited(tick());
        final timer = Timer.periodic(interval, (_) => unawaited(tick()));
        _timers.add(timer);
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }

  Stream<T> _pollChildren<T>(
    List<String> path, {
    required Future<T?> Function(Object? value, String key) parse,
    Duration interval = const Duration(milliseconds: 75),
  }) {
    late final StreamController<T> controller;
    final seen = <String>{};
    var running = false;

    Future<void> tick() async {
      if (running || controller.isClosed) return;
      running = true;
      try {
        final value = await _get(path);
        if (value is! Map) return;
        final keys = value.keys.whereType<String>().toList()..sort();
        for (final key in keys) {
          if (!seen.add(key)) continue;
          final parsed = await parse(value[key], key);
          if (parsed != null && !controller.isClosed) {
            controller.add(parsed);
          }
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        running = false;
      }
    }

    controller = StreamController<T>.broadcast(
      onListen: () {
        unawaited(tick());
        final timer = Timer.periodic(interval, (_) => unawaited(tick()));
        _timers.add(timer);
      },
    );
    _controllers.add(controller);
    return controller.stream;
  }

  Map<Object?, Object?> _asObjectMap(Object? value) {
    if (value is! Map) {
      throw ArgumentError.value(value, 'value', 'Expected a JSON map');
    }
    return Map<Object?, Object?>.from(value);
  }

  String _markerFor(Object value) {
    if (value is Set) {
      final items = value.map((Object? item) => item.toString()).toList()
        ..sort();
      return jsonEncode(items);
    }
    if (value is Iterable) {
      return jsonEncode(value.map((Object? item) => item.toString()).toList());
    }
    return value.toString();
  }

  Future<Object?> _get(List<String> path) {
    return _databaseRequest('GET', path);
  }

  Future<void> _put(List<String> path, Object? body) async {
    await _databaseRequest('PUT', path, body: body);
  }

  Future<void> _patch(List<String> path, Map<String, Object?> body) async {
    await _databaseRequest('PATCH', path, body: body);
  }

  Future<void> _delete(List<String> path) async {
    await _databaseRequest('DELETE', path);
  }

  Future<Object?> _databaseRequest(
    String method,
    List<String> path, {
    Object? body,
  }) async {
    await ensureAuthenticated();
    final encodedPath = path.map(Uri.encodeComponent).join('/');
    final uri =
        Uri.parse(
          'http://$databaseHost:$databasePort/$encodedPath.json',
        ).replace(
          queryParameters: <String, String>{
            'ns': databaseNamespace,
            'auth': _idToken!,
          },
        );
    return _sendJson(method, uri, body);
  }

  Future<Object?> _sendJson(String method, Uri uri, Object? body) async {
    final request = await _client.openUrl(method, uri);
    request.headers.contentType = ContentType.json;
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 400) {
      throw HttpException(
        'HTTP ${response.statusCode} from $uri: ${decoded ?? text}',
        uri: uri,
      );
    }
    return decoded;
  }
}
