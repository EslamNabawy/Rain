import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  TextColumn get state => text()();
  IntColumn get addedAt => integer()();
  IntColumn get lastOnlineAt => integer().nullable()();
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
    : super(executor ?? driftDatabase(name: 'rain'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(identityTable, identityTable.gender);
      }
    },
  );

  Future<void> clearSessionData() {
    return transaction(() async {
      await delete(messages).go();
      await delete(friends).go();
      await delete(queuedMessages).go();
      await delete(connectionMemoryTable).go();
      await delete(identityTable).go();
      await delete(messageSeqTracker).go();
    });
  }
}
