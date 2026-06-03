import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  test(
    'authenticated session generation changes after explicit session end',
    () async {
      final container = _container();
      addTearDown(container.dispose);
      final identity =
          container.read(identityProvider.notifier)
              as _MutableIdentityController;
      await container.read(identityProvider.future);

      expect(container.read(authenticatedSessionProvider), isNull);

      identity.setIdentity(_identity('alice', displayName: 'Alice'));
      final first = container.read(authenticatedSessionProvider);

      expect(first?.identity.username, 'alice');
      expect(first?.sessionGeneration, 1);

      identity.setIdentity(_identity('alice', displayName: 'Alice Updated'));
      final updated = container.read(authenticatedSessionProvider);

      expect(updated?.identity.displayName, 'Alice Updated');
      expect(updated?.sessionGeneration, first?.sessionGeneration);

      container.read(authenticatedSessionProvider.notifier).endSession();
      expect(container.read(authenticatedSessionProvider), isNull);

      identity.setIdentity(_identity('alice', displayName: 'Alice Again'));
      final relogin = container.read(authenticatedSessionProvider);

      expect(relogin?.identity.username, 'alice');
      expect(relogin?.sessionGeneration, greaterThan(first!.sessionGeneration));
    },
  );

  test('recent searches reset at the session boundary', () async {
    final container = _container();
    addTearDown(container.dispose);
    final identity =
        container.read(identityProvider.notifier) as _MutableIdentityController;
    await container.read(identityProvider.future);

    identity.setIdentity(_identity('alice'));
    container.read(recentSearchesProvider.notifier).add('bob');

    expect(container.read(recentSearchesProvider), <String>['bob']);

    container.read(authenticatedSessionProvider.notifier).endSession();

    expect(container.read(recentSearchesProvider), isEmpty);
  });

  test('user search state resets at the session boundary', () async {
    final container = _container();
    addTearDown(container.dispose);
    final identity =
        container.read(identityProvider.notifier) as _MutableIdentityController;
    await container.read(identityProvider.future);

    identity.setIdentity(_identity('alice'));
    await container.read(userSearchProvider.notifier).search('a');

    expect(container.read(userSearchProvider).requireValue.query, 'a');

    container.read(authenticatedSessionProvider.notifier).endSession();

    expect(container.read(userSearchProvider).requireValue.query, isEmpty);
  });

  test(
    'message streams are empty while no authenticated session exists',
    () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final store = MessageStore(database);
      final envelope = await store.composeOutgoingEnvelope(
        from: 'alice',
        to: 'bob',
        content: 'must not leak while signed out',
      );
      await store.storeOutgoingEnvelope(envelope);

      final container = _container(database: database);
      addTearDown(container.dispose);

      final messages = await container.read(messagesProvider('bob').future);

      expect(messages, isEmpty);
    },
  );
}

ProviderContainer _container({RainDatabase? database}) {
  final db = database ?? RainDatabase(NativeDatabase.memory());
  if (database == null) {
    addTearDown(db.close);
  }
  return ProviderContainer(
    overrides: [
      identityProvider.overrideWith(_MutableIdentityController.new),
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          environment: AppEnvironment.fromEnvironment(
            runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
          ),
          database: db,
          adapter: NoopSignalingAdapter(),
          forceUpdateService: ForceUpdateService(
            remoteConfig: null,
            updateUrl: 'https://example.com',
          ),
        ),
      ),
    ],
  );
}

RainIdentity _identity(String username, {String? displayName}) {
  return RainIdentity(
    username: username,
    displayName: displayName ?? username,
    createdAt: 1,
    gender: RainGender.male,
  );
}

class _MutableIdentityController extends IdentityController {
  @override
  Future<RainIdentity?> build() async => null;

  void setIdentity(RainIdentity? identity) {
    state = AsyncValue.data(identity);
  }
}
