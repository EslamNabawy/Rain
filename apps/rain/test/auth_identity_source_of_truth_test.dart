import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  test('cached identity is cleared when backend account is deleted', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await IdentityRepository(database).saveIdentity(
      const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: RainGender.female,
      ),
    );
    final adapter = _AuthValidationAdapter(
      currentUidValue: 'uid-alice',
      backendIdentity: null,
    );
    final container = _container(database, adapter);
    addTearDown(container.dispose);

    final identity = await container.read(identityProvider.future);

    expect(identity, isNull);
    expect(await IdentityRepository(database).loadIdentity(), isNull);
    expect(adapter.ensureSignedInAsCalls, 1);
    expect(adapter.fetchIdentityCalls, 1);
    expect(adapter.signOutCalls, 1);
    expect(adapter.upsertedIdentities, isEmpty);
  });

  test(
    'cached identity is cleared when Firebase user does not own backend user',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await IdentityRepository(database).saveIdentity(
        const RainIdentity(
          username: 'alice',
          displayName: 'Alice',
          createdAt: 1,
          gender: RainGender.female,
        ),
      );
      final adapter = _AuthValidationAdapter(
        currentUidValue: 'uid-other',
        backendIdentity: _backendAlice(uid: 'uid-alice'),
      );
      final container = _container(database, adapter);
      addTearDown(container.dispose);

      final identity = await container.read(identityProvider.future);

      expect(identity, isNull);
      expect(await IdentityRepository(database).loadIdentity(), isNull);
      expect(adapter.signOutCalls, 1);
      expect(adapter.upsertedIdentities, isEmpty);
    },
  );

  test(
    'backend identity wins over stale local display data during restoration',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await IdentityRepository(database).saveIdentity(
        const RainIdentity(
          username: 'alice',
          displayName: 'Old Alice',
          createdAt: 1,
          gender: RainGender.female,
        ),
      );
      final adapter = _AuthValidationAdapter(
        currentUidValue: 'uid-alice',
        backendIdentity: _backendAlice(
          uid: 'uid-alice',
          displayName: 'Alice Backend',
          registeredAt: 42,
          gender: 'male',
        ),
      );
      final container = _container(database, adapter);
      addTearDown(container.dispose);

      final identity = await container.read(identityProvider.future);
      final cached = await IdentityRepository(database).loadIdentity();

      expect(identity?.displayName, 'Alice Backend');
      expect(identity?.createdAt, 42);
      expect(identity?.gender, RainGender.male);
      expect(cached?.displayName, 'Alice Backend');
      expect(adapter.upsertedIdentities, isEmpty);
      expect(adapter.signOutCalls, 0);
    },
  );

  test(
    'registration backend save failure signs out and does not cache identity',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final adapter = _AuthValidationAdapter(
        currentUidValue: 'uid-alice',
        backendIdentity: null,
        upsertError: Exception('permission denied'),
      );
      final container = _container(database, adapter);
      addTearDown(container.dispose);

      await container.read(identityProvider.future);

      await expectLater(
        container
            .read(identityProvider.notifier)
            .register(
              username: 'alice',
              displayName: 'Alice',
              password: 'secret1',
              gender: RainGender.female,
            ),
        throwsA(isA<Exception>()),
      );

      expect(adapter.registerCalls, 1);
      expect(adapter.addToUserSearchCalls, 1);
      expect(adapter.upsertedIdentities, hasLength(1));
      expect(adapter.setPresenceCalls, 0);
      expect(adapter.signOutCalls, 1);
      expect(await IdentityRepository(database).loadIdentity(), isNull);
    },
  );

  test(
    'login does not recreate a missing backend account after authentication',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final adapter = _AuthValidationAdapter(
        currentUidValue: 'uid-alice',
        backendIdentity: null,
      );
      final container = _container(database, adapter);
      addTearDown(container.dispose);

      await container.read(identityProvider.future);

      await expectLater(
        container
            .read(identityProvider.notifier)
            .login(username: 'alice', password: 'secret1'),
        throwsA(isA<SignalingSessionExpiredException>()),
      );

      expect(adapter.loginCalls, 1);
      expect(adapter.fetchIdentityCalls, 1);
      expect(adapter.addToUserSearchCalls, 0);
      expect(adapter.upsertedIdentities, isEmpty);
      expect(adapter.setPresenceCalls, 0);
      expect(adapter.signOutCalls, 1);
      expect(await IdentityRepository(database).loadIdentity(), isNull);
    },
  );

  test(
    'login reports deleted account when local delete marker exists',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await AppSettingsStore().rememberDeletedRainUsername('alice');
      final adapter = _AuthValidationAdapter(
        currentUidValue: 'uid-alice',
        backendIdentity: null,
        loginError: Exception(
          'Wrong password. Check the password and try again.',
        ),
      );
      final container = _container(database, adapter);
      addTearDown(container.dispose);

      await container.read(identityProvider.future);

      await expectLater(
        container
            .read(identityProvider.notifier)
            .login(username: 'Alice', password: 'secret1'),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('was deleted on this device'),
          ),
        ),
      );

      expect(adapter.loginCalls, 1);
      expect(adapter.fetchIdentityCalls, 0);
      expect(adapter.signOutCalls, 0);
      expect(await IdentityRepository(database).loadIdentity(), isNull);
    },
  );
}

ProviderContainer _container(
  RainDatabase database,
  _AuthValidationAdapter adapter,
) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          environment: AppEnvironment.fromEnvironment(
            runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
          ),
          database: database,
          adapter: adapter,
          forceUpdateService: ForceUpdateService(
            remoteConfig: null,
            updateUrl: 'https://example.com',
          ),
        ),
      ),
      networkStatusProvider.overrideWith(
        (Ref ref) =>
            Stream<NetworkStatusState>.value(const NetworkStatusState.online()),
      ),
      keyStoreServiceProvider.overrideWithValue(InMemoryKeyStoreService()),
    ],
  );
}

BackendIdentity _backendAlice({
  required String uid,
  String displayName = 'Alice',
  int registeredAt = 1,
  String? gender = 'female',
}) {
  return BackendIdentity(
    username: 'alice',
    uid: uid,
    displayName: displayName,
    gender: gender,
    registeredAt: registeredAt,
    lastSeen: 10,
    lastHeartbeat: 10,
    online: true,
  );
}

final class _AuthValidationAdapter extends NoopSignalingAdapter {
  _AuthValidationAdapter({
    required this.currentUidValue,
    required this.backendIdentity,
    this.upsertError,
    this.loginError,
  });

  final String currentUidValue;
  final BackendIdentity? backendIdentity;
  final Object? upsertError;
  final Object? loginError;
  final List<BackendIdentity> upsertedIdentities = <BackendIdentity>[];
  int ensureSignedInAsCalls = 0;
  int fetchIdentityCalls = 0;
  int registerCalls = 0;
  int publishSigningKeyCalls = 0;
  int loginCalls = 0;
  int addToUserSearchCalls = 0;
  int setPresenceCalls = 0;
  int signOutCalls = 0;

  @override
  Future<void> ensureSignedInAs(String username) async {
    ensureSignedInAsCalls += 1;
  }

  @override
  Future<String> currentUid() async => currentUidValue;

  @override
  Future<String> register(String username, String password) async {
    registerCalls += 1;
    return currentUidValue;
  }

  @override
  Future<void> publishIdentitySigningKey({
    required String username,
    required String signingPublicKey,
  }) async {
    publishSigningKeyCalls += 1;
  }

  @override
  Future<String> login(String username, String password) async {
    loginCalls += 1;
    final error = loginError;
    if (error != null) {
      throw error;
    }
    return currentUidValue;
  }

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async {
    fetchIdentityCalls += 1;
    if (backendIdentity?.username == username) {
      return backendIdentity;
    }
    return null;
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }

  @override
  Future<void> addToUserSearch(String username) async {
    addToUserSearchCalls += 1;
  }

  @override
  Future<void> upsertIdentity(BackendIdentity identity) async {
    upsertedIdentities.add(identity);
    final error = upsertError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> setPresence(String username, bool online) async {
    setPresenceCalls += 1;
  }
}
