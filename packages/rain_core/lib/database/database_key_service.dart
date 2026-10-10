import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../identity/key_store_service.dart';

/// Generates and persists the DB encryption key for TASK-002 (SQLCipher).
///
/// Only the **key-bootstrap half** of TASK-002 is implemented here. The actual
/// SQLCipher open path + one-time plaintext→cipher file migration are DEFERRED
/// (they require a SQLCipher-enabled `sqlite3` native library; the legacy
/// `sqlcipher_flutter_libs` package is end-of-life and unverifiable in this
/// environment). This service makes the key available so the open path can
/// consume it once the native dependency is settled.
///
/// The key is 32 bytes (AES-256 / SQLCipher default), base64-wrapped, stored in
/// the OS-backed [KeyStoreService] under [KeyStoreIds.databaseKey].
final class DatabaseKeyService {
  DatabaseKeyService(this._store);

  final KeyStoreService _store;

  static const int _keyLengthBytes = 32;

  /// Returns the persisted base64 DB key, generating + storing it on first run.
  Future<String> ensureDatabaseKey() async {
    final existing = await _store.read(KeyStoreIds.databaseKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final key = _generateKey();
    final wrapped = base64Encode(key);
    await _store.write(KeyStoreIds.databaseKey, wrapped);
    return wrapped;
  }

  /// Returns the raw key bytes (used by the SQLCipher open path once wired).
  /// Throws [KeyStoreException] if the key is missing or corrupt.
  Future<Uint8List> getDatabaseKeyBytes() async {
    final wrapped = await _store.read(KeyStoreIds.databaseKey);
    if (wrapped == null || wrapped.isEmpty) {
      throw const KeyStoreException('Database encryption key not found.');
    }
    try {
      final bytes = base64Decode(wrapped);
      if (bytes.length != _keyLengthBytes) {
        throw const KeyStoreException(
          'Database encryption key has unexpected length.',
        );
      }
      return Uint8List.fromList(bytes);
    } on FormatException catch (e) {
      throw KeyStoreException('Database encryption key is corrupt.', e);
    }
  }

  /// Deletes the key (used by account reset / re-key).
  Future<void> clear() => _store.delete(KeyStoreIds.databaseKey);

  static Uint8List _generateKey() {
    final rng = Random.secure();
    final bytes = Uint8List(_keyLengthBytes);
    for (var i = 0; i < _keyLengthBytes; i += 1) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }
}
