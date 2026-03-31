import 'package:drift/drift.dart';

import '../database/rain_database.dart';

enum FriendState {
  pendingOutgoing,
  pendingIncoming,
  friend,
  blocked,
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
  });

  final String username;
  final String displayName;
  final FriendState state;
  final int addedAt;
  final int? lastOnlineAt;
  final bool isOnline;
  final int unreadCount;
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
  }) {
    return _database.transaction(() async {
      await _database.into(_database.friends).insertOnConflictUpdate(
        FriendsCompanion.insert(
          username: username,
          displayName: displayName,
          state: state.name,
          addedAt: addedAt ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
    });
  }

  Future<void> markAccepted(String username, {String? displayName}) {
    return _database.transaction(() async {
      await (_database.update(_database.friends)
            ..where((Friends row) => row.username.equals(username)))
          .write(
            FriendsCompanion(
              displayName: displayName == null
                  ? const Value<String>.absent()
                  : Value<String>(displayName),
              state: Value<String>(FriendState.friend.name),
            ),
          );
    });
  }

  Future<void> reject(String username) {
    return _database.transaction(() async {
      await (_database.delete(_database.friends)
            ..where((Friends row) => row.username.equals(username)))
          .go();
    });
  }

  Future<void> block(String username) {
    return _database.transaction(() async {
      await (_database.update(_database.friends)
            ..where((Friends row) => row.username.equals(username)))
          .write(
            FriendsCompanion(state: Value<String>(FriendState.blocked.name)),
          );
    });
  }

  Future<void> updatePresence(String username, bool isOnline) {
    return _database.transaction(() async {
      await (_database.update(_database.friends)
            ..where((Friends row) => row.username.equals(username)))
          .write(
            FriendsCompanion(
              lastOnlineAt: Value<int?>(
                isOnline ? DateTime.now().millisecondsSinceEpoch : null,
              ),
            ),
          );
    });
  }

  Future<void> incrementUnread(String username) {
    return _database.transaction(() async {
      final query = _database.select(_database.friends)
        ..where((Friends row) => row.username.equals(username))
        ..limit(1);
      final existing = await query.getSingleOrNull();
      if (existing == null) {
        return;
      }
      await (_database.update(_database.friends)
            ..where((Friends row) => row.username.equals(username)))
          .write(
            FriendsCompanion(
              unreadCount: Value<int>(existing.unreadCount + 1),
            ),
          );
    });
  }

  Future<void> clearUnread(String username) {
    return _database.transaction(() async {
      await (_database.update(_database.friends)
            ..where((Friends row) => row.username.equals(username)))
          .write(
            const FriendsCompanion(unreadCount: Value<int>(0)),
          );
    });
  }

  FriendRecord _mapRecord(Friend row) {
    final lastOnlineAt = row.lastOnlineAt;
    final isOnline = lastOnlineAt != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(lastOnlineAt),
            ) <
            const Duration(minutes: 7);
    return FriendRecord(
      username: row.username,
      displayName: row.displayName,
      state: FriendState.values.byName(row.state),
      addedAt: row.addedAt,
      lastOnlineAt: row.lastOnlineAt,
      isOnline: isOnline,
      unreadCount: row.unreadCount,
    );
  }
}
