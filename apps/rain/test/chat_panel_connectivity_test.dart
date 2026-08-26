/// # chat_panel_connectivity_test
///
/// Tests chat panel behavior when sending messages over stale presence data with an accepted-friend connection.
///
/// **Key types:** _WidgetTestSessionManager, _FakePlatformBridge, _RecordingSoundEffectsService.
///
/// **Depends on:** HomeScreen, ChatPanel, RainRuntimeController, and message delivery service.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/audio/sound_event_router.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/application/state/sound_event_providers.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain/presentation/screens/home_screen.dart';
import 'package:rain/presentation/widgets/chat_composer.dart';
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

  testWidgets('ChatPanel sends while accepted-friend presence is stale', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final database = RainDatabase(NativeDatabase.memory());
    final friendStore = FriendStore(database);
    await friendStore.upsertFriend(
      username: 'bob',
      displayName: 'Bob',
      state: FriendState.friend,
      addedAt: 1,
    );
    await friendStore.updatePresence('bob', false);
    final friends = await friendStore.loadFriends();
    final sentPayloads = <String>[];
    final brain = _WidgetTestSessionManager()
      ..seedConnected('bob', sender: sentPayloads.add)
      ..setChannelOpen('bob', SessionChannel.chat, true);
    final messageStore = MessageStore(database);
    final offlineQueueStore = OfflineQueueStore(database);
    final messageDeliveryService = MessageDeliveryService(
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      ackTimeout: const Duration(milliseconds: 1),
      autoResendLimit: 0,
    );
    final soundRouter = SoundEventRouter(
      effects: _RecordingSoundEffectsService(),
      settingsLoader: () => const AppAudioSettings(),
      callStateReader: () => const VoiceCallState.idle(),
    );
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: null,
      ),
      sessionGeneration: 1,
      adapter: NoopSignalingAdapter(),
      brain: brain,
      database: database,
      friendStore: friendStore,
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: messageDeliveryService,
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(database)),
        networkStatusProvider.overrideWith(
          (Ref ref) => Stream<NetworkStatusState>.value(
            const NetworkStatusState.online(),
          ),
        ),
        platformBridgeProvider.overrideWithValue(_FakePlatformBridge()),
        identityProvider.overrideWith(_SignedInIdentityController.new),
        runtimeControllerProvider.overrideWith(
          () => _StaticRuntimeController(runtime),
        ),
        friendsProvider.overrideWith(() => _StaticFriendsController(friends)),
        soundEventRouterProvider.overrideWithValue(soundRouter),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await runtime.dispose();
      await brain.dispose();
      messageDeliveryService.dispose();
      await soundRouter.dispose();
      await database.close();
    });

    await container.read(identityProvider.future);
    await container.read(runtimeControllerProvider.future);
    await container.read(friendsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey<String>('friend-tile-bob')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Data lane only'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'stale presence send');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(ChatComposer),
        matching: find.byIcon(Icons.send_rounded),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(sentPayloads, isNotEmpty);
    messageDeliveryService.dispose();
  });
}

AppBootstrapState _bootstrap(RainDatabase database) {
  return AppBootstrapState(
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

final class _SignedInIdentityController extends IdentityController {
  @override
  Future<RainIdentity?> build() async {
    return const RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 1,
      gender: null,
    );
  }
}

final class _StaticRuntimeController extends RuntimeController {
  _StaticRuntimeController(this.runtime);

  final RainRuntimeController runtime;

  @override
  Future<RainRuntimeController?> build() async => runtime;
}

final class _StaticFriendsController extends FriendsController {
  _StaticFriendsController(this.friends);

  final List<FriendRecord> friends;

  @override
  Future<List<FriendRecord>> build() async => friends;
}

final class _FakePlatformBridge implements PlatformBridge {
  @override
  Future<List<MediaDeviceInfo>> enumerateMediaDevices() async {
    return const <MediaDeviceInfo>[];
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

final class _RecordingSoundEffectsService extends SoundEffectsService {
  _RecordingSoundEffectsService() : super();

  @override
  Future<void> play(
    RainSoundEffect effect, {
    bool voiceCallActive = false,
    bool allowDuringCall = false,
    double volumeScale = 1.0,
  }) async {}
}

final class _WidgetTestSessionManager implements SessionManager {
  final Map<String, Session> _sessions = <String, Session>{};
  final Set<String> _openChannels = <String>{};
  final StreamController<Session> _peerConnected =
      StreamController<Session>.broadcast();
  final StreamController<String> _peerDisconnected =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _peerMessages =
      StreamController<SessionMessage>.broadcast();
  final StreamController<SessionRemoteTrack> _remoteTracks =
      StreamController<SessionRemoteTrack>.broadcast();
  final StreamController<Session> _sessionChanges =
      StreamController<Session>.broadcast();
  final StreamController<IncomingOfferRejection> _incomingOfferRejected =
      StreamController<IncomingOfferRejection>.broadcast();

  void seedConnected(
    String peerId, {
    required void Function(String data) sender,
  }) {
    final session = Session(
      peerId: peerId,
      state: SessionState.connected,
      connectionType: ConnectionType.signaling,
      phase: SessionPhase.connected,
      detail: 'Data channels open.',
      roomId: 'room-$peerId-alice',
      sender: sender,
    );
    _sessions[peerId] = session;
  }

  void setChannelOpen(String peerId, SessionChannel channel, bool isOpen) {
    final key = '$peerId:${channel.name}';
    if (isOpen) {
      _openChannels.add(key);
    } else {
      _openChannels.remove(key);
    }
  }

  Future<void> dispose() async {
    await _peerConnected.close();
    await _peerDisconnected.close();
    await _peerMessages.close();
    await _remoteTracks.close();
    await _sessionChanges.close();
    await _incomingOfferRejected.close();
  }

  @override
  Stream<Session> get onPeerConnected => _peerConnected.stream;

  @override
  Stream<String> get onPeerDisconnected => _peerDisconnected.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _peerMessages.stream;

  @override
  Stream<SessionRemoteTrack> get onRemoteTrack => _remoteTracks.stream;

  @override
  Stream<Session> get onSessionChanged => _sessionChanges.stream;

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      _incomingOfferRejected.stream;

  @override
  List<Session> getSessions() => _sessions.values.toList(growable: false);

  @override
  Session? getSession(String peerId) => _sessions[peerId];

  @override
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {}

  @override
  Future<void> unregisterPeer(String peerId) async {}

  @override
  Future<Session> connect(String peerId) async {
    final session = Session(
      peerId: peerId,
      state: SessionState.connecting,
      connectionType: ConnectionType.signaling,
      sender: (_) {},
    );
    _sessions[peerId] = session;
    _sessionChanges.add(session);
    return session;
  }

  @override
  Future<void> disconnect(String peerId) async {
    _sessions.remove(peerId);
    _peerDisconnected.add(peerId);
  }

  @override
  Future<void> recoverConnection(
    String peerId, {
    String reason = 'Network changed. Restarting peer connection.',
  }) async {}

  @override
  Future<void> recoverConnections({
    String reason = 'Network changed. Restarting peer connections.',
  }) async {}

  @override
  void sendControl(String peerId, String data) {}

  @override
  void send(String peerId, SessionChannel channel, Object data) {}

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {
    setChannelOpen(peerId, channel, true);
  }

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) {
    return _openChannels.contains('$peerId:${channel.name}');
  }

  @override
  Future<void> startLocalAudio(String peerId) async {}

  @override
  Future<void> stopLocalAudio(String peerId) async {}

  @override
  Future<void> setMicrophoneMuted(String peerId, {required bool muted}) async {}

  @override
  Future<VoiceMediaConnection> createVoiceMediaConnection(String peerId) {
    throw UnimplementedError();
  }

  @override
  Future<CallMediaConnection> createCallMediaConnection(String peerId) {
    throw UnimplementedError();
  }

  @override
  Future<RTCSessionDescription> createMediaOffer(String peerId) {
    throw UnimplementedError();
  }

  @override
  Future<RTCSessionDescription> applyMediaOffer(
    String peerId,
    RTCSessionDescription offer,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> applyMediaAnswer(
    String peerId,
    RTCSessionDescription answer,
  ) async {}
}
