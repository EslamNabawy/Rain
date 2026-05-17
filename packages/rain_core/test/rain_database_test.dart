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
      isA<QueryRow>().having((row) => row.data.values.single, 'version', 5),
    );
  });

  test('serializedWrite retries busy snapshot transactions', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    var attempts = 0;
    final result = await database.serializedWrite(() async {
      attempts += 1;
      if (attempts == 1) {
        throw SqliteException(517, 'database is locked');
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

class _LegacyExecutor extends QueryExecutorUser {
  @override
  int get schemaVersion => 2;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
