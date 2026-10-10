import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/database/database_key_service.dart';
import 'package:rain_core/identity/key_store_service.dart';

void main() {
  group('TASK-002 DatabaseKeyService (key bootstrap)', () {
    test('generates a 32-byte base64 key once and persists it', () async {
      final store = InMemoryKeyStoreService();
      final service = DatabaseKeyService(store);

      final first = await service.ensureDatabaseKey();
      final bytes = base64Decode(first);
      expect(bytes.length, 32);

      // Idempotent: same key returned, nothing new written.
      final again = await service.ensureDatabaseKey();
      expect(again, first);
      expect(await store.read(KeyStoreIds.databaseKey), first);
    });

    test('getDatabaseKeyBytes returns the raw key', () async {
      final store = InMemoryKeyStoreService();
      final service = DatabaseKeyService(store);
      await service.ensureDatabaseKey();

      final bytes = await service.getDatabaseKeyBytes();
      expect(bytes, isA<Uint8List>());
      expect(bytes.length, 32);
    });

    test('getDatabaseKeyBytes throws when key missing', () async {
      final service = DatabaseKeyService(InMemoryKeyStoreService());
      expect(
        () => service.getDatabaseKeyBytes(),
        throwsA(isA<KeyStoreException>()),
      );
    });

    test('clear removes the persisted key', () async {
      final store = InMemoryKeyStoreService();
      final service = DatabaseKeyService(store);
      await service.ensureDatabaseKey();
      expect(await service.getDatabaseKeyBytes(), isA<Uint8List>());

      await service.clear();
      expect(await store.read(KeyStoreIds.databaseKey), isNull);
      expect(
        () => service.getDatabaseKeyBytes(),
        throwsA(isA<KeyStoreException>()),
      );
    });
  });
}
