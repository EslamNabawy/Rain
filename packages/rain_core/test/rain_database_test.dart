/// # rain_database_test.dart — rain_core package
///
/// Tests for RainDatabase SQLite configuration including busy timeout, WAL journal mode, foreign keys, and migration idempotency for the friends online column.
///
/// **Key types:** None (test file)
///
/// **Package:** rain_core
///
/// **Depends on:** drift, drift/native.dart, flutter_test, rain_database.dart
///
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rain_core/database/rain_database.dart';

void main() {
  test('sqlite setup enables lock-tolerant local database pragmas', () async {
    final tempDir = Directory.systemTemp.createTempSync('rain_db_test_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final database = RainDatabase(
      NativeDatabase(
        File(p.join(tempDir.path, 'rain.sqlite')),
        setup: configureRainSqliteConnection,
      ),
    );
    addTearDown(database.close);

    final busyTimeout = await database
        .customSelect('PRAGMA busy_timeout;')
        .getSingle();
    expect(busyTimeout.data.values.single, 5000);

    final journalMode = await database
        .customSelect('PRAGMA journal_mode;')
        .getSingle();
    expect(journalMode.data.values.single.toString().toLowerCase(), 'wal');

    final foreignKeys = await database
        .customSelect('PRAGMA foreign_keys;')
        .getSingle();
    expect(foreignKeys.data.values.single, 1);
  });

  test('migration skips already-added friends online column', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'rain_db_migration_test_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final file = File(p.join(tempDir.path, 'rain.sqlite'));
    final legacy = NativeDatabase(file);
    await legacy.ensureOpen(_LegacyExecutor());
    await legacy.runCustom(
      'CREATE TABLE friends ('
      'username TEXT NOT NULL PRIMARY KEY, '
      'display_name TEXT NOT NULL, '
      'state TEXT NOT NULL, '
      'added_at INTEGER NOT NULL, '
      'last_online_at INTEGER NULL, '
      'online INTEGER NOT NULL DEFAULT 0 CHECK (online IN (0, 1)), '
      'unread_count INTEGER NOT NULL DEFAULT 0'
      ');',
    );
    await legacy.runCustom('PRAGMA user_version = 2;');
    await legacy.close();

    final database = RainDatabase(
      NativeDatabase(file, setup: configureRainSqliteConnection),
    );
    addTearDown(database.close);

    final columns = await database
        .customSelect('PRAGMA table_info(friends);')
        .get();

    expect(columns.map((row) => row.data['name']), contains('online'));
    expect(columns.map((row) => row.data['name']), contains('gender'));
    expect(
      await database.customSelect('PRAGMA table_info(file_transfers);').get(),
      isNotEmpty,
    );
    expect(
      await database.customSelect('PRAGMA user_version;').getSingle(),
      isA<QueryRow>().having((row) => row.data.values.single, 'version', 6),
    );
  });

  test('schema v6 creates explicit scalability indexes', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await _expectIndex(
      database,
      table: 'messages',
      index: 'messages_peer_sent_seq_id_idx',
    );
    await _expectIndex(
      database,
      table: 'queued_messages',
      index: 'queued_messages_to_status_seq_sent_idx',
    );
    await _expectIndex(
      database,
      table: 'queued_messages',
      index: 'queued_messages_status_to_idx',
    );
    await _expectIndex(
      database,
      table: 'file_transfers',
      index: 'file_transfers_peer_created_idx',
    );
    await _expectIndex(
      database,
      table: 'file_transfers',
      index: 'file_transfers_message_id_idx',
    );
    await _expectIndex(
      database,
      table: 'file_transfers',
      index: 'file_transfers_state_peer_idx',
    );
    await _expectIndex(
      database,
      table: 'friends',
      index: 'friends_display_name_idx',
    );
  });

  test('migration from v5 creates scalability indexes', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'rain_db_v6_migration_test_',
    );
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final file = File(p.join(tempDir.path, 'rain.sqlite'));
    final legacy = NativeDatabase(file);
    await legacy.ensureOpen(_LegacyV5Executor());
    await _createLegacyV5Schema(legacy);
    await legacy.runCustom('PRAGMA user_version = 5;');
    await legacy.close();

    final database = RainDatabase(
      NativeDatabase(file, setup: configureRainSqliteConnection),
    );
    addTearDown(database.close);

    await _expectIndex(
      database,
      table: 'messages',
      index: 'messages_peer_sent_seq_id_idx',
    );
    await _expectIndex(
      database,
      table: 'queued_messages',
      index: 'queued_messages_to_status_seq_sent_idx',
    );
    await _expectIndex(
      database,
      table: 'file_transfers',
      index: 'file_transfers_state_peer_idx',
    );
    expect(
      await database.customSelect('PRAGMA user_version;').getSingle(),
      isA<QueryRow>().having((row) => row.data.values.single, 'version', 6),
    );
  });

  test('serializedWrite retries busy snapshot transactions', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    var attempts = 0;
    final result = await database.serializedWrite(() async {
      attempts += 1;
      if (attempts == 1) {
        throw SqliteException(
          extendedResultCode: 517,
          message: 'database is locked',
        );
      }
      await database
          .into(database.friends)
          .insert(
            FriendsCompanion.insert(
              username: 'bob',
              displayName: 'Bob',
              state: 'friend',
              addedAt: 1,
            ),
          );
      return 'stored';
    }, baseDelay: Duration.zero);

    expect(result, 'stored');
    expect(attempts, 2);
    final row = await database.select(database.friends).getSingle();
    expect(row.username, 'bob');
  });
}

Future<void> _expectIndex(
  RainDatabase database, {
  required String table,
  required String index,
}) async {
  final rows = await database.customSelect('PRAGMA index_list($table);').get();
  expect(
    rows.map((row) => row.data['name']),
    contains(index),
    reason: '$table should have index $index',
  );
}

Future<void> _createLegacyV5Schema(NativeDatabase database) async {
  await database.runCustom(
    'CREATE TABLE messages ('
    'id TEXT NOT NULL PRIMARY KEY, '
    'peer_id TEXT NOT NULL, '
    'content TEXT NOT NULL, '
    'sent_at INTEGER NOT NULL, '
    'seq INTEGER NOT NULL, '
    'type TEXT NOT NULL, '
    'status TEXT NOT NULL, '
    'is_outgoing INTEGER NOT NULL CHECK (is_outgoing IN (0, 1))'
    ');',
  );
  await database.runCustom(
    'CREATE TABLE friends ('
    'username TEXT NOT NULL PRIMARY KEY, '
    'display_name TEXT NOT NULL, '
    'gender TEXT NULL, '
    'state TEXT NOT NULL, '
    'added_at INTEGER NOT NULL, '
    'last_online_at INTEGER NULL, '
    'online INTEGER NOT NULL DEFAULT 0 CHECK (online IN (0, 1)), '
    'unread_count INTEGER NOT NULL DEFAULT 0'
    ');',
  );
  await database.runCustom(
    'CREATE TABLE queued_messages ('
    'id TEXT NOT NULL PRIMARY KEY, '
    '"to" TEXT NOT NULL, '
    'content TEXT NOT NULL, '
    'sent_at INTEGER NOT NULL, '
    'seq INTEGER NOT NULL, '
    'status TEXT NOT NULL'
    ');',
  );
  await database.runCustom(
    'CREATE TABLE file_transfers ('
    'id TEXT NOT NULL PRIMARY KEY, '
    'peer_id TEXT NOT NULL, '
    'message_id TEXT NOT NULL, '
    'direction TEXT NOT NULL, '
    'file_name TEXT NOT NULL, '
    'file_size INTEGER NOT NULL, '
    'mime_type TEXT NULL, '
    'local_path TEXT NULL, '
    'temp_path TEXT NULL, '
    'bytes_transferred INTEGER NOT NULL DEFAULT 0, '
    'state TEXT NOT NULL, '
    'error TEXT NULL, '
    'created_at INTEGER NOT NULL, '
    'updated_at INTEGER NOT NULL'
    ');',
  );
}

class _LegacyExecutor extends QueryExecutorUser {
  @override
  int get schemaVersion => 2;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

class _LegacyV5Executor extends QueryExecutorUser {
  @override
  int get schemaVersion => 5;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
