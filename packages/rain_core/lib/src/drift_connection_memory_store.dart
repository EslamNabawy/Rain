import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:protocol_brain/protocol_brain.dart';

import '../database/rain_database.dart';

class DriftConnectionMemoryStore implements ConnectionMemoryStore {
  DriftConnectionMemoryStore(this._database);

  final RainDatabase _database;

  @override
  Future<void> delete(String peerId) {
    return _database.transaction(() async {
      await (_database.delete(_database.connectionMemoryTable)
            ..where((ConnectionMemoryTable row) => row.peerId.equals(peerId)))
          .go();
    });
  }

  @override
  Future<ConnectionMemory?> read(String peerId) async {
    final query = _database.select(_database.connectionMemoryTable)
      ..where((ConnectionMemoryTable row) => row.peerId.equals(peerId))
      ..limit(1);
    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }

    final json = jsonDecode(row.cachedIce) as List<dynamic>;
    return ConnectionMemory(
      peerId: row.peerId,
      lastConnectedAt: row.lastConnectedAt,
      cachedIce: json
          .map((dynamic item) => iceCandidateFromJson(item as Map<Object?, Object?>))
          .toList(growable: false),
      fingerprint: row.fingerprint,
      consecutiveFailures: row.consecutiveFailures,
    );
  }

  @override
  Future<void> write(ConnectionMemory memory) {
    return _database.transaction(() async {
      await _database.into(_database.connectionMemoryTable).insertOnConflictUpdate(
        ConnectionMemoryTableCompanion.insert(
          peerId: memory.peerId,
          lastConnectedAt: memory.lastConnectedAt,
          cachedIce: jsonEncode(
            memory.cachedIce.map(iceCandidateToJson).toList(growable: false),
          ),
          fingerprint: memory.fingerprint,
          consecutiveFailures: Value<int>(memory.consecutiveFailures),
        ),
      );
    });
  }
}
