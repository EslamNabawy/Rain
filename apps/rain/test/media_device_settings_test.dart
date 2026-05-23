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

  test(
    'device model keeps audio output and future video input kinds',
    () async {
      final platform = _FakePlatformBridge()
        ..devices = <MediaDeviceInfo>[
          MediaDeviceInfo(
            deviceId: 'mic-1',
            label: '',
            kind: audioInputDeviceKind,
          ),
          MediaDeviceInfo(
            deviceId: 'speaker-1',
            label: '',
            kind: audioOutputDeviceKind,
          ),
          MediaDeviceInfo(
            deviceId: 'camera-1',
            label: '',
            kind: videoInputDeviceKind,
          ),
        ];
      final service = MediaDeviceSettings(
        platformBridge: platform,
        settingsStore: AppSettingsStore(),
      );

      final devices = await service.loadMediaDevices();
      final outputs = await service.loadAudioOutputDevices();
      final cameras = await service.loadVideoInputDevices();

      expect(devices.map((device) => device.typedKind), <RainMediaDeviceKind>[
        RainMediaDeviceKind.audioInput,
        RainMediaDeviceKind.audioOutput,
        RainMediaDeviceKind.videoInput,
      ]);
      expect(devices[0].displayLabel(0), 'Microphone 1');
      expect(outputs.single.displayLabel(0), 'Speaker 1');
      expect(cameras.single.displayLabel(0), 'Camera 1');
      expect(cameras.single.isVideoInput, isTrue);
    },
  );

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

  test(
    'selected microphone test captures and disposes a short stream',
    () async {
      final stream = _FakeMediaStream('stream-1', _FakeMediaTrack('track-1'));
      final platform = _FakePlatformBridge()
        ..devices = <MediaDeviceInfo>[
          MediaDeviceInfo(
            deviceId: 'mic-1',
            label: 'Desk mic',
            kind: 'audioinput',
          ),
        ]
        ..userMediaStream = stream;
      final service = MediaDeviceSettings(
        platformBridge: platform,
        settingsStore: AppSettingsStore(),
      );

      await service.selectMicrophone('mic-1');
      await service.testSelectedMicrophoneAvailability();

      expect(platform.userMediaConstraints, hasLength(1));
      final constraints = platform.userMediaConstraints.single;
      expect(constraints['video'], isFalse);
      expect(constraints['audio'], containsPair('deviceId', 'mic-1'));
      expect(stream.audioTrack.stopped, isTrue);
      expect(stream.disposed, isTrue);
    },
  );

  test('selected microphone test rejects missing persisted device', () async {
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

    await expectLater(
      service.testSelectedMicrophoneAvailability(),
      throwsA(isA<StateError>()),
    );
    expect(platform.userMediaConstraints, isEmpty);
  });

  test('selected microphone test surfaces capture failures', () async {
    final platform = _FakePlatformBridge()
      ..devices = <MediaDeviceInfo>[
        MediaDeviceInfo(
          deviceId: 'mic-1',
          label: 'Desk mic',
          kind: 'audioinput',
        ),
      ]
      ..userMediaError = StateError('Microphone permission denied');
    final service = MediaDeviceSettings(
      platformBridge: platform,
      settingsStore: AppSettingsStore(),
    );

    await service.selectMicrophone('mic-1');

    await expectLater(
      service.testSelectedMicrophoneAvailability(),
      throwsA(isA<StateError>()),
    );
    expect(platform.userMediaConstraints, hasLength(1));
  });
}

class _FakePlatformBridge implements PlatformBridge {
  List<MediaDeviceInfo> devices = const <MediaDeviceInfo>[];
  final List<Map<String, dynamic>> userMediaConstraints =
      <Map<String, dynamic>>[];
  _FakeMediaStream? userMediaStream;
  Object? userMediaError;

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
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) async {
    userMediaConstraints.add(constraints);
    final error = userMediaError;
    if (error != null) {
      throw error;
    }
    return userMediaStream ??
        _FakeMediaStream('stream-default', _FakeMediaTrack('track-default'));
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

class _FakeMediaStream extends Fake implements MediaStream {
  _FakeMediaStream(this._id, this.audioTrack);

  final String _id;
  final _FakeMediaTrack audioTrack;
  bool disposed = false;

  @override
  String get id => _id;

  @override
  List<MediaStreamTrack> getAudioTracks() => <MediaStreamTrack>[audioTrack];

  @override
  List<MediaStreamTrack> getTracks() => <MediaStreamTrack>[audioTrack];

  @override
  List<MediaStreamTrack> getVideoTracks() => const <MediaStreamTrack>[];

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeMediaTrack extends Fake implements MediaStreamTrack {
  _FakeMediaTrack(this._id);

  final String _id;
  bool stopped = false;

  @override
  String? get id => _id;

  @override
  String? get kind => 'audio';

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
