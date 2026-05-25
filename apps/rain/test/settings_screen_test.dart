import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/crash_diagnostics_service.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain/presentation/screens/settings_screen.dart';
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

  testWidgets('settings screen loads voice audio defaults', (
    WidgetTester tester,
  ) async {
    final harness = _SettingsHarness();
    addTearDown(harness.dispose);

    await tester.pumpSettingsScreen(harness: harness);

    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Test microphone'), findsOneWidget);
    expect(find.text('Default call output'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
    expect(find.text('Sound effects'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Call sounds'), findsOneWidget);
    expect(find.text('Reduce during calls'), findsOneWidget);
  });

  testWidgets('settings screen exposes debug sound diagnostics', (
    WidgetTester tester,
  ) async {
    _useTallView(tester);
    final harness = _SettingsHarness();
    addTearDown(harness.dispose);

    await tester.pumpSettingsScreen(harness: harness);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('App sound diagnostics'), findsOneWidget);
    expect(find.textContaining('Last: none'), findsOneWidget);
  });

  testWidgets('microphone selection persists from settings', (
    WidgetTester tester,
  ) async {
    final harness = _SettingsHarness(
      platformBridge: _FakePlatformBridge()
        ..devices = <MediaDeviceInfo>[
          MediaDeviceInfo(
            deviceId: 'mic-1',
            label: 'Desk mic',
            kind: 'audioinput',
          ),
        ],
    );
    addTearDown(harness.dispose);

    await tester.pumpSettingsScreen(harness: harness);
    await tester.tap(find.byTooltip('Choose microphone'));
    await tester.pumpSettingsFrame();
    await tester.tap(find.text('Desk mic').last);
    await tester.pumpSettingsFrame();

    expect(await AppSettingsStore().loadSelectedMicrophoneDeviceId(), 'mic-1');
  });

  testWidgets(
    'output route control hides bluetooth unless bluetooth output is available',
    (WidgetTester tester) async {},
    skip: true,
  );

  testWidgets(
    'settings microphone picker shows real audio inputs including wired headset labels',
    (WidgetTester tester) async {
      final harness = _SettingsHarness(
        platformBridge: _FakePlatformBridge()
          ..devices = <MediaDeviceInfo>[
            MediaDeviceInfo(
              deviceId: 'built-in-mic',
              label: 'Built-in microphone',
              kind: 'audioinput',
            ),
            MediaDeviceInfo(
              deviceId: 'wired-headset-mic',
              label: 'USB-C Wired Headset Microphone',
              kind: 'audioinput',
            ),
          ],
      );
      addTearDown(harness.dispose);

      await tester.pumpSettingsScreen(harness: harness);
      await tester.tap(find.byTooltip('Choose microphone'));
      await tester.pumpSettingsFrame();

      expect(find.text('Built-in microphone'), findsOneWidget);
      expect(find.text('USB-C Wired Headset Microphone'), findsOneWidget);

      await tester.tap(find.text('USB-C Wired Headset Microphone').last);
      await tester.pumpSettingsFrame();

      expect(
        await AppSettingsStore().loadSelectedMicrophoneDeviceId(),
        'wired-headset-mic',
      );
    },
  );

  testWidgets('camera selection persists from settings', (
    WidgetTester tester,
  ) async {
    _useTallView(tester);
    final harness = _SettingsHarness(
      platformBridge: _FakePlatformBridge()
        ..devices = <MediaDeviceInfo>[
          MediaDeviceInfo(
            deviceId: 'default-mic',
            label: 'Default mic',
            kind: 'audioinput',
          ),
          MediaDeviceInfo(
            deviceId: 'front-camera',
            label: 'Front Camera',
            kind: 'videoinput',
          ),
          MediaDeviceInfo(
            deviceId: 'rear-camera',
            label: 'Back Camera',
            kind: 'videoinput',
          ),
        ],
    );
    addTearDown(harness.dispose);

    await tester.pumpSettingsScreen(harness: harness);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpSettingsFrame();
    await tester.tap(find.byTooltip('Choose camera'));
    await tester.pumpSettingsFrame();
    await tester.tap(find.text('Back Camera').last);
    await tester.pumpSettingsFrame();

    expect(
      await AppSettingsStore().loadSelectedVideoInputDeviceId(),
      'rear-camera',
    );
  });

  testWidgets('sound effects toggle persists from settings', (
    WidgetTester tester,
  ) async {
    _useTallView(tester);
    final harness = _SettingsHarness();
    addTearDown(harness.dispose);

    await tester.pumpSettingsScreen(harness: harness);
    await tester.tap(find.text('Sound effects'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await AppSettingsStore().loadSoundEffectsEnabled(), isFalse);
  });

  testWidgets('call sounds toggle persists from settings', (
    WidgetTester tester,
  ) async {
    _useTallView(tester);
    final harness = _SettingsHarness();
    addTearDown(harness.dispose);

    await tester.pumpSettingsScreen(harness: harness);
    await tester.tap(find.text('Call sounds'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(await AppSettingsStore().loadCallSoundsEnabled(), isFalse);
  });

  testWidgets('device refresh handles permission denied', (
    WidgetTester tester,
  ) async {
    final harness = _SettingsHarness(
      platformBridge: _FakePlatformBridge()
        ..enumerateError = StateError('Microphone permission denied'),
    );
    addTearDown(harness.dispose);

    await tester.pumpSettingsScreen(harness: harness);
    await tester.tap(find.byTooltip('Refresh microphones'));
    await tester.pumpSettingsFrame();

    expect(find.text('Microphones unavailable'), findsOneWidget);
    expect(find.text('Microphone permission denied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings screen does not overflow on narrow mobile', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final harness = _SettingsHarness();
    addTearDown(harness.dispose);

    await tester.pumpSettingsScreen(harness: harness);

    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
    await tester.pump();
  });
}

void _useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

extension _SettingsPump on WidgetTester {
  Future<void> pumpSettingsScreen({required _SettingsHarness harness}) async {
    await pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(harness.bootstrap),
          platformBridgeProvider.overrideWithValue(harness.platformBridge),
          identityProvider.overrideWith(_NoIdentityController.new),
          runtimeControllerProvider.overrideWith(_NoRuntimeController.new),
          friendsProvider.overrideWith(_NoFriendsController.new),
          crashDiagnosticsServiceProvider.overrideWithValue(
            harness.crashDiagnostics,
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await pumpSettingsFrame();
  }

  Future<void> pumpSettingsFrame() async {
    await pump();
    await pump(const Duration(milliseconds: 300));
  }
}

class _SettingsHarness {
  _SettingsHarness({_FakePlatformBridge? platformBridge})
    : platformBridge = platformBridge ?? _FakePlatformBridge(),
      database = RainDatabase(NativeDatabase.memory()),
      diagnosticsDirectory = Directory.systemTemp.createTempSync(
        'rain_settings_test_',
      ) {
    crashDiagnostics = CrashDiagnosticsService(
      directoryProvider: () async => diagnosticsDirectory,
      appInfoProvider: () async => const CrashDiagnosticsAppInfo.unknown(),
    );
    bootstrap = AppBootstrapState(
      environment: AppEnvironment.fromEnvironment(
        runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
      ),
      database: database,
      adapter: NoopSignalingAdapter(),
      forceUpdateService: ForceUpdateService(
        remoteConfig: null,
        updateUrl: 'https://example.com',
      ),
    );
  }

  final _FakePlatformBridge platformBridge;
  final RainDatabase database;
  final Directory diagnosticsDirectory;
  late final CrashDiagnosticsService crashDiagnostics;
  late final AppBootstrapState bootstrap;

  Future<void> dispose() async {
    await database.close();
    if (diagnosticsDirectory.existsSync()) {
      diagnosticsDirectory.deleteSync(recursive: true);
    }
  }
}

class _FakePlatformBridge implements PlatformBridge {
  List<MediaDeviceInfo> devices = <MediaDeviceInfo>[
    MediaDeviceInfo(
      deviceId: 'default-mic',
      label: 'Default mic',
      kind: 'audioinput',
    ),
  ];
  Object? enumerateError;

  @override
  Future<List<MediaDeviceInfo>> enumerateMediaDevices() async {
    final error = enumerateError;
    if (error != null) {
      throw error;
    }
    return devices;
  }

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

class _NoIdentityController extends IdentityController {
  @override
  Future<RainIdentity?> build() async => null;
}

class _NoRuntimeController extends RuntimeController {
  @override
  Future<RainRuntimeController?> build() async => null;
}

class _NoFriendsController extends FriendsController {
  @override
  Future<List<FriendRecord>> build() async => const <FriendRecord>[];
}
