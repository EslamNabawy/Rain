import 'dart:convert';

/// Thrown when a [KeyStoreService] operation fails (e.g. platform keystore
/// unavailable, OS-level access denied).
class KeyStoreException implements Exception {
  const KeyStoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'KeyStoreException($message${cause == null ? '' : ': $cause'})';
}

/// OS/secure-storage-backed string secret store, keyed by an opaque id.
///
/// Implementations back this with Android Keystore (encryptedSharedPreferences),
/// iOS Keychain, or an encrypted file on Windows (documented as non-TPM for v1).
/// The interface is intentionally minimal and injectable so unit tests can use
/// an in-memory fake.
abstract interface class KeyStoreService {
  /// Reads a previously stored secret, or `null` if absent.
  Future<String?> read(String keyId);

  /// Writes (or overwrites) a secret.
  Future<void> write(String keyId, String value);

  /// Deletes a stored secret. Deleting a missing key is a no-op.
  Future<void> delete(String keyId);
}

/// In-memory [KeyStoreService] for tests and headless contexts.
final class InMemoryKeyStoreService implements KeyStoreService {
  InMemoryKeyStoreService([Map<String, String>? initial])
      : _store = <String, String>{...?initial};

  final Map<String, String> _store;

  @override
  Future<String?> read(String keyId) async => _store[keyId];

  @override
  Future<void> write(String keyId, String value) async {
    _store[keyId] = value;
  }

  @override
  Future<void> delete(String keyId) async {
    _store.remove(keyId);
  }
}

/// Base64 helpers for wrapping raw key bytes in a string secret.
final class KeyEncoding {
  const KeyEncoding._();

  static String encodeBytes(List<int> bytes) => base64Encode(bytes);

  static List<int> decodeBytes(String encoded) => base64Decode(encoded);
}

/// Stable key ids used by [KeyStoreService] consumers.
abstract final class KeyStoreIds {
  const KeyStoreIds._();

  /// Wrapped (base64) X25519 private key for the local identity.
  static const String identityPrivateKey = 'rain_identity_private_key';

  /// 32-byte base64 DB encryption key (used by TASK-002 SQLCipher).
  static const String databaseKey = 'rain_db_key';
}
