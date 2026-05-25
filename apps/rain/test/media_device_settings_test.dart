import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/media_device_settings.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
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

  test('device model classifies audio labels by transport hints', () {
    const bluetoothOutput = RainMediaDevice(
      deviceId: 'airpods-output',
      label: 'AirPods Pro Bluetooth',
      kind: audioOutputDeviceKind,
    );
    const wiredOutput = RainMediaDevice(
      deviceId: 'usb-output',
      label: 'USB-C Wired Headset',
      kind: audioOutputDeviceKind,
    );
    const wiredInput = RainMediaDevice(
      deviceId: 'usb-mic',
      label: 'USB-C Wired Headset Microphone',
      kind: audioInputDeviceKind,
    );
    const bluetoothInput = RainMediaDevice(
      deviceId: 'buds-mic',
      label: 'Galaxy Buds2 Bluetooth Microphone',
      kind: audioInputDeviceKind,
    );
    const usbInput = RainMediaDevice(
      deviceId: 'usb-table-mic',
      label: 'USB Studio Microphone',
      kind: audioInputDeviceKind,
    );
    const defaultInput = RainMediaDevice(
      deviceId: 'default-mic',
      label: 'Default mic',
      kind: audioInputDeviceKind,
    );
    const hiddenLabelInput = RainMediaDevice(
      deviceId: 'default-mic',
      label: '',
      kind: audioInputDeviceKind,
    );

    expect(bluetoothOutput.isBluetoothAudioOutput, isTrue);
    expect(bluetoothOutput.isWiredAudioOutput, isFalse);
    expect(wiredOutput.isWiredAudioOutput, isTrue);
    expect(wiredOutput.isBluetoothAudioOutput, isFalse);
    expect(wiredInput.isWiredAudioInput, isTrue);
    expect(wiredInput.isHeadsetAudioInput, isTrue);
    expect(wiredInput.displayLabel(0), 'Wired headset mic');
    expect(wiredInput.displayDetailLabel(0), 'USB-C Wired Headset Microphone');
    expect(bluetoothInput.isBluetoothAudioInput, isTrue);
    expect(bluetoothInput.displayLabel(0), 'Bluetooth mic');
    expect(usbInput.displayLabel(0), 'USB microphone');
    expect(defaultInput.displayLabel(0), 'Default microphone');
    expect(hiddenLabelInput.isHeadsetAudioInput, isFalse);
    expect(hiddenLabelInput.displayLabel(0), 'Microphone 1');
  });

  test(
    'audio output capabilities expose typed route and output hints',
    () async {
      final platform = _FakePlatformBridge()
        ..devices = <MediaDeviceInfo>[
          MediaDeviceInfo(
            deviceId: 'mic-1',
            label: 'Desk mic',
            kind: audioInputDeviceKind,
          ),
          MediaDeviceInfo(
            deviceId: 'speaker-1',
            label: 'Built-in Speaker',
            kind: audioOutputDeviceKind,
          ),
          MediaDeviceInfo(
            deviceId: 'bluetooth-1',
            label: 'Galaxy Buds2 Bluetooth',
            kind: audioOutputDeviceKind,
          ),
          MediaDeviceInfo(
            deviceId: 'wired-1',
            label: 'USB Headphones',
            kind: audioOutputDeviceKind,
          ),
        ];
      final store = AppSettingsStore();
      final service = MediaDeviceSettings(
        platformBridge: platform,
        settingsStore: store,
      );

      await store.setDefaultCallAudioOutputPreference(
        CallAudioOutputPreference.bluetooth,
      );
      final state = await service.loadAudioOutputCapabilities();

      expect(
        state.devices.map((RainMediaDevice device) => device.deviceId),
        <String>['speaker-1', 'bluetooth-1', 'wired-1'],
      );
      expect(state.selectedRoute, VoiceCallOutputRoute.bluetooth);
      expect(state.hasBluetoothOutput, isTrue);
      expect(state.hasWiredOutput, isTrue);
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

  test('video capabilities report no camera safely', () async {
    final service = MediaDeviceSettings(
      platformBridge: _FakePlatformBridge(),
      settingsStore: AppSettingsStore(),
    );

    final state = await service.loadVideoInputCapabilities();

    expect(state.devices, isEmpty);
    expect(state.availableVideoInputCount, 0);
    expect(state.selectedDeviceId, isNull);
    expect(state.labelsAvailable, isFalse);
    expect(state.supportsCameraSwitch, isFalse);
    expect(state.likelyHasRearFacingCamera, isFalse);
    expect(
      state.filterCallControls(const <CallControlCapability>[
        CallControlCapability.camera,
        CallControlCapability.switchCamera,
        CallControlCapability.hangUp,
      ]),
      const <CallControlCapability>[
        CallControlCapability.camera,
        CallControlCapability.hangUp,
      ],
    );
  });

  test(
    'video capabilities keep one Windows laptop camera non-switchable',
    () async {
      final platform = _FakePlatformBridge()
        ..devices = <MediaDeviceInfo>[
          MediaDeviceInfo(
            deviceId: 'integrated-camera',
            label: 'Integrated Webcam',
            kind: videoInputDeviceKind,
          ),
        ];
      final service = MediaDeviceSettings(
        platformBridge: platform,
        settingsStore: AppSettingsStore(),
      );

      final state = await service.loadVideoInputCapabilities();

      expect(state.availableVideoInputCount, 1);
      expect(state.devices.single.cameraFacing, RainCameraFacing.external);
      expect(state.labelsAvailable, isTrue);
      expect(state.supportsCameraSwitch, isFalse);
      expect(state.likelyHasRearFacingCamera, isFalse);
    },
  );

  test('video capabilities detect Android front and rear cameras', () async {
    final platform = _FakePlatformBridge()
      ..devices = <MediaDeviceInfo>[
        MediaDeviceInfo(
          deviceId: 'front-camera',
          label: 'Camera 0, Facing front',
          kind: videoInputDeviceKind,
        ),
        MediaDeviceInfo(
          deviceId: 'rear-camera',
          label: 'Camera 1, Facing back',
          kind: videoInputDeviceKind,
        ),
      ];
    final store = AppSettingsStore();
    final service = MediaDeviceSettings(
      platformBridge: platform,
      settingsStore: store,
    );

    await service.selectVideoInput('rear-camera');
    final state = await service.loadVideoInputCapabilities();

    expect(await store.loadSelectedVideoInputDeviceId(), 'rear-camera');
    expect(state.availableVideoInputCount, 2);
    expect(state.selectedDeviceId, 'rear-camera');
    expect(state.selectedDevice?.displayLabel(1), 'Camera 1, Facing back');
    expect(
      state.devices.map((RainMediaDevice device) => device.cameraFacing),
      <RainCameraFacing>[RainCameraFacing.front, RainCameraFacing.rear],
    );
    expect(state.labelsAvailable, isTrue);
    expect(state.supportsCameraSwitch, isTrue);
    expect(state.likelyHasRearFacingCamera, isTrue);
    expect(
      state.filterCallControls(const <CallControlCapability>[
        CallControlCapability.camera,
        CallControlCapability.switchCamera,
        CallControlCapability.hangUp,
      ]),
      const <CallControlCapability>[
        CallControlCapability.camera,
        CallControlCapability.switchCamera,
        CallControlCapability.hangUp,
      ],
    );
  });

  test(
    'video capabilities do not assume rear camera when labels are hidden',
    () async {
      final platform = _FakePlatformBridge()
        ..devices = <MediaDeviceInfo>[
          MediaDeviceInfo(
            deviceId: 'camera-1',
            label: '',
            kind: videoInputDeviceKind,
          ),
          MediaDeviceInfo(
            deviceId: 'camera-2',
            label: '',
            kind: videoInputDeviceKind,
          ),
        ];
      final service = MediaDeviceSettings(
        platformBridge: platform,
        settingsStore: AppSettingsStore(),
      );

      final state = await service.loadVideoInputCapabilities();

      expect(state.availableVideoInputCount, 2);
      expect(state.devices.first.displayLabel(0), 'Camera 1');
      expect(state.labelsAvailable, isFalse);
      expect(state.supportsCameraSwitch, isFalse);
      expect(state.likelyHasRearFacingCamera, isFalse);
      expect(
        state.devices.map((RainMediaDevice device) => device.cameraFacing),
        <RainCameraFacing>[RainCameraFacing.unknown, RainCameraFacing.unknown],
      );
    },
  );

  test('missing selected video input falls back to default', () async {
    final platform = _FakePlatformBridge()
      ..devices = <MediaDeviceInfo>[
        MediaDeviceInfo(
          deviceId: 'camera-1',
          label: 'Camera',
          kind: videoInputDeviceKind,
        ),
      ];
    final service = MediaDeviceSettings(
      platformBridge: platform,
      settingsStore: AppSettingsStore(),
    );

    await service.selectVideoInput('missing-camera');
    final state = await service.loadVideoInputCapabilities();

    expect(state.selectedDeviceId, isNull);
    expect(state.missingSelectedDeviceId, 'missing-camera');
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
      final stream = _FakeMediaStream(
        'stream-1',
        _FakeMediaTrack('track-1', 'audio'),
      );
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

  test('startup permission warmup probes microphone and camera once', () async {
    final audioStream = _FakeMediaStream(
      'audio-stream',
      _FakeMediaTrack('audio-track', 'audio'),
    );
    final videoStream = _FakeMediaStream(
      'video-stream',
      _FakeMediaTrack('unused-audio-track', 'audio'),
      _FakeMediaTrack('video-track', 'video'),
    );
    final platform = _FakePlatformBridge()
      ..userMediaStreams.addAll(<_FakeMediaStream>[audioStream, videoStream]);
    final store = AppSettingsStore();
    final service = MediaDeviceSettings(
      platformBridge: platform,
      settingsStore: store,
    );

    final result = await service.warmUpStartupCallPermissions();

    expect(result.microphoneReady, isTrue);
    expect(result.cameraReady, isTrue);
    expect(await store.loadStartupMicrophoneWarmupCompleted(), isTrue);
    expect(await store.loadStartupCameraWarmupCompleted(), isTrue);
    expect(platform.userMediaConstraints, hasLength(2));
    expect(platform.userMediaConstraints[0]['video'], isFalse);
    expect(platform.userMediaConstraints[0]['audio'], isA<Map>());
    expect(platform.userMediaConstraints[1], <String, dynamic>{
      'audio': false,
      'video': true,
    });
    expect(audioStream.audioTrack.stopped, isTrue);
    expect(videoStream.videoTrack?.stopped, isTrue);

    platform.userMediaConstraints.clear();
    await service.warmUpStartupCallPermissions();

    expect(platform.userMediaConstraints, isEmpty);
  });

  test(
    'startup permission warmup records partial failures without skipping camera',
    () async {
      final videoStream = _FakeMediaStream(
        'video-stream',
        _FakeMediaTrack('unused-audio-track', 'audio'),
        _FakeMediaTrack('video-track', 'video'),
      );
      final platform = _FakePlatformBridge()
        ..userMediaErrors.add(StateError('Microphone permission denied'))
        ..userMediaStreams.add(videoStream);
      final store = AppSettingsStore();
      final service = MediaDeviceSettings(
        platformBridge: platform,
        settingsStore: store,
      );

      await expectLater(
        service.warmUpStartupCallPermissions(),
        throwsA(
          isA<StartupMediaPermissionWarmupException>()
              .having(
                (error) => error.microphoneError,
                'microphoneError',
                isA<StateError>(),
              )
              .having((error) => error.cameraError, 'cameraError', isNull),
        ),
      );

      expect(platform.userMediaConstraints, hasLength(2));
      expect(await store.loadStartupMicrophoneWarmupCompleted(), isFalse);
      expect(await store.loadStartupCameraWarmupCompleted(), isTrue);
      expect(videoStream.videoTrack?.stopped, isTrue);
    },
  );
}

class _FakePlatformBridge implements PlatformBridge {
  List<MediaDeviceInfo> devices = const <MediaDeviceInfo>[];
  final List<Map<String, dynamic>> userMediaConstraints =
      <Map<String, dynamic>>[];
  final List<_FakeMediaStream> userMediaStreams = <_FakeMediaStream>[];
  final List<Object> userMediaErrors = <Object>[];
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
    if (userMediaErrors.isNotEmpty) {
      throw userMediaErrors.removeAt(0);
    }
    final error = userMediaError;
    if (error != null) {
      throw error;
    }
    if (userMediaStreams.isNotEmpty) {
      return userMediaStreams.removeAt(0);
    }
    return userMediaStream ??
        _FakeMediaStream(
          'stream-default',
          _FakeMediaTrack('track-default', 'audio'),
        );
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
  Future<void> switchCamera(MediaStreamTrack track) async {}

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
  _FakeMediaStream(this._id, this.audioTrack, [this.videoTrack]);

  final String _id;
  final _FakeMediaTrack audioTrack;
  final _FakeMediaTrack? videoTrack;
  bool disposed = false;

  @override
  String get id => _id;

  @override
  List<MediaStreamTrack> getAudioTracks() => <MediaStreamTrack>[audioTrack];

  @override
  List<MediaStreamTrack> getTracks() => <MediaStreamTrack>[
    audioTrack,
    ?videoTrack,
  ];

  @override
  List<MediaStreamTrack> getVideoTracks() => <MediaStreamTrack>[?videoTrack];

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeMediaTrack extends Fake implements MediaStreamTrack {
  _FakeMediaTrack(this._id, this._kind);

  final String _id;
  final String _kind;
  bool stopped = false;

  @override
  String? get id => _id;

  @override
  String? get kind => _kind;

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
