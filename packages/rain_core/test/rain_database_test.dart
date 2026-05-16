import 'dart:io';

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
}
