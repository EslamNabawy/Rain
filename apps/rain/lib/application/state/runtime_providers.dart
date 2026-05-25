import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/runtime/app_exit_coordinator.dart';
import 'package:rain/application/runtime/video_call_renderers.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/background_services.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'app_state.dart';
import 'core_providers.dart';
import 'identity_providers.dart';
import 'messaging_providers.dart';
import 'settings_providers.dart';

final backgroundServiceProvider =
    AsyncNotifierProvider<BackgroundServiceController, bool>(
      BackgroundServiceController.new,
    );

class BackgroundServiceController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    await ref.watch(appSettingsStoreProvider).loadBackgroundServiceEnabled();
    await BackgroundServices.instance.stop();
    return false;
  }

  Future<void> setEnabled(bool enabled) async {
    final previous =
        state.value ?? AppSettingsStore.defaultBackgroundServiceEnabled;
    state = const AsyncValue.data(false);
    try {
      await ref
          .read(appSettingsStoreProvider)
          .setBackgroundServiceEnabled(false);
      final runtime = ref.read(runtimeControllerProvider).value;
      if (runtime == null) {
        await BackgroundServices.instance.stop();
        return;
      }
      await runtime.setBackgroundServiceEnabled(false);
    } catch (error, stackTrace) {
      state = AsyncValue.data(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final friendsProvider =
    AsyncNotifierProvider<FriendsController, List<FriendRecord>>(
      FriendsController.new,
    );

class FriendsController extends AsyncNotifier<List<FriendRecord>> {
  StreamSubscription<List<FriendRecord>>? _subscription;

  @override
  Future<List<FriendRecord>> build() async {
    final store = ref.watch(friendStoreProvider);
    _subscription = store.watchFriends().listen(
      (List<FriendRecord> friends) => state = AsyncValue.data(friends),
      onError: (Object error, StackTrace stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
    );
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return store.loadFriends();
  }

  Future<void> accept(String username) async {
    assertNetworkReady(ref);
    await _runtime().acceptFriend(username);
  }

  Future<void> reject(String username) async {
    assertNetworkReady(ref);
    await _runtime().rejectFriend(username);
  }

  Future<void> unfriend(String username) async {
    assertNetworkReady(ref);
    await _runtime().unfriend(username);
  }

  Future<void> block(String username) async {
    assertNetworkReady(ref);
    await _runtime().blockFriend(username);
  }

  Future<void> unblock(String username) async {
    assertNetworkReady(ref);
    await _runtime().unblockFriend(username);
  }

  Future<void> refresh() async {
    assertNetworkReady(ref);
    await _runtime().refreshRelationships();
  }

  Future<void> refreshPeer(String username) async {
    assertNetworkReady(ref);
    await _runtime().refreshPeer(username);
  }

  RainRuntimeController _runtime() {
    final runtime = ref.read(runtimeControllerProvider).value;
    if (runtime == null) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }
}

final brainProvider = Provider<SessionManager?>((Ref ref) {
  final identity = ref.watch(identityProvider).value;
  final environment = ref.watch(appEnvironmentProvider);

  if (identity == null || environment.shouldUseFallbackAdapter) {
    return null;
  }

  final brain = createDefaultProtocolBrain(
    selfUsername: identity.username,
    adapter: ref.watch(adapterProvider),
    iceServers: environment.iceServers,
    iceServersProvider: ref.watch(turnCredentialServiceProvider).iceServers,
    connectionMemoryStore: ref.watch(connectionMemoryStoreProvider),
    platformBridge: ref.watch(platformBridgeProvider),
    selectedAudioInputDeviceIdProvider: ref
        .watch(appSettingsStoreProvider)
        .loadSelectedMicrophoneDeviceId,
    selectedVideoInputDeviceIdProvider: ref
        .watch(appSettingsStoreProvider)
        .loadSelectedVideoInputDeviceId,
  );

  return brain;
});

final runtimeControllerProvider =
    AsyncNotifierProvider<RuntimeController, RainRuntimeController?>(
      RuntimeController.new,
    );

class RuntimeController extends AsyncNotifier<RainRuntimeController?> {
  NetworkStatusKind? _lastNetworkKind;
  String? _lastNetworkPathKey;

  @override
  Future<RainRuntimeController?> build() async {
    final identity = ref.watch(identityProvider).value;
    if (identity == null) {
      return null;
    }
    final current = state.value;
    final networkStatus =
        ref.watch(networkStatusProvider).value ??
        const NetworkStatusState.checking();
    final previousNetworkKind = _lastNetworkKind;
    final previousNetworkPathKey = _lastNetworkPathKey;
    _lastNetworkKind = networkStatus.kind;
    _lastNetworkPathKey = networkStatus.pathKey;
    if (networkStatus.blocksNetworkActions) {
      if (current != null) {
        await current.handleNetworkLost(
          'Internet connection lost. Transfer canceled.',
        );
        await current.dispose();
      }
      return null;
    }
    if (networkStatus.kind == NetworkStatusKind.checking) {
      return current?.selfIdentity.username == identity.username
          ? current
          : null;
    }
    if (current != null && current.selfIdentity.username == identity.username) {
      if (previousNetworkKind != null &&
          (previousNetworkKind != networkStatus.kind ||
              previousNetworkPathKey != networkStatus.pathKey)) {
        await current.handleNetworkAvailable(
          'Network changed. Restarting peer connection paths.',
        );
      }
      return current;
    }
    final environment = ref.watch(appEnvironmentProvider);
    await ref.read(backgroundServiceProvider.future);
    final controller = RainRuntimeController(
      selfIdentity: identity,
      adapter: ref.watch(adapterProvider),
      voiceSignalingCipher: SignalingCipher.fromKeyMaterial(
        environment.signalingEncryptionKey,
      ),
      brain: ref.watch(brainProvider),
      database: ref.watch(databaseProvider),
      friendStore: ref.watch(friendStoreProvider),
      messageStore: ref.watch(messageStoreProvider),
      offlineQueueStore: ref.watch(offlineQueueStoreProvider),
      messageDeliveryService: ref.watch(messageDeliveryServiceProvider),
      fileTransferStore: ref.watch(fileTransferStoreProvider),
      heartbeatInterval: environment.heartbeatInterval,
      startupMediaPermissionWarmup:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? () => ref
                .read(mediaDeviceSettingsProvider)
                .warmUpStartupCallPermissions()
          : null,
      errorRecorder: ref.watch(crashDiagnosticsServiceProvider).recordErrorSync,
    );

    final exitRegistration = AppExitCoordinator.instance.register(
      controller.closeForAppExit,
    );
    ref.onDispose(() {
      exitRegistration.unregister();
      unawaited(controller.dispose());
    });

    try {
      await controller.start();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    return controller;
  }

  Future<void> logOut() async {
    final controller = state.value;
    if (controller == null) {
      return;
    }
    await controller.logOut();
    state = const AsyncValue.data(null);
    ref.invalidate(identityProvider);
    ref.invalidate(friendsProvider);
    ref.invalidate(fileTransfersProvider);
    ref.invalidate(voiceCallProvider);
    ref.invalidate(connectionsProvider);
    ref.invalidate(recentSearchesProvider);
  }
}

final voiceCallProvider = NotifierProvider<VoiceCallController, VoiceCallState>(
  VoiceCallController.new,
);

final videoCallRenderersProvider = Provider<VideoCallRenderers?>((Ref ref) {
  final call = ref.watch(voiceCallProvider);
  if (!call.isVideo || call.phase == VoiceCallPhase.idle) {
    return null;
  }
  return ref.watch(runtimeControllerProvider).value?.videoCallRenderers;
});

class VoiceCallController extends Notifier<VoiceCallState> {
  StreamSubscription<VoiceCallState>? _subscription;
  RainRuntimeController? _runtime;

  @override
  VoiceCallState build() {
    ref.listen<AsyncValue<RainRuntimeController?>>(runtimeControllerProvider, (
      _,
      AsyncValue<RainRuntimeController?> next,
    ) {
      unawaited(_replaceRuntime(next.value));
    });
    scheduleMicrotask(() {
      unawaited(_replaceRuntime(ref.read(runtimeControllerProvider).value));
    });
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return ref.read(runtimeControllerProvider).value?.voiceCallState ??
        const VoiceCallState.idle();
  }

  Future<void> start(String peerId) async {
    assertNetworkReady(ref);
    await _requireRuntime().startVoiceCall(peerId);
  }

  Future<void> startVideo(String peerId) async {
    assertNetworkReady(ref);
    await _requireRuntime().startVideoCall(peerId);
  }

  Future<void> accept() async {
    assertNetworkReady(ref);
    await _requireRuntime().acceptVoiceCall();
  }

  Future<void> reject() async {
    await _requireRuntime().rejectVoiceCall();
  }

  Future<void> hangUp() async {
    await _requireRuntime().hangUpVoiceCall();
  }

  Future<void> setMuted(bool muted) async {
    await _requireRuntime().setVoiceCallMuted(muted);
  }

  Future<void> setCameraMuted(bool muted) async {
    await _requireRuntime().setVideoCallCameraMuted(muted);
  }

  Future<void> switchCamera() async {
    final capabilities = await ref
        .read(videoInputCapabilityProvider.notifier)
        .reload();
    if (!capabilities.supportsCameraSwitch) {
      throw StateError('Camera switching is unavailable on this device.');
    }
    await _requireRuntime().switchVideoCallCamera();
  }

  Future<void> setDeafened(bool deafened) async {
    await _requireRuntime().setVoiceCallDeafened(deafened);
  }

  Future<void> setOutputRoute(VoiceCallOutputRoute route) async {
    await _requireRuntime().setVoiceCallOutputRoute(route);
  }

  bool blocksFileTransfer(String peerId) {
    return state.blocksFileTransfersFor(peerId);
  }

  RainRuntimeController _requireRuntime() {
    final runtime = _runtime ?? ref.read(runtimeControllerProvider).value;
    if (runtime == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
    return runtime;
  }

  Future<void> _replaceRuntime(RainRuntimeController? runtime) async {
    _runtime = runtime;
    await _subscription?.cancel();
    _subscription = null;
    if (runtime == null) {
      state = const VoiceCallState.idle();
      return;
    }
    state = runtime.voiceCallState;
    _subscription = runtime.watchVoiceCallState().listen(
      (VoiceCallState next) => state = next,
      onError: (Object error, StackTrace stackTrace) {
        state = state.copyWith(error: error);
      },
    );
  }
}

final connectionsProvider =
    NotifierProvider<ConnectionsController, ConnectionsState>(
      ConnectionsController.new,
    );

class ConnectionsController extends Notifier<ConnectionsState> {
  final List<StreamSubscription<dynamic>> _brainSubscriptions =
      <StreamSubscription<dynamic>>[];
  RainRuntimeController? _runtime;

  @override
  ConnectionsState build() {
    ref.listen<AsyncValue<RainRuntimeController?>>(runtimeControllerProvider, (
      _,
      AsyncValue<RainRuntimeController?> next,
    ) {
      unawaited(_replaceRuntime(next.value));
    });
    scheduleMicrotask(() {
      unawaited(_replaceRuntime(ref.read(runtimeControllerProvider).value));
    });
    ref.onDispose(() {
      for (final subscription in _brainSubscriptions) {
        unawaited(subscription.cancel());
      }
      _brainSubscriptions.clear();
    });
    return const ConnectionsState();
  }

  Future<void> connect(
    String peerId, {
    bool waitForConnected = false,
    bool manualRetry = false,
    bool allowStalePresence = false,
  }) async {
    assertNetworkReady(ref);
    final runtime = _requireRuntime();
    _upsert(
      peerId,
      (view) => view.copyWith(
        manualIntent: ManualConnectionIntent.connecting,
        actionBusy: true,
        localDetail: manualRetry
            ? 'Retrying peer connection.'
            : 'Checking presence and starting signaling.',
        error: null,
      ),
    );
    try {
      await runtime.connectPeer(
        peerId,
        interactive: true,
        waitForConnected: waitForConnected,
        allowStalePresence: allowStalePresence,
        bypassRetryBackoff: manualRetry,
      );
      syncPeer(peerId);
    } catch (error) {
      _upsert(
        peerId,
        (view) => view.copyWith(
          manualIntent: ManualConnectionIntent.failed,
          actionBusy: false,
          disconnecting: false,
          error: error,
          localDetail: 'Connection failed before chat was ready.',
        ),
      );
      rethrow;
    }
  }

  Future<void> disconnect(String peerId) async {
    final runtime = _requireRuntime();
    _upsert(
      peerId,
      (view) => view.copyWith(
        manualIntent: ManualConnectionIntent.manualDisconnected,
        disconnecting: true,
        localDetail: 'Disconnecting.',
        error: null,
      ),
    );
    try {
      await runtime.disconnectPeer(peerId);
      _upsert(
        peerId,
        (view) => view.copyWith(
          session: null,
          manualIntent: ManualConnectionIntent.manualDisconnected,
          actionBusy: false,
          disconnecting: false,
          localDetail: 'Manual disconnect.',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (error) {
      _upsert(
        peerId,
        (view) => view.copyWith(
          actionBusy: false,
          disconnecting: false,
          error: error,
          localDetail: 'Disconnect failed.',
        ),
      );
      rethrow;
    }
  }

  void syncPeer(String peerId) {
    final session = _runtime?.brain?.getSession(peerId);
    _upsert(
      peerId,
      (view) => view.copyWith(
        session: session,
        manualIntent: _intentForSession(session, fallback: view.manualIntent),
        actionBusy: false,
        disconnecting: session?.phase == SessionPhase.disconnecting
            ? view.disconnecting
            : false,
        localDetail: session?.detail,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  RainRuntimeController _requireRuntime() {
    final runtime = _runtime ?? ref.read(runtimeControllerProvider).value;
    if (runtime == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
    return runtime;
  }

  Future<void> _replaceRuntime(RainRuntimeController? runtime) async {
    _runtime = runtime;
    for (final subscription in _brainSubscriptions) {
      await subscription.cancel();
    }
    _brainSubscriptions.clear();
    final brain = runtime?.brain;
    if (brain == null) {
      state = const ConnectionsState();
      return;
    }
    for (final session in brain.getSessions()) {
      _handleSession(session);
    }
    _brainSubscriptions.add(brain.onSessionChanged.listen(_handleSession));
    _brainSubscriptions.add(brain.onPeerConnected.listen(_handleSession));
    _brainSubscriptions.add(
      brain.onIncomingOfferRejected.listen(_handleIncomingOfferRejected),
    );
    _brainSubscriptions.add(
      brain.onPeerDisconnected.listen((String peerId) {
        _upsert(
          peerId,
          (view) => view.copyWith(
            session: null,
            manualIntent:
                view.manualIntent == ManualConnectionIntent.manualDisconnected
                ? ManualConnectionIntent.manualDisconnected
                : ManualConnectionIntent.idle,
            actionBusy: false,
            disconnecting: false,
            localDetail: 'Disconnected.',
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }),
    );
  }

  void _handleIncomingOfferRejected(IncomingOfferRejection rejection) {
    _upsert(
      rejection.peerId,
      (view) => view.copyWith(
        error: rejection.reason,
        localDetail: rejection.reason,
        updatedAt: rejection.rejectedAt.millisecondsSinceEpoch,
      ),
    );
  }

  void _handleSession(Session session) {
    _upsert(
      session.peerId,
      (view) => view.copyWith(
        session: session,
        manualIntent: _intentForSession(session, fallback: view.manualIntent),
        actionBusy: false,
        disconnecting: session.phase == SessionPhase.disconnecting
            ? view.disconnecting
            : false,
        localDetail: session.detail,
        error: session.error,
        updatedAt: session.updatedAt,
      ),
    );
  }

  ManualConnectionIntent _intentForSession(
    Session? session, {
    required ManualConnectionIntent fallback,
  }) {
    if (session?.phase == SessionPhase.disconnecting) {
      return fallback == ManualConnectionIntent.manualDisconnected
          ? ManualConnectionIntent.manualDisconnected
          : ManualConnectionIntent.idle;
    }
    return switch (session?.state) {
      SessionState.connected => ManualConnectionIntent.linked,
      SessionState.connecting ||
      SessionState.reconnecting => ManualConnectionIntent.connecting,
      SessionState.failed => ManualConnectionIntent.failed,
      null => fallback,
    };
  }

  void _upsert(
    String peerId,
    PeerConnectionView Function(PeerConnectionView view) update,
  ) {
    final next = Map<String, PeerConnectionView>.of(state.peers);
    next[peerId] = update(state.peer(peerId));
    state = state.copyWith(
      peers: Map<String, PeerConnectionView>.unmodifiable(next),
    );
  }
}
