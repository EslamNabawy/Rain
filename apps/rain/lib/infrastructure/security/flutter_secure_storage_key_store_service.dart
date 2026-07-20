import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rain_core/rain_core.dart';

/// OS-backed [KeyStoreService] built on `flutter_secure_storage`.
///
/// - Android: encryptedSharedPreferences (Android Keystore-backed).
/// - iOS: Keychain.
/// - Windows/Linux: encrypted file (documented as non-TPM for v1 — accepted
///   per TASK-015 risk note).
///
/// TASK-015 (keystone): safe home for the identity private key + DB key.
final class FlutterSecureStorageKeyStoreService implements KeyStoreService {
  FlutterSecureStorageKeyStoreService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String keyId) async {
    try {
      return await _storage.read(key: keyId);
    } on PlatformException catch (e) {
      throw KeyStoreException('Failed to read key "$keyId".', e);
    }
  }

  @override
  Future<void> write(String keyId, String value) async {
    try {
      await _storage.write(key: keyId, value: value);
    } on PlatformException catch (e) {
      throw KeyStoreException('Failed to write key "$keyId".', e);
    }
  }

  @override
  Future<void> delete(String keyId) async {
    try {
      await _storage.delete(key: keyId);
    } on PlatformException catch (e) {
      throw KeyStoreException('Failed to delete key "$keyId".', e);
    }
  }
}
