import 'package:drift/drift.dart';

import '../database/rain_database.dart';
import '../identity/identity.dart';

enum FriendState {
  pendingOutgoing,
  pendingIncoming,
  friend,
  blocked,
  blockedByPeer,
}

class FriendRecord {
  const FriendRecord({
    required this.username,
    required this.displayName,
    required this.state,
    required this.addedAt,
    required this.lastOnlineAt,
    required this.isOnline,
    required this.unreadCount,
    required this.gender,
  });

  final String username;
  final String displayName;
  final FriendState state;
  final int addedAt;
  final int? lastOnlineAt;
  final bool isOnline;
  final int unreadCount;
  final RainGender? gender;
}

class FriendStore {
  FriendStore(this._database);

  final RainDatabase _database;

  Stream<List<FriendRecord>> watchFriends() {
    final query = _database.select(_database.friends)
      ..orderBy(<OrderingTerm Function(Friends)>[
        (Friends table) => OrderingTerm.asc(table.displayName),
      ]);
    return query.watch().map(
      (List<Friend> rows) => rows.map(_mapRecord).toList(growable: false),
    );
  }

  Future<List<FriendRecord>> loadFriends() async {
    final query = _database.select(_database.friends)
      ..orderBy(<OrderingTerm Function(Friends)>[
        (Friends table) => OrderingTerm.asc(table.displayName),
      ]);
    return (await query.get()).map(_mapRecord).toList(growable: false);
  }

  Future<FriendRecord?> loadFriend(String username) async {
    final query = _database.select(_database.friends)
      ..where((Friends row) => row.username.equals(username))
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapRecord(row);
  }

  Future<void> upsertFriend({
    required String username,
    required String displayName,
    required FriendState state,
    int? addedAt,
    RainGender? gender,
  }) {
    return _database.serializedTransaction(() async {
      final existing =
          await (_database.select(_database.friends)
                ..where((Friends row) => row.username.equals(username))
                ..limit(1))
              .getSingleOrNull();
      final effectiveGender = gender ?? _genderFromName(existing?.gender);

      await _database
          .into(_database.friends)
          .insertOnConflictUpdate(
            FriendsCompanion.insert(
              username: username,
              displayName: displayName,
              state: state.name,
              addedAt: addedAt ?? DateTime.now().millisecondsSinceEpoch,
              gender: effectiveGender == null
                  ? const Value<String?>.absent()
                  : Value<String?>(effectiveGender.name),
            ),
          );
    });
  }

  Future<void> markAccepted(
    String username, {
    String? displayName,
    RainGender? gender,
  }) {
    return _database.serializedTransaction(() async {
      await (_database.update(
        _database.friends,
      )..where((Friends row) => row.username.equals(username))).write(
        FriendsCompanion(
          displayName: displayName == null
              ? const Value<String>.absent()
              : Value<String>(displayName),
          state: Value<String>(FriendState.friend.name),
          gender: gender == null
              ? const Value<String?>.absent()
              : Value<String?>(gender.name),
        ),
      );
    });
  }

  Future<void> reject(String username) {
    return _database.serializedTransaction(() async {
      await (_database.delete(
        _database.friends,
      )..where((Friends row) => row.username.equals(username))).go();
    });
  }

  Future<void> block(String username) {
    return _database.serializedTransaction(() async {
      await _upsertBlockedState(username, FriendState.blocked);
    });
  }

  Future<void> markBlockedByPeer(String username) {
    return _database.serializedTransaction(() async {
      await _upsertBlockedState(username, FriendState.blockedByPeer);
    });
  }

  Future<void> _upsertBlockedState(String username, FriendState state) async {
    final existing =
        await (_database.select(_database.friends)
              ..where((Friends row) => row.username.equals(username))
              ..limit(1))
            .getSingleOrNull();
    await _database
        .into(_database.friends)
        .insertOnConflictUpdate(
          FriendsCompanion.insert(
            username: username,
            displayName: existing?.displayName ?? username,
            state: state.name,
            addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
            gender: existing?.gender == null
                ? const Value<String?>.absent()
                : Value<String?>(existing!.gender),
          ),
        );
  }

  Future<void> unblock(String username) {
    return _database.serializedTransaction(() async {
      await (_database.delete(
        _database.friends,
      )..where((Friends row) => row.username.equals(username))).go();
    });
  }

  Future<void> updatePresence(String username, bool isOnline) {
    return _database.serializedTransaction(() async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await (_database.update(
        _database.friends,
      )..where((Friends row) => row.username.equals(username))).write(
        FriendsCompanion(
          online: Value<bool>(isOnline),
          lastOnlineAt: isOnline ? const Value.absent() : Value<int?>(now),
        ),
      );
    });
  }

  Future<void> incrementUnread(String username) {
    return _database.serializedTransaction(() async {
      final query = _database.select(_database.friends)
        ..where((Friends row) => row.username.equals(username))
        ..limit(1);
      final existing = await query.getSingleOrNull();
      if (existing == null) {
        return;
      }
      await (_database.update(
        _database.friends,
      )..where((Friends row) => row.username.equals(username))).write(
        FriendsCompanion(unreadCount: Value<int>(existing.unreadCount + 1)),
      );
    });
  }

  Future<void> clearUnread(String username) {
    return _database.serializedTransaction(() async {
      await (_database.update(_database.friends)
            ..where((Friends row) => row.username.equals(username)))
          .write(const FriendsCompanion(unreadCount: Value<int>(0)));
    });
  }

  FriendRecord _mapRecord(Friend row) {
    return FriendRecord(
      username: row.username,
      displayName: row.displayName,
      state: FriendState.values.byName(row.state),
      addedAt: row.addedAt,
      lastOnlineAt: row.lastOnlineAt,
      isOnline: row.online,
      unreadCount: row.unreadCount,
      gender: _genderFromName(row.gender),
    );
  }

  RainGender? _genderFromName(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final gender in RainGender.values) {
      if (gender.name == normalized) {
        return gender;
      }
    }
    return null;
  }
}
