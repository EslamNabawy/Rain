import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

part 'rain_database.g.dart';

class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get peerId => text()();
  TextColumn get content => text()();
  IntColumn get sentAt => integer()();
  IntColumn get seq => integer()();
  TextColumn get type => text()();
  TextColumn get status => text()();
  BoolColumn get isOutgoing => boolean()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class Friends extends Table {
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  TextColumn get gender => text().nullable()();
  TextColumn get state => text()();
  IntColumn get addedAt => integer()();
  IntColumn get lastOnlineAt => integer().nullable()();
  BoolColumn get online => boolean().withDefault(const Constant(false))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{username};
}

class QueuedMessages extends Table {
  TextColumn get id => text()();
  TextColumn get to => text()();
  TextColumn get content => text()();
  IntColumn get sentAt => integer()();
  IntColumn get seq => integer()();
  TextColumn get status => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class ConnectionMemoryTable extends Table {
  TextColumn get peerId => text()();
  IntColumn get lastConnectedAt => integer()();
  TextColumn get cachedIce => text()();
  TextColumn get fingerprint => text()();
  IntColumn get consecutiveFailures =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{peerId};
}

class IdentityTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text()();
  TextColumn get displayName => text()();
  IntColumn get createdAt => integer()();
  TextColumn get gender => text().nullable()();
}

class MessageSeqTracker extends Table {
  TextColumn get peerId => text()();
  IntColumn get lastSeq => integer()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{peerId};
}

@DriftDatabase(
  tables: <Type>[
    Messages,
    Friends,
    QueuedMessages,
    ConnectionMemoryTable,
    IdentityTable,
    MessageSeqTracker,
  ],
)
class RainDatabase extends _$RainDatabase {
  RainDatabase([QueryExecutor? executor])
    : super(executor ?? _openRainDatabase());
  Future<void> _serializedWriteQueue = Future<void>.value();

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2 && !await _hasColumn('identity_table', 'gender')) {
        await m.addColumn(identityTable, identityTable.gender);
      }
      if (from < 3 && !await _hasColumn('friends', 'online')) {
        await m.addColumn(friends, friends.online);
      }
      if (from < 4 && !await _hasColumn('friends', 'gender')) {
        await m.addColumn(friends, friends.gender);
      }
    },
  );

  Future<bool> _hasColumn(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName);').get();
    return rows.any((row) => row.data['name'] == columnName);
  }

  Future<void> clearSessionData() {
    return serializedTransaction(() async {
      await delete(messages).go();
      await delete(friends).go();
      await delete(queuedMessages).go();
      await delete(connectionMemoryTable).go();
      await delete(identityTable).go();
      await delete(messageSeqTracker).go();
    });
  }

  Future<T> serializedWrite<T>(
    Future<T> Function() action, {
    int maxAttempts = 6,
    Duration baseDelay = const Duration(milliseconds: 25),
  }) {
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'must be at least 1',
      );
    }

    final completer = Completer<T>();
    final previous = _serializedWriteQueue;
    _serializedWriteQueue = previous.catchError((_) {}).then((_) async {
      try {
        final value = await _retryBusyWrite(
          action,
          maxAttempts: maxAttempts,
          baseDelay: baseDelay,
        );
        completer.complete(value);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<T> serializedTransaction<T>(
    Future<T> Function() action, {
    int maxAttempts = 6,
    Duration baseDelay = const Duration(milliseconds: 25),
  }) {
    return serializedWrite(
      () => transaction(action),
      maxAttempts: maxAttempts,
      baseDelay: baseDelay,
    );
  }

  Future<T> _retryBusyWrite<T>(
    Future<T> Function() action, {
    required int maxAttempts,
    required Duration baseDelay,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        return await action();
      } on SqliteException catch (error) {
        if (!_isBusyOrLocked(error) || attempt == maxAttempts) {
          rethrow;
        }
        final multiplier = 1 << (attempt - 1);
        final delay = baseDelay * multiplier;
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
    }
    throw StateError('unreachable serialized SQLite write retry state');
  }

  bool _isBusyOrLocked(SqliteException error) {
    return error.resultCode == SqlError.SQLITE_BUSY ||
        error.resultCode == SqlError.SQLITE_LOCKED;
  }
}

QueryExecutor _openRainDatabase() {
  return driftDatabase(
    name: 'rain',
    native: const DriftNativeOptions(
      shareAcrossIsolates: true,
      setup: configureRainSqliteConnection,
    ),
  );
}

void configureRainSqliteConnection(CommonDatabase db) {
  db.execute('PRAGMA busy_timeout = 5000;');
  db.execute('PRAGMA journal_mode = WAL;');
  db.execute('PRAGMA synchronous = NORMAL;');
  db.execute('PRAGMA foreign_keys = ON;');
}
