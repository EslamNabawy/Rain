import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/media_device_settings.dart';
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

  test('device list filters audio inputs', () async {
    final platform = _FakePlatformBridge()
      ..devices = <MediaDeviceInfo>[
        MediaDeviceInfo(
          deviceId: 'mic-1',
          label: 'Desk mic',
          kind: 'audioinput',
        ),
        MediaDeviceInfo(
          deviceId: 'speaker-1',
          label: 'Speakers',
          kind: 'audiooutput',
        ),
        MediaDeviceInfo(
          deviceId: 'camera-1',
          label: 'Camera',
          kind: 'videoinput',
        ),
      ];
    final service = MediaDeviceSettings(
      platformBridge: platform,
      settingsStore: AppSettingsStore(),
    );

    final devices = await service.loadAudioInputDevices();

    expect(devices, hasLength(1));
    expect(devices.single.deviceId, 'mic-1');
    expect(devices.single.label, 'Desk mic');
  });

  test('selected microphone persists and resolves when available', () async {
    final platform = _FakePlatformBridge()
      ..devices = <MediaDeviceInfo>[
        MediaDeviceInfo(
          deviceId: 'mic-1',
          label: 'Desk mic',
          kind: 'audioinput',
        ),
      ];
    final store = AppSettingsStore();
    final service = MediaDeviceSettings(
      platformBridge: platform,
      settingsStore: store,
    );

    await service.selectMicrophone('mic-1');
    final state = await service.loadMicrophoneSelection();

    expect(await store.loadSelectedMicrophoneDeviceId(), 'mic-1');
    expect(state.selectedDeviceId, 'mic-1');
    expect(state.missingSelectedDeviceId, isNull);
  });

  test('missing selected microphone falls back to default', () async {
    final platform = _FakePlatformBridge()
      ..devices = <MediaDeviceInfo>[
        MediaDeviceInfo(
          deviceId: 'mic-1',
          label: 'Desk mic',
          kind: 'audioinput',
        ),
      ];
    final service = MediaDeviceSettings(
      platformBridge: platform,
      settingsStore: AppSettingsStore(),
    );

    await service.selectMicrophone('missing-mic');
    final state = await service.loadMicrophoneSelection();

    expect(state.selectedDeviceId, isNull);
    expect(state.missingSelectedDeviceId, 'missing-mic');
    expect(state.hasMissingSelection, isTrue);
  });

  test('empty device list leaves default selected', () async {
    final service = MediaDeviceSettings(
      platformBridge: _FakePlatformBridge(),
      settingsStore: AppSettingsStore(),
    );

    final state = await service.loadMicrophoneSelection();

    expect(state.devices, isEmpty);
    expect(state.selectedDeviceId, isNull);
    expect(state.hasMissingSelection, isFalse);
  });
}

class _FakePlatformBridge implements PlatformBridge {
  List<MediaDeviceInfo> devices = const <MediaDeviceInfo>[];

  @override
  Future<List<MediaDeviceInfo>> enumerateMediaDevices() async => devices;

  @override
  Future<RTCPeerConnection> createPeerConnection(Map<String, dynamic> config) {
    throw UnimplementedError();
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    RTCPeerConnection pc,
    String label,
    RTCDataChannelInit opts,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) {
    throw UnimplementedError();
  }

  @override
  StorageBackend getLocalStorage() => MemoryStorageBackend();

  @override
  Future<void> prepareVoiceAudio() async {}

  @override
  Future<void> clearVoiceAudio() async {}

  @override
  Future<void> setMicrophoneMuted(
    MediaStreamTrack track, {
    required bool muted,
  }) async {}

  @override
  Future<void> selectAudioInput(String deviceId) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> setSpeakerphoneOn(bool enabled) async {}

  @override
  Future<void> setSpeakerphoneOnButPreferBluetooth() async {}
}
