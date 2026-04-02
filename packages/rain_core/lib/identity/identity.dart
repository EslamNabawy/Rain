import 'package:drift/drift.dart';

import '../database/rain_database.dart';

enum RainGender { male, female }

class RainIdentity {
  const RainIdentity({
    required this.username,
    required this.displayName,
    required this.createdAt,
    required this.gender,
  });

  final String username;
  final String displayName;
  final int createdAt;
  final RainGender? gender;

  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,24}$');

  static bool isValidUsername(String value) => _usernamePattern.hasMatch(value);

  RainIdentity copyWith({
    String? username,
    String? displayName,
    int? createdAt,
    RainGender? gender,
  }) {
    return RainIdentity(
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      gender: gender ?? this.gender,
    );
  }
}

class IdentityRepository {
  IdentityRepository(this._database);

  final RainDatabase _database;

  Stream<RainIdentity?> watchIdentity() {
    final query = _database.select(_database.identityTable)
      ..limit(1);
    return query.watchSingleOrNull().map(_mapIdentity);
  }

  Future<RainIdentity?> loadIdentity() async {
    final query = _database.select(_database.identityTable)
      ..limit(1);
    return _mapIdentity(await query.getSingleOrNull());
  }

  Future<void> saveIdentity(RainIdentity identity) {
    return _database.transaction(() async {
      await _database.delete(_database.identityTable).go();
      await _database.into(_database.identityTable).insert(
        IdentityTableCompanion.insert(
          username: identity.username,
          displayName: identity.displayName,
          createdAt: identity.createdAt,
          gender: Value<String?>(identity.gender?.name),
        ),
      );
    });
  }

  Future<void> updateDisplayName(String displayName) {
    return _database.transaction(() async {
      await (_database.update(_database.identityTable)..where(
            (IdentityTable table) => table.id.isBiggerThanValue(0),
          ))
          .write(
            IdentityTableCompanion(
              displayName: Value<String>(displayName),
            ),
          );
    });
  }

  Future<void> updateGender(RainGender? gender) {
    return _database.transaction(() async {
      await (_database.update(_database.identityTable)..where(
            (IdentityTable table) => table.id.isBiggerThanValue(0),
          ))
          .write(
            IdentityTableCompanion(
              gender: Value<String?>(gender?.name),
            ),
          );
    });
  }

  RainIdentity? _mapIdentity(IdentityTableData? data) {
    if (data == null) {
      return null;
    }
    return RainIdentity(
      username: data.username,
      displayName: data.displayName,
      createdAt: data.createdAt,
      gender: data.gender == null ? null : RainGender.values.byName(data.gender!),
    );
  }
}
