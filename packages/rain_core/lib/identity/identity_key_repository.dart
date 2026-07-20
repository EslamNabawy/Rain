import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:rain_core/database/rain_database.dart';

import 'key_store_service.dart';

/// Generates and persists a per-install X25519 identity keypair.
///
/// Private key (base64) is stored in the OS-backed [KeyStoreService]; the
/// public key is persisted in [RainDatabase] ([IdentityTable.signingPublicKey])
/// and later published to RTDB (TASK-015.5). Generate-once: a second
/// [ensureKeyPair] returns the existing public key.
///
/// TASK-015 (keystone): this is the safe key home that unblocks per-pair E2E
/// (TASK-001) and SQLCipher (TASK-002).
final class IdentityKeyRepository {
  IdentityKeyRepository(this._database, this._store);

  final RainDatabase _database;
  final KeyStoreService _store;

  static const String _storeId = KeyStoreIds.identityPrivateKey;

  /// Returns the public key, generating + persisting the keypair on first run.
  Future<SimplePublicKey> ensureKeyPair() async {
    final existing = await _readPublicKey();
    if (existing != null) {
      return existing;
    }

    final keyPair = await X25519().newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    final public = await keyPair.extractPublicKey();

    await _store.write(_storeId, KeyEncoding.encodeBytes(privateBytes));
    await _persistPublicKey(public.bytes);

    return public;
  }

  /// Returns the stored public key, or `null` if no keypair exists yet.
  Future<SimplePublicKey?> getPublicKey() => _readPublicKey();

  /// Reads the wrapped private key bytes from the store.
  /// Throws [KeyStoreException] if the key is missing or unreadable.
  Future<List<int>> getPrivateKeyBytes() async {
    final wrapped = await _store.read(_storeId);
    if (wrapped == null) {
      throw const KeyStoreException(
        'Identity private key not found in secure store.',
      );
    }
    try {
      return KeyEncoding.decodeBytes(wrapped);
    } on FormatException catch (e) {
      throw KeyStoreException('Identity private key is corrupt.', e);
    }
  }

  /// Deletes the keypair (store + DB column). Used by account reset.
  Future<void> clear() async {
    await _store.delete(_storeId);
    await _database.serializedTransaction(() async {
      await (_database.update(
        _database.identityTable,
      )..where((IdentityTable table) => table.id.isBiggerThanValue(0))).write(
        const IdentityTableCompanion(signingPublicKey: Value<String?>(null)),
      );
    });
  }

  Future<SimplePublicKey?> _readPublicKey() async {
    final row = await (_database.select(
      _database.identityTable,
    )..limit(1)).getSingleOrNull();
    final encoded = row?.signingPublicKey;
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      return SimplePublicKey(
        KeyEncoding.decodeBytes(encoded),
        type: KeyPairType.x25519,
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _persistPublicKey(List<int> publicBytes) async {
    await _database.serializedTransaction(() async {
      await (_database.update(
        _database.identityTable,
      )..where((IdentityTable table) => table.id.isBiggerThanValue(0))).write(
        IdentityTableCompanion(
          signingPublicKey: Value<String>(KeyEncoding.encodeBytes(publicBytes)),
        ),
      );
    });
  }
}
