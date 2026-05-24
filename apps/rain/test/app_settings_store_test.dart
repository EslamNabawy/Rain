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

  test('selected microphone persists locally', () async {
    final store = AppSettingsStore();

    expect(await store.loadSelectedMicrophoneDeviceId(), isNull);

    await store.setSelectedMicrophoneDeviceId(' external-mic ');
    expect(await store.loadSelectedMicrophoneDeviceId(), 'external-mic');

    await store.setSelectedMicrophoneDeviceId(null);
    expect(await store.loadSelectedMicrophoneDeviceId(), isNull);
  });

  test('audio settings load defaults', () async {
    final store = AppSettingsStore();

    final settings = await store.loadAudioSettings();

    expect(settings.soundEffectsEnabled, isTrue);
    expect(settings.soundEffectsVolume, 1.0);
    expect(settings.callSoundsEnabled, isTrue);
    expect(settings.reduceSoundsDuringCall, isTrue);
    expect(
      settings.defaultOutputPreference,
      CallAudioOutputPreference.systemDefault,
    );
  });

  test('sound effects toggle persists locally', () async {
    final store = AppSettingsStore();

    await store.setSoundEffectsEnabled(false);

    expect(await store.loadSoundEffectsEnabled(), isFalse);
    expect((await store.loadAudioSettings()).soundEffectsEnabled, isFalse);
  });

  test('call sounds toggle persists locally', () async {
    final store = AppSettingsStore();

    await store.setCallSoundsEnabled(false);

    expect(await store.loadCallSoundsEnabled(), isFalse);
    expect((await store.loadAudioSettings()).callSoundsEnabled, isFalse);
  });

  test('reduce sounds during call toggle persists locally', () async {
    final store = AppSettingsStore();

    await store.setReduceSoundsDuringCall(false);

    expect(await store.loadReduceSoundsDuringCall(), isFalse);
    expect((await store.loadAudioSettings()).reduceSoundsDuringCall, isFalse);
  });

  test('sound effects volume persists with bounds', () async {
    final store = AppSettingsStore();

    await store.setSoundEffectsVolume(0.35);
    expect(await store.loadSoundEffectsVolume(), 0.35);

    await store.setSoundEffectsVolume(8);
    expect(await store.loadSoundEffectsVolume(), 1.0);

    await store.setSoundEffectsVolume(-1);
    expect(await store.loadSoundEffectsVolume(), 0.0);
  });

  test('non-finite sound effects volume falls back to default', () async {
    final store = AppSettingsStore();

    await store.setSoundEffectsVolume(double.nan);

    expect(
      await store.loadSoundEffectsVolume(),
      AppSettingsStore.defaultSoundEffectsVolume,
    );
  });

  test('default call output preference persists locally', () async {
    final store = AppSettingsStore();

    await store.setDefaultCallAudioOutputPreference(
      CallAudioOutputPreference.bluetooth,
    );

    expect(
      await store.loadDefaultCallAudioOutputPreference(),
      CallAudioOutputPreference.bluetooth,
    );
    expect(
      (await store.loadAudioSettings()).defaultOutputPreference,
      CallAudioOutputPreference.bluetooth,
    );
  });
}
