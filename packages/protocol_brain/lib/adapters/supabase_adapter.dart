import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../src/iroh_signaling.dart';
import 'signaling_adapter.dart';
import 'signaling_cipher.dart';
import 'supabase_auth_alias.dart';
import 'supabase_auth_error.dart';
import 'supabase_identity_error.dart';

class SupabaseSignalingAdapter implements SignalingAdapter {
  SupabaseSignalingAdapter({
    required String projectUrl,
    SupabaseClient? client,
    SignalingCipher? signalingCipher,
  }) : _projectUrl = projectUrl,
       _client = client ?? Supabase.instance.client,
       _signalingCipher = signalingCipher ?? SignalingCipher.demo();

  final SupabaseClient _client;
  final String _projectUrl;
  final SignalingCipher _signalingCipher;
  static const int _presenceTimeoutMs = 90 * 1000;

  @override
  Future<void> deleteRoom(String roomId) async {
    await ensureAuthenticated();
    await _client.from('rooms').delete().eq('room_id', roomId);
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> ensureAuthenticated() async {
    if (_client.auth.currentSession == null) {
      throw Exception('Supabase session is missing. Sign in again.');
    }
  }

  @override
  Future<String> currentUid() async {
    await ensureAuthenticated();
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw Exception('Supabase user id is unavailable.');
    }
    return uid;
  }

  @override
  Future<void> signOut() {
    return _client.auth.signOut();
  }

  List<String> _loginEmailsFromUsername(String username) {
    return supabaseLoginEmailsFromUsername(username, projectUrl: _projectUrl);
  }

  Future<String> _signInWithEmail(String email, String password) async {
    final authResponse = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final uid = authResponse.user?.id ?? _client.auth.currentUser?.id ?? '';
    if (uid.isEmpty) {
      throw Exception('Failed to authenticate Supabase user');
    }
    return uid;
  }

  String _canonicalRoomId(String firstUser, String secondUser) {
    final users = <String>[firstUser, secondUser]..sort();
    return users.join(':');
  }

  List<String> _canonicalUserPair(String firstUser, String secondUser) {
    final users = <String>[firstUser, secondUser]..sort();
    return users;
  }

  Future<String> _currentUsername() async {
    final uid = await currentUid();
    final rows =
        (await _client.from('users').select('username').eq('uid', uid).limit(1))
            as List<dynamic>;
    if (rows.isEmpty) {
      throw Exception('Supabase user identity is missing.');
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    final username = row['username'] as String? ?? '';
    if (username.isEmpty) {
      throw Exception('Supabase username is unavailable.');
    }
    return username;
  }

  String _normalizedUsername(String username) {
    return username.trim().toLowerCase();
  }

  bool _isMissingFriendshipsTableError(Object error) {
    if (error is! PostgrestException || error.code != 'PGRST205') {
      return false;
    }
    final combined =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    return combined.contains('friendships');
  }

  bool _isMissingUserBlocksTableError(Object error) {
    if (error is! PostgrestException || error.code != 'PGRST205') {
      return false;
    }
    final combined =
        '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
            .toLowerCase();
    return combined.contains('user_blocks');
  }

  Future<void> _deleteFriendRequestsForPair(
    String firstUser,
    String secondUser,
  ) async {
    await deleteFriendRequest(firstUser, secondUser);
    await deleteFriendRequest(secondUser, firstUser);
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
    return <String, Object?>{'user_a': users[0], 'user_b': users[1]};
  }

  bool _isFreshPresence(bool online, int lastHeartbeat) {
    final age = DateTime.now().millisecondsSinceEpoch - lastHeartbeat;
    return online && age < _presenceTimeoutMs;
  }

  Exception _normalizeFriendRequestWriteError(
    Object error, {
    required String to,
    required String from,
  }) {
    if (error is! PostgrestException || error.code != '23503') {
      return Exception(error.toString());
    }

    final details = '${error.details ?? ''}'.toLowerCase();
    if (details.contains('friend_requests_to_user_fkey')) {
      return Exception(
        'User "@$to" was not found. Ask them to create an account first.',
      );
    }
    if (details.contains('friend_requests_from_user_fkey')) {
      return Exception(
        'Your Rain identity is missing from Supabase. Sign out and sign in again before sending friend requests.',
      );
    }

    return Exception(
      'Rain could not send the friend request from "@$from" to "@$to".',
    );
  }

  @override
  Future<String> register(String username, String password) async {
    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    final email = supabasePreferredEmailFromUsername(
      username,
      projectUrl: _projectUrl,
    );
    try {
      final authResponse = await _client.auth.signUp(
        email: email,
        password: password,
      );
      final uid = authResponse.user?.id ?? _client.auth.currentUser?.id ?? '';
      if (uid.isEmpty) {
        throw Exception('Failed to authenticate Supabase user');
      }
      final now = DateTime.now().millisecondsSinceEpoch;

      await _client.from('users').upsert({
        'username': username,
        'uid': uid,
        'display_name': username,
        'gender': null,
        'registered_at': now,
        'last_seen': now,
        'last_heartbeat': now,
        'online': true,
      });

      if (_client.auth.currentSession == null) {
        await _client.auth.signInWithPassword(email: email, password: password);
      }

      return uid;
    } catch (error) {
      throw normalizeSupabaseAuthError(error, duringRegistration: true);
    }
  }

  @override
  Future<String> login(String username, String password) async {
    Object? lastError;
    for (final email in _loginEmailsFromUsername(username)) {
      try {
        return await _signInWithEmail(email, password);
      } catch (error) {
        lastError = error;
      }
    }
    throw normalizeSupabaseAuthError(
      lastError ?? Exception('Failed to authenticate Supabase user'),
      duringRegistration: false,
    );
  }

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async {
    final rows =
        (await _client.from('users').select().eq('username', username).limit(1))
            as List<dynamic>;
    if (rows.isEmpty) {
      return null;
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    final lastHeartbeat = (row['last_heartbeat'] as num?)?.toInt() ?? 0;
    return BackendIdentity(
      username: row['username'] as String,
      uid: row['uid'] as String? ?? '',
      displayName: row['display_name'] as String? ?? row['username'] as String,
      gender: row['gender'] as String?,
      registeredAt: (row['registered_at'] as num?)?.toInt() ?? 0,
      lastSeen: (row['last_seen'] as num?)?.toInt() ?? 0,
      lastHeartbeat: lastHeartbeat,
      online: _isFreshPresence(row['online'] as bool? ?? false, lastHeartbeat),
    );
  }

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async {
    if (query.length < 2) {
      return [];
    }

    final rows = await _client
        .from('users')
        .select()
        .ilike('username', '%$query%')
        .limit(10);

    final result = <BackendIdentity>[];
    for (final row in rows as List<dynamic>) {
      final map = Map<String, dynamic>.from(row as Map);
      final lastHeartbeat = (map['last_heartbeat'] as num?)?.toInt() ?? 0;
      result.add(
        BackendIdentity(
          username: map['username'] as String,
          uid: map['uid'] as String? ?? '',
          displayName:
              map['display_name'] as String? ?? map['username'] as String,
          gender: map['gender'] as String?,
          registeredAt: (map['registered_at'] as num?)?.toInt() ?? 0,
          lastSeen: (map['last_seen'] as num?)?.toInt() ?? 0,
          lastHeartbeat: lastHeartbeat,
          online: _isFreshPresence(
            map['online'] as bool? ?? false,
            lastHeartbeat,
          ),
        ),
      );
    }
    return result;
  }

  @override
  Future<void> addToUserSearch(String username) async {
    await ensureAuthenticated();
  }

  @override
  Future<void> deleteFriendRequest(String to, String from) async {
    await ensureAuthenticated();
    final normalizedTo = _normalizedUsername(to);
    final normalizedFrom = _normalizedUsername(from);
    await _client
        .from('friend_requests')
        .delete()
        .eq('from_user', normalizedFrom)
        .eq('to_user', normalizedTo);
  }

  @override
  Future<void> deleteFriendship(String firstUser, String secondUser) async {
    await ensureAuthenticated();
    final users = _canonicalUserPair(
      _normalizedUsername(firstUser),
      _normalizedUsername(secondUser),
    );
    try {
      await _client
          .from('friendships')
          .delete()
          .eq('user_a', users[0])
          .eq('user_b', users[1]);
    } catch (error) {
      if (!_isMissingFriendshipsTableError(error)) {
        rethrow;
      }
    }
    await _deleteFriendRequestsForPair(users[0], users[1]);
  }

  @override
  Future<List<String>> loadAcceptedFriends(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    try {
      final rows = await _client
          .from('friendships')
          .select('user_a, user_b')
          .or('user_a.eq.$normalizedUsername,user_b.eq.$normalizedUsername');

      final friends = <String>[];
      for (final row in rows as List<dynamic>) {
        final map = Map<String, dynamic>.from(row as Map);
        final userA = map['user_a'] as String?;
        final userB = map['user_b'] as String?;
        if (userA == null || userB == null) {
          continue;
        }
        friends.add(userA == normalizedUsername ? userB : userA);
      }
      return friends.toSet().toList(growable: false);
    } catch (error) {
      if (!_isMissingFriendshipsTableError(error)) {
        rethrow;
      }
    }

    final incoming = await loadIncomingFriendRequests(normalizedUsername);
    final outgoing = await loadOutgoingFriendRequests(normalizedUsername);
    return incoming
        .toSet()
        .intersection(outgoing.toSet())
        .toList(growable: false);
  }

  @override
  Future<List<String>> loadBlockedUsers(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    try {
      final rows = await _client
          .from('user_blocks')
          .select('blocked')
          .eq('blocker', normalizedUsername);
      return (rows as List<dynamic>)
          .map((dynamic row) => Map<String, dynamic>.from(row as Map))
          .map((Map<String, dynamic> row) => row['blocked'] as String?)
          .whereType<String>()
          .toList(growable: false);
    } catch (error) {
      if (_isMissingUserBlocksTableError(error)) {
        return const <String>[];
      }
      rethrow;
    }
  }

  @override
  Future<List<String>> loadUsersBlocking(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    try {
      final rows = await _client
          .from('user_blocks')
          .select('blocker')
          .eq('blocked', normalizedUsername);
      return (rows as List<dynamic>)
          .map((dynamic row) => Map<String, dynamic>.from(row as Map))
          .map((Map<String, dynamic> row) => row['blocker'] as String?)
          .whereType<String>()
          .toList(growable: false);
    } catch (error) {
      if (_isMissingUserBlocksTableError(error)) {
        return const <String>[];
      }
      rethrow;
    }
  }

  @override
  Future<List<String>> loadIncomingFriendRequests(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    final rows = await _client
        .from('friend_requests')
        .select('from_user')
        .eq('to_user', normalizedUsername);

    return (rows as List<dynamic>)
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .map((Map<String, dynamic> row) => row['from_user'] as String?)
        .whereType<String>()
        .toList(growable: false);
  }

  @override
  Future<List<String>> loadOutgoingFriendRequests(String username) async {
    await ensureAuthenticated();
    final normalizedUsername = _normalizedUsername(username);
    final rows = await _client
        .from('friend_requests')
        .select('to_user')
        .eq('from_user', normalizedUsername);

    return (rows as List<dynamic>)
        .map((dynamic row) => Map<String, dynamic>.from(row as Map))
        .map((Map<String, dynamic> row) => row['to_user'] as String?)
        .whereType<String>()
        .toList(growable: false);
  }

  @override
  Future<bool> isUsernameAvailable(String username) async {
    await ensureAuthenticated();
    final rows =
        (await _client
                .from('users')
                .select('username, uid')
                .eq('username', username))
            as List<dynamic>;
    if (rows.isEmpty) {
      return true;
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    return row['uid'] == _client.auth.currentUser?.id;
  }

  @override
  Stream<SDPPayload> onAnswer(String roomId) {
    int? lastTs;
    return _client
        .from('rooms')
        .stream(primaryKey: <String>['room_id'])
        .eq('room_id', roomId)
        .asyncExpand((List<Map<String, dynamic>> rows) async* {
          if (rows.isEmpty) {
            return;
          }
          final raw = rows.first['answer'];
          if (raw is! Map) {
            return;
          }
          final decrypted = await _signalingCipher.decryptPayload(
            roomId: roomId,
            purpose: SignalingCipher.answerPurpose,
            payload: Map<Object?, Object?>.from(raw),
          );
          final payload = SDPPayload.fromJson(decrypted);
          if (payload.ts == lastTs) {
            return;
          }
          lastTs = payload.ts;
          yield payload;
        });
  }

  @override
  Stream<String> onFriendRequest(String username) {
    final seen = <String>{};
    return _client
        .from('friend_requests')
        .stream(primaryKey: <String>['from_user', 'to_user'])
        .eq('to_user', username)
        .expand((List<Map<String, dynamic>> rows) sync* {
          for (final row in rows) {
            final from = row['from_user'] as String?;
            final to = row['to_user'] as String?;
            final sentAt = (row['sent_at'] as num?)?.toInt() ?? 0;
            if (from == null || to != username) {
              continue;
            }
            final key = '$from:$to:$sentAt';
            if (seen.add(key)) {
              yield from;
            }
          }
        });
  }

  @override
  Stream<String> onRelationshipChanged(String username) {
    final normalizedUsername = _normalizedUsername(username);
    late final StreamController<String> controller;
    final subscriptions = <StreamSubscription<List<Map<String, dynamic>>>>[];

    void emit(String peerUsername) {
      if (peerUsername.isNotEmpty &&
          peerUsername != normalizedUsername &&
          !controller.isClosed) {
        controller.add(peerUsername);
      }
    }

    controller = StreamController<String>.broadcast(
      onListen: () {
        subscriptions.add(
          _client
              .from('friend_requests')
              .stream(primaryKey: <String>['from_user', 'to_user'])
              .listen((List<Map<String, dynamic>> rows) {
                for (final row in rows) {
                  final from = row['from_user'] as String?;
                  final to = row['to_user'] as String?;
                  if (to == normalizedUsername && from != null) {
                    emit(from);
                  } else if (from == normalizedUsername && to != null) {
                    emit(to);
                  }
                }
              }),
        );
        subscriptions.add(
          _client
              .from('friendships')
              .stream(primaryKey: <String>['user_a', 'user_b'])
              .listen((List<Map<String, dynamic>> rows) {
                for (final row in rows) {
                  final userA = row['user_a'] as String?;
                  final userB = row['user_b'] as String?;
                  if (userA == normalizedUsername && userB != null) {
                    emit(userB);
                  } else if (userB == normalizedUsername && userA != null) {
                    emit(userA);
                  }
                }
              }),
        );
        subscriptions.add(
          _client
              .from('user_blocks')
              .stream(primaryKey: <String>['blocker', 'blocked'])
              .listen((List<Map<String, dynamic>> rows) {
                for (final row in rows) {
                  final blocker = row['blocker'] as String?;
                  final blocked = row['blocked'] as String?;
                  if (blocker == normalizedUsername && blocked != null) {
                    emit(blocked);
                  } else if (blocked == normalizedUsername && blocker != null) {
                    emit(blocker);
                  }
                }
              }),
        );
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
  Stream<IceCandidatePayload> onICE(String roomId, IceRole role) {
    final field = role == IceRole.caller ? 'caller_ice' : 'callee_ice';
    final purpose = role == IceRole.caller
        ? SignalingCipher.callerIcePurpose
        : SignalingCipher.calleeIcePurpose;
    final seen = <String>{};
    return _client
        .from('rooms')
        .stream(primaryKey: <String>['room_id'])
        .eq('room_id', roomId)
        .asyncExpand((List<Map<String, dynamic>> rows) async* {
          if (rows.isEmpty) {
            return;
          }
          final raw = rows.first[field];
          final values = raw is List ? raw.whereType<Map>() : const <Map>[];
          for (final rawValue in values) {
            final value = Map<Object?, Object?>.from(rawValue);
            final key = SignalingCipher.isEncryptedEnvelope(value)
                ? '${value['ts']}:${value['nonce']}:${value['mac']}'
                : '${value['candidate']}:${value['sdpMid']}:${value['sdpMLineIndex']}';
            if (seen.add(key)) {
              final decrypted = await _signalingCipher.decryptPayload(
                roomId: roomId,
                purpose: purpose,
                payload: value,
              );
              yield IceCandidatePayload.fromJson(decrypted);
            }
          }
        });
  }

  @override
  Stream<IrohAddressPayload> onIrohAddress(String roomId) {
    return const Stream<IrohAddressPayload>.empty();
  }

  @override
  Stream<SDPPayload> onOffer(String roomId) {
    int? lastTs;
    return _client
        .from('rooms')
        .stream(primaryKey: <String>['room_id'])
        .eq('room_id', roomId)
        .asyncExpand((List<Map<String, dynamic>> rows) async* {
          if (rows.isEmpty) {
            return;
          }
          final raw = rows.first['offer'];
          if (raw is! Map) {
            return;
          }
          final decrypted = await _signalingCipher.decryptPayload(
            roomId: roomId,
            purpose: SignalingCipher.offerPurpose,
            payload: Map<Object?, Object?>.from(raw),
          );
          final payload = SDPPayload.fromJson(decrypted);
          if (payload.ts == lastTs) {
            return;
          }
          lastTs = payload.ts;
          yield payload;
        });
  }

  @override
  Future<void> setPresence(String username, bool online) async {
    await ensureAuthenticated();
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await fetchIdentity(username);
    await _client.from('users').upsert(<String, Object?>{
      'username': username,
      'display_name': existing?.displayName ?? username,
      'online': online,
      'registered_at': existing?.registeredAt ?? now,
      'last_seen': now,
      'last_heartbeat': now,
      'uid': _client.auth.currentUser?.id ?? existing?.uid ?? '',
      'gender': existing?.gender,
    });
  }

  @override
  Future<void> sendHeartbeat(String username) async {
    await ensureAuthenticated();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _client
        .from('users')
        .update(<String, Object?>{
          'online': true,
          'last_heartbeat': now,
          'last_seen': now,
        })
        .eq('username', username);
  }

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {
    await ensureAuthenticated();
    try {
      await _client.from('users').upsert(identity.toSupabaseJson());
    } catch (error) {
      throw normalizeSupabaseIdentityWriteError(
        error,
        username: identity.username,
      );
    }
  }

  @override
  Stream<bool> watchPresence(String username) {
    final controller = StreamController<bool>.broadcast();
    Timer? expiryTimer;
    bool? lastEmitted;

    void emitPresence(bool online, int lastHeartbeat) {
      expiryTimer?.cancel();
      expiryTimer = null;
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiresIn = _presenceTimeoutMs - (now - lastHeartbeat);
      final freshOnline = online && expiresIn > 0;
      if (lastEmitted != freshOnline && !controller.isClosed) {
        lastEmitted = freshOnline;
        controller.add(freshOnline);
      }
      if (freshOnline) {
        expiryTimer = Timer(Duration(milliseconds: expiresIn), () {
          emitPresence(online, lastHeartbeat);
        });
      }
    }

    late final StreamSubscription<List<Map<String, dynamic>>> subscription;
    subscription = _client
        .from('users')
        .stream(primaryKey: <String>['username'])
        .eq('username', username)
        .listen((List<Map<String, dynamic>> rows) {
          if (rows.isEmpty) {
            emitPresence(false, 0);
            return;
          }
          final row = rows.first;
          final online = row['online'] as bool? ?? false;
          final lastHeartbeat = (row['last_heartbeat'] as num?)?.toInt() ?? 0;
          emitPresence(online, lastHeartbeat);
        });

    controller.onCancel = () {
      expiryTimer?.cancel();
      subscription.cancel();
    };

    return controller.stream;
  }

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) async {
    await ensureAuthenticated();
    final encryptedAnswer = await _signalingCipher.encryptPayload(
      roomId: roomId,
      purpose: SignalingCipher.answerPurpose,
      timestamp: answer.ts,
      payload: answer.toJson(),
    );
    await _client.from('rooms').upsert(<String, Object?>{
      'room_id': roomId,
      ..._roomParticipants(roomId),
      'answer': encryptedAnswer,
      'created_at': DateTime.now().millisecondsSinceEpoch,
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
    try {
      await _client.from('friend_requests').upsert(<String, Object?>{
        'from_user': normalizedFrom,
        'to_user': normalizedTo,
        'sent_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (error) {
      throw _normalizeFriendRequestWriteError(
        error,
        to: normalizedTo,
        from: normalizedFrom,
      );
    }
  }

  @override
  Future<void> blockUser(String blocker, String blocked) async {
    await ensureAuthenticated();
    final normalizedBlocker = _normalizedUsername(blocker);
    final normalizedBlocked = _normalizedUsername(blocked);
    if (normalizedBlocker == normalizedBlocked) {
      throw Exception('Cannot block yourself');
    }
    try {
      await _client.from('user_blocks').upsert(<String, Object?>{
        'blocker': normalizedBlocker,
        'blocked': normalizedBlocked,
        'blocked_at': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (error) {
      if (!_isMissingUserBlocksTableError(error)) {
        rethrow;
      }
    }
    await deleteFriendship(normalizedBlocker, normalizedBlocked);
    await _deleteFriendRequestsForPair(normalizedBlocker, normalizedBlocked);
  }

  @override
  Future<void> unblockUser(String blocker, String blocked) async {
    await ensureAuthenticated();
    final normalizedBlocker = _normalizedUsername(blocker);
    final normalizedBlocked = _normalizedUsername(blocked);
    try {
      await _client
          .from('user_blocks')
          .delete()
          .eq('blocker', normalizedBlocker)
          .eq('blocked', normalizedBlocked);
    } catch (error) {
      if (!_isMissingUserBlocksTableError(error)) {
        rethrow;
      }
    }
  }

  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) async {
    await ensureAuthenticated();
    final normalizedFirstUser = _normalizedUsername(firstUser);
    final normalizedSecondUser = _normalizedUsername(secondUser);
    if (normalizedFirstUser == normalizedSecondUser) {
      throw Exception('Cannot create friendship with yourself');
    }

    try {
      final currentUsername = await _currentUsername();
      if (currentUsername != normalizedFirstUser &&
          currentUsername != normalizedSecondUser) {
        throw Exception('Current user is not part of this friendship.');
      }

      final requestFrom = currentUsername == normalizedFirstUser
          ? normalizedSecondUser
          : normalizedFirstUser;
      await _client.rpc(
        'accept_friend_request',
        params: <String, Object?>{'request_from': requestFrom},
      );
    } catch (error) {
      if (!_isMissingFriendshipsTableError(error)) {
        rethrow;
      }
      await writeFriendRequest(normalizedSecondUser, normalizedFirstUser);
    }
  }

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    IceCandidatePayload candidate,
  ) async {
    await ensureAuthenticated();
    final encryptedCandidate = await _signalingCipher.encryptPayload(
      roomId: roomId,
      purpose: role == IceRole.caller
          ? SignalingCipher.callerIcePurpose
          : SignalingCipher.calleeIcePurpose,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: candidate.toJson(),
    );
    await _client.rpc(
      'append_room_ice',
      params: <String, Object?>{
        'target_room_id': roomId,
        'target_role': role == IceRole.caller ? 'caller' : 'callee',
        'target_candidate': encryptedCandidate,
      },
    );
  }

  @override
  Future<void> writeIrohAddress(
    String roomId,
    IrohAddressPayload payload,
  ) async {}

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {
    await ensureAuthenticated();
    final encryptedOffer = await _signalingCipher.encryptPayload(
      roomId: roomId,
      purpose: SignalingCipher.offerPurpose,
      timestamp: offer.ts,
      payload: offer.toJson(),
    );
    await _client.from('rooms').upsert(<String, Object?>{
      'room_id': roomId,
      ..._roomParticipants(roomId),
      'offer': encryptedOffer,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
