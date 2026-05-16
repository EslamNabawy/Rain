import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
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

  test('background service is disabled by default', () async {
    final store = AppSettingsStore();

    expect(await store.loadBackgroundServiceEnabled(), isFalse);
  });

  test('background service setting is forced off', () async {
    final store = AppSettingsStore();

    await store.setBackgroundServiceEnabled(true);
    expect(await store.loadBackgroundServiceEnabled(), isFalse);

    await store.setBackgroundServiceEnabled(false);
    expect(await store.loadBackgroundServiceEnabled(), isFalse);
  });
}
