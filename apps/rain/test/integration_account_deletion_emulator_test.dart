/// # integration_account_deletion_emulator_test
///
/// Integration tests for account deletion via Firebase emulator, verifying tombstone creation and search index removal.
///
/// **Key types:** FirebaseEmulatorSignalingAdapter.
///
/// **Depends on:** Firebase Auth/Realtime Database emulator and signaling adapter.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'utils/firebase_emulator_signaling_adapter.dart';

const bool runIntegrationTests = bool.fromEnvironment(
  'RUN_RAIN_INTEGRATION_TESTS',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!runIntegrationTests) return;
    HttpOverrides.global = null;
  });

  tearDownAll(() {
    if (!runIntegrationTests) return;
    HttpOverrides.global = null;
  });

  test(
    'Firebase emulator deleteAccount tombstones backend identity and removes search',
    () async {
      final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final username = 'del$runId';
      final observer = 'obs$runId';
      const password = 'deletepw';

      final accountAdapter = FirebaseEmulatorSignalingAdapter();
      final observerAdapter = FirebaseEmulatorSignalingAdapter();

      try {
        await accountAdapter.register(username, password);
        await observerAdapter.register(observer, 'observerpw');
        await accountAdapter.login(username, password);
        await accountAdapter.deleteAccount(username);
        await observerAdapter.login(observer, 'observerpw');

        final tombstone = await observerAdapter.getRawForTest(<String>[
          'users',
          username,
        ]);
        expect(tombstone, isA<Map<Object?, Object?>>());
        final tombstoneMap = tombstone! as Map<Object?, Object?>;
        expect(tombstoneMap['uid'], isA<String>());
        expect(tombstoneMap['username'], username);
        expect(tombstoneMap['accountState'], 'deleted');
        expect(tombstoneMap['deletedAt'], isA<num>());
        expect(
          await observerAdapter.getRawForTest(<String>['userSearch', username]),
          isNull,
        );
        expect(
          await observerAdapter.getRawForTest(<String>[
            'presence',
            username,
            'online',
          ]),
          isFalse,
        );
      } finally {
        await accountAdapter.dispose();
        await observerAdapter.dispose();
      }
    },
    skip: runIntegrationTests ? null : 'Requires Firebase emulators',
  );

  test(
    'Firebase emulator tombstoned surviving Auth cannot recreate profile or search',
    () async {
      final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final username = 'survive$runId';
      const password = 'survivepw';

      final adapter = FirebaseEmulatorSignalingAdapter();

      try {
        final uid = await adapter.register(username, password);
        await adapter.login(username, password);
        final registeredAt = DateTime.now().millisecondsSinceEpoch;
        final deletedAt = registeredAt + 1;

        await adapter.deleteRawForTest(<String>['userSearch', username]);
        await adapter.putRawForTest(
          <String>['users', username],
          <String, Object?>{
            'username': username,
            'uid': uid,
            'displayName': 'Deleted account',
            'registeredAt': registeredAt,
            'accountState': 'deleted',
            'deletedAt': deletedAt,
          },
        );
        await adapter.signOut();
        expect(await adapter.login(username, password), uid);

        expect(await adapter.fetchIdentity(username), isNull);
        await expectLater(
          adapter.upsertIdentity(
            BackendIdentity(
              username: username,
              uid: uid,
              displayName: username,
              gender: null,
              registeredAt: registeredAt,
              lastSeen: registeredAt,
              lastHeartbeat: registeredAt,
              online: false,
            ),
          ),
          throwsA(isA<SignalingSessionExpiredException>()),
        );
        await expectLater(
          adapter.addToUserSearch(username),
          throwsA(isA<HttpException>()),
        );
        expect(
          await adapter.getRawForTest(<String>['users', username, 'uid']),
          uid,
        );
        expect(
          await adapter.getRawForTest(<String>[
            'users',
            username,
            'accountState',
          ]),
          'deleted',
        );
        expect(
          await adapter.getRawForTest(<String>['userSearch', username]),
          isNull,
        );
      } finally {
        await adapter.dispose();
      }
    },
    skip: runIntegrationTests ? null : 'Requires Firebase emulators',
  );
}
