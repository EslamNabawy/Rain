import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'signaling_adapter.dart';

class SupabaseSignalingAdapter implements SignalingAdapter {
  SupabaseSignalingAdapter({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<void> deleteRoom(String roomId) async {
    await ensureAuthenticated();
    await _client.from('rooms').delete().eq('room_id', roomId);
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> ensureAuthenticated() async {
    if (_client.auth.currentSession != null) {
      return;
    }
    await _client.auth.signInAnonymously();
  }

  @override
  Future<String> currentUid() async {
    await ensureAuthenticated();
    return _client.auth.currentUser?.id ?? '';
  }

  @override
  Future<void> signOut() {
    return _client.auth.signOut();
  }

  String _hashPassword(String password) {
    int hash = 0;
    for (int i = 0; i < password.length; i++) {
      hash = ((hash << 5) - hash) + password.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  @override
  Future<String> register(String username, String password) async {
    await ensureAuthenticated();

    final existing = await fetchIdentity(username);
    if (existing != null && existing.uid.isNotEmpty) {
      throw Exception('Username "$username" is already taken');
    }

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    final uid = _client.auth.currentUser?.id ?? '';
    final now = DateTime.now().millisecondsSinceEpoch;
    final passwordHash = _hashPassword(password);

    await _client.from('users').upsert({
      'username': username,
      'uid': uid,
      'display_name': username,
      'registered_at': now,
      'last_seen': now,
      'last_heartbeat': now,
      'online': true,
      'password_hash': passwordHash,
    });

    return uid;
  }

  @override
  Future<String> login(String username, String password) async {
    await ensureAuthenticated();

    final rows =
        (await _client.from('users').select().eq('username', username).limit(1))
            as List<dynamic>;
    if (rows.isEmpty) {
      throw Exception('User "$username" not found');
    }

    final value = Map<String, dynamic>.from(rows.first as Map);
    final storedHash = value['password_hash'] as String? ?? '';
    final inputHash = _hashPassword(password);

    if (storedHash != inputHash) {
      throw Exception('Invalid password');
    }

    return value['uid'] as String? ?? _client.auth.currentUser?.id ?? '';
  }

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async {
    await ensureAuthenticated();
    final rows =
        (await _client.from('users').select().eq('username', username).limit(1))
            as List<dynamic>;
    if (rows.isEmpty) {
      return null;
    }
    final row = Map<String, dynamic>.from(rows.first as Map);
    return BackendIdentity(
      username: row['username'] as String,
      uid: row['uid'] as String? ?? '',
      displayName: row['display_name'] as String? ?? row['username'] as String,
      registeredAt: (row['registered_at'] as num?)?.toInt() ?? 0,
      lastSeen: (row['last_seen'] as num?)?.toInt() ?? 0,
      lastHeartbeat: (row['last_heartbeat'] as num?)?.toInt() ?? 0,
      online: row['online'] as bool? ?? false,
    );
  }

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async {
    if (query.length < 2) {
      return [];
    }

    await ensureAuthenticated();
    final rows = await _client
        .from('users')
        .select()
        .ilike('username', '%$query%')
        .limit(10);

    final result = <BackendIdentity>[];
    for (final row in rows as List<dynamic>) {
      final map = Map<String, dynamic>.from(row as Map);
      result.add(
        BackendIdentity(
          username: map['username'] as String,
          uid: map['uid'] as String? ?? '',
          displayName:
              map['display_name'] as String? ?? map['username'] as String,
          registeredAt: (map['registered_at'] as num?)?.toInt() ?? 0,
          lastSeen: (map['last_seen'] as num?)?.toInt() ?? 0,
          lastHeartbeat: (map['last_heartbeat'] as num?)?.toInt() ?? 0,
          online: map['online'] as bool? ?? false,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> addToUserSearch(String username) async {
    await ensureAuthenticated();
    await _client.from('user_search').upsert({'username': username});
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
    return _client
        .from('rooms')
        .stream(primaryKey: <String>['room_id'])
        .eq('room_id', roomId)
        .map((List<Map<String, dynamic>> rows) {
          if (rows.isEmpty || rows.first['answer'] == null) {
            throw const _SkipStreamValue();
          }
          return SDPPayload.fromJson(
            rows.first['answer'] as Map<Object?, Object?>,
          );
        })
        .where((_) => true)
        .handleError((_) {}, test: (_) => true);
  }

  @override
  Stream<String> onFriendRequest(String username) {
    return _client
        .from('friend_requests')
        .stream(primaryKey: <String>['from_user', 'to_user'])
        .eq('to_user', username)
        .map(
          (List<Map<String, dynamic>> rows) =>
              rows.map((Map<String, dynamic> row) {
                return row['from_user'] as String;
              }).toList(),
        )
        .expand((List<String> rows) => rows);
  }

  @override
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role) {
    final field = role == IceRole.caller ? 'caller_ice' : 'callee_ice';
    final seen = <String>{};
    return _client
        .from('rooms')
        .stream(primaryKey: <String>['room_id'])
        .eq('room_id', roomId)
        .expand((List<Map<String, dynamic>> rows) sync* {
          if (rows.isEmpty) {
            return;
          }
          final raw = rows.first[field];
          final values = raw is List
              ? raw.cast<Map<String, dynamic>>()
              : const <Map<String, dynamic>>[];
          for (final value in values) {
            final key =
                '${value['candidate']}:${value['sdpMid']}:${value['sdpMLineIndex']}';
            if (seen.add(key)) {
              yield iceCandidateFromJson(value);
            }
          }
        });
  }

  @override
  Stream<SDPPayload> onOffer(String roomId) {
    return _client
        .from('rooms')
        .stream(primaryKey: <String>['room_id'])
        .eq('room_id', roomId)
        .map((List<Map<String, dynamic>> rows) {
          if (rows.isEmpty || rows.first['offer'] == null) {
            throw const _SkipStreamValue();
          }
          return SDPPayload.fromJson(
            rows.first['offer'] as Map<Object?, Object?>,
          );
        })
        .where((_) => true)
        .handleError((_) {}, test: (_) => true);
  }

  @override
  Future<void> setPresence(String username, bool online) async {
    await ensureAuthenticated();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _client.from('users').upsert(<String, Object?>{
      'username': username,
      'online': online,
      'last_seen': now,
      'last_heartbeat': now,
      'uid': _client.auth.currentUser?.id ?? '',
    });
  }

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {
    await ensureAuthenticated();
    await _client.from('users').upsert(identity.toSupabaseJson());
  }

  @override
  Stream<bool> watchPresence(String username) {
    return _client
        .from('users')
        .stream(primaryKey: <String>['username'])
        .eq('username', username)
        .map((List<Map<String, dynamic>> rows) {
          if (rows.isEmpty) {
            return false;
          }
          return rows.first['online'] as bool? ?? false;
        });
  }

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) async {
    await ensureAuthenticated();
    await _client.from('rooms').upsert(<String, Object?>{
      'room_id': roomId,
      'answer': answer.toJson(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> writeFriendRequest(String to, String from) async {
    await ensureAuthenticated();
    await _client.from('friend_requests').upsert(<String, Object?>{
      'from_user': from,
      'to_user': to,
      'sent_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    RTCIceCandidate candidate,
  ) async {
    await ensureAuthenticated();
    final field = role == IceRole.caller ? 'caller_ice' : 'callee_ice';
    final rows =
        (await _client
                .from('rooms')
                .select(field)
                .eq('room_id', roomId)
                .limit(1))
            as List<dynamic>;
    final current = rows.isNotEmpty && (rows.first as Map)[field] is List
        ? List<Map<String, Object?>>.from((rows.first as Map)[field] as List)
        : <Map<String, Object?>>[];
    current.add(iceCandidateToJson(candidate));
    await _client.from('rooms').upsert(<String, Object?>{
      'room_id': roomId,
      field: current,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) async {
    await ensureAuthenticated();
    await _client.from('rooms').upsert(<String, Object?>{
      'room_id': roomId,
      'offer': offer.toJson(),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
}

class _SkipStreamValue implements Exception {
  const _SkipStreamValue();
}
