import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/application/state/core_providers.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

ProviderContainer _container(RainDatabase database) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          environment: AppEnvironment.fromEnvironment(
            runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
          ),
          database: database,
          adapter: NoopSignalingAdapter(),
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
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  group('TASK-003 runtime_providers unit tests', () {
    test('appEnvironmentProvider and databaseProvider resolve from bootstrap',
        () async {
      final database = RainDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final container = _container(database);
      addTearDown(container.dispose);

      expect(
        container.read(appEnvironmentProvider),
        isA<AppEnvironment>(),
      );
      expect(container.read(databaseProvider), same(database));
    });
  });
}
