import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rain_core/database/rain_database.dart';
import 'package:rain_core/identity/identity_key_repository.dart';
import 'package:rain_core/identity/key_store_service.dart';

RainDatabase _openTempDb(Directory dir) {
  return RainDatabase(
    NativeDatabase(
      File(p.join(dir.path, 'rain.sqlite')),
      setup: configureRainSqliteConnection,
    ),
  );
}

Future<void> _seedIdentity(RainDatabase db) async {
  await db
      .into(db.identityTable)
      .insert(
        IdentityTableCompanion.insert(
          username: 'eslam',
          displayName: 'Eslam',
          createdAt: 1,
          gender: const Value<String?>(null),
        ),
      );
}

void main() {
  group('TASK-015 IdentityKeyRepository', () {
    test(
      'generates an X25519 keypair once and persists the public key',
      () async {
        final dir = Directory.systemTemp.createTempSync('rain_keypair_');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        final db = _openTempDb(dir);
        addTearDown(db.close);
        final store = InMemoryKeyStoreService();
        final repo = IdentityKeyRepository(db, store);

        await _seedIdentity(db);

        final first = await repo.ensureKeyPair();
        // X25519 public keys are 32 bytes.
        expect(first.bytes.length, 32);
        expect(first.type, KeyPairType.x25519);

        // Private key is wrapped into the secure store.
        final stored = await store.read(KeyStoreIds.identityPrivateKey);
        expect(stored, isNotNull);
        expect(store.read(KeyStoreIds.identityPrivateKey), isNotNull);

        // Public key persisted to the DB column.
        final pub = await repo.getPublicKey();
        expect(pub, isNotNull);
        expect(pub!.bytes, first.bytes);

        // Second call is idempotent: same public key, no new private key written.
        final again = await repo.ensureKeyPair();
        expect(again.bytes, first.bytes);
      },
    );

    test('getPrivateKeyBytes returns the wrapped private key', () async {
      final dir = Directory.systemTemp.createTempSync('rain_keypair_2_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final db = _openTempDb(dir);
      addTearDown(db.close);
      final store = InMemoryKeyStoreService();
      final repo = IdentityKeyRepository(db, store);
      await _seedIdentity(db);

      await repo.ensureKeyPair();
      final private = await repo.getPrivateKeyBytes();
      expect(private.length, 32); // X25519 private key scalar.
    });

    test('getPublicKey returns null before any keypair exists', () async {
      final dir = Directory.systemTemp.createTempSync('rain_keypair_3_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final db = _openTempDb(dir);
      addTearDown(db.close);
      final repo = IdentityKeyRepository(db, InMemoryKeyStoreService());
      await _seedIdentity(db);

      expect(await repo.getPublicKey(), isNull);
    });

    test('clear removes keypair from store and DB column', () async {
      final dir = Directory.systemTemp.createTempSync('rain_keypair_4_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final db = _openTempDb(dir);
      addTearDown(db.close);
      final store = InMemoryKeyStoreService();
      final repo = IdentityKeyRepository(db, store);
      await _seedIdentity(db);

      await repo.ensureKeyPair();
      expect(await repo.getPublicKey(), isNotNull);

      await repo.clear();
      expect(await repo.getPublicKey(), isNull);
      expect(await store.read(KeyStoreIds.identityPrivateKey), isNull);
    });
  });
}
