/// # rain_database.dart — rain_core package
///
/// Defines the Drift (SQLite) database schema and RainDatabase class for
/// local persistence. Contains table definitions for messages, friends,
/// queued messages, file transfers, connection memory, identity, and
/// message sequence tracking, along with migration logic.
///
/// **Key types:** Messages, Friends, QueuedMessages, FileTransfers,
///   ConnectionMemoryTable, IdentityTable, MessageSeqTracker, RainDatabase.
///
/// **Package:** rain_core
///
/// **Depends on:** drift, drift_flutter, dart:async.
library;

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:sqlite3/common.dart';

part 'rain_database.g.dart';

@TableIndex(
  name: 'messages_peer_sent_seq_id_idx',
  columns: <Symbol>{#peerId, #sentAt, #seq, #id},
)
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

@TableIndex(name: 'friends_display_name_idx', columns: <Symbol>{#displayName})
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

@TableIndex(
  name: 'queued_messages_to_status_seq_sent_idx',
  columns: <Symbol>{#to, #status, #seq, #sentAt},
)
@TableIndex(
  name: 'queued_messages_status_to_idx',
  columns: <Symbol>{#status, #to},
)
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

@TableIndex(
  name: 'file_transfers_peer_created_idx',
  columns: <Symbol>{#peerId, #createdAt},
)
@TableIndex(
  name: 'file_transfers_message_id_idx',
  columns: <Symbol>{#messageId},
)
@TableIndex(
  name: 'file_transfers_state_peer_idx',
  columns: <Symbol>{#state, #peerId},
)
class FileTransfers extends Table {
  TextColumn get id => text()();
  TextColumn get peerId => text()();
  TextColumn get messageId => text()();
  TextColumn get direction => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer()();
  TextColumn get mimeType => text().nullable()();
  TextColumn get localPath => text().nullable()();
  TextColumn get tempPath => text().nullable()();
  IntColumn get bytesTransferred => integer().withDefault(const Constant(0))();
  TextColumn get state => text()();
  TextColumn get error => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

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
    FileTransfers,
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
  int get schemaVersion => 6;

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
      if (from < 5) {
        await m.createTable(fileTransfers);
      }
      if (from < 6) {
        await _createScalabilityIndexes();
      }
    },
  );

  Future<void> _createScalabilityIndexes() async {
    if (await _hasTable('messages')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS messages_peer_sent_seq_id_idx '
        'ON messages (peer_id, sent_at, seq, id);',
      );
    }
    if (await _hasTable('friends')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS friends_display_name_idx '
        'ON friends (display_name);',
      );
    }
    if (await _hasTable('queued_messages')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS queued_messages_to_status_seq_sent_idx '
        'ON queued_messages ("to", status, seq, sent_at);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS queued_messages_status_to_idx '
        'ON queued_messages (status, "to");',
      );
    }
    if (await _hasTable('file_transfers')) {
      await customStatement(
        'CREATE INDEX IF NOT EXISTS file_transfers_peer_created_idx '
        'ON file_transfers (peer_id, created_at);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS file_transfers_message_id_idx '
        'ON file_transfers (message_id);',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS file_transfers_state_peer_idx '
        'ON file_transfers (state, peer_id);',
      );
    }
  }

  Future<bool> _hasTable(String tableName) async {
    final rows = await customSelect(
      'SELECT name FROM sqlite_master WHERE type = ? AND name = ?;',
      variables: <Variable<Object>>[
        const Variable<String>('table'),
        Variable<String>(tableName),
      ],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _hasColumn(String tableName, String columnName) async {
    final rows = await customSelect('PRAGMA table_info($tableName);').get();
    return rows.any((row) => row.data['name'] == columnName);
  }

  Future<void> clearSessionData() {
    return serializedTransaction(() async {
      await delete(messages).go();
      await delete(friends).go();
      await delete(queuedMessages).go();
      await delete(fileTransfers).go();
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
