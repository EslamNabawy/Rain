import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/background_services.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';
import 'app_state.dart';

enum AppThemeMode { dark, light, system }

extension AppThemeModeX on AppThemeMode {
  ThemeMode get themeMode => switch (this) {
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.system => ThemeMode.system,
  };
}

final themeModeProvider = NotifierProvider<ThemeModeController, AppThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => AppThemeMode.dark;

  void setDark() => state = AppThemeMode.dark;
  void setLight() => state = AppThemeMode.light;
  void setSystem() => state = AppThemeMode.system;
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

class RecentSearchesController extends Notifier<List<String>> {
  static const int maxRecentSearches = 5;

  @override
  List<String> build() => const <String>[];

  void add(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return;
    }
    state = <String>[
      normalized,
      ...state.where((String item) => item != normalized),
    ].take(maxRecentSearches).toList(growable: false);
  }

  void clear() {
    state = const <String>[];
  }
}

final appBootstrapProvider = Provider<AppBootstrapState>(
  (_) => throw UnimplementedError('AppBootstrapState has not been overridden.'),
);

final appEnvironmentProvider = Provider(
  (Ref ref) => ref.watch(appBootstrapProvider).environment,
);

final databaseProvider = Provider<RainDatabase>(
  (Ref ref) => ref.watch(appBootstrapProvider).database,
);

final adapterProvider = Provider<SignalingAdapter>(
  (Ref ref) => ref.watch(appBootstrapProvider).adapter,
);

final forceUpdateServiceProvider = Provider(
  (Ref ref) => ref.watch(appBootstrapProvider).forceUpdateService,
);

final soundEffectsProvider = Provider<SoundEffectsService>((Ref ref) {
  final service = SoundEffectsService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final appSettingsStoreProvider = Provider((Ref ref) => AppSettingsStore());

final identityRepositoryProvider = Provider(
  (Ref ref) => IdentityRepository(ref.watch(databaseProvider)),
);

final friendStoreProvider = Provider(
  (Ref ref) => FriendStore(ref.watch(databaseProvider)),
);

final messageStoreProvider = Provider(
  (Ref ref) => MessageStore(ref.watch(databaseProvider)),
);

final offlineQueueStoreProvider = Provider(
  (Ref ref) => OfflineQueueStore(ref.watch(databaseProvider)),
);

final fileTransferStoreProvider = Provider(
  (Ref ref) => FileTransferStore(ref.watch(databaseProvider)),
);

final connectionMemoryStoreProvider = Provider(
  (Ref ref) => DriftConnectionMemoryStore(ref.watch(databaseProvider)),
);

final messageDeliveryServiceProvider = Provider((Ref ref) {
  final service = MessageDeliveryService(
    messageStore: ref.watch(messageStoreProvider),
    offlineQueueStore: ref.watch(offlineQueueStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final forceUpdateProvider =
    AsyncNotifierProvider<ForceUpdateController, ForceUpdateResult>(
      ForceUpdateController.new,
    );

class ForceUpdateController extends AsyncNotifier<ForceUpdateResult> {
  @override
  Future<ForceUpdateResult> build() {
    return ref.watch(forceUpdateServiceProvider).check();
  }
}

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
        state.valueOrNull ?? AppSettingsStore.defaultBackgroundServiceEnabled;
    state = const AsyncValue.data(false);
    try {
      await ref
          .read(appSettingsStoreProvider)
          .setBackgroundServiceEnabled(false);
      final runtime = ref.read(runtimeControllerProvider).valueOrNull;
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

final identityProvider =
    AsyncNotifierProvider<IdentityController, RainIdentity?>(
      IdentityController.new,
    );

class IdentityController extends AsyncNotifier<RainIdentity?> {
  StreamSubscription<RainIdentity?>? _subscription;

  @override
  Future<RainIdentity?> build() async {
    final repository = ref.watch(identityRepositoryProvider);
    _subscription = repository.watchIdentity().listen(
      (RainIdentity? identity) => state = AsyncValue.data(identity),
      onError: (Object error, StackTrace stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
    );
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return repository.loadIdentity();
  }

  Future<void> register({
    required String username,
    required String displayName,
    required String password,
    required RainGender gender,
  }) async {
    final adapter = ref.read(adapterProvider);
    await adapter.register(username, password);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _saveBackendIdentity(
      RainIdentity(
        username: username,
        displayName: displayName,
        createdAt: now,
        gender: gender,
      ),
    );
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final adapter = ref.read(adapterProvider);
    await adapter.login(username, password);
    final existing = await adapter.fetchIdentity(username);
    await _saveBackendIdentity(
      RainIdentity(
        username: username,
        displayName: existing?.displayName ?? username,
        createdAt:
            existing?.registeredAt ?? DateTime.now().millisecondsSinceEpoch,
        gender: existing?.gender == null
            ? null
            : RainGender.values.byName(existing!.gender!),
      ),
    );
  }

  Future<void> updateDisplayName(String displayName) async {
    final identity = state.valueOrNull;
    if (identity == null) {
      return;
    }
    await _saveBackendIdentity(identity.copyWith(displayName: displayName));
  }

  Future<void> updateGender(RainGender gender) async {
    final identity = state.valueOrNull;
    if (identity == null) {
      return;
    }
    await _saveBackendIdentity(identity.copyWith(gender: gender));
  }

  Future<void> resetExpiredSession() async {
    await ref.read(adapterProvider).signOut();
    await ref.read(databaseProvider).clearSessionData();
  }

  Future<void> _saveBackendIdentity(RainIdentity identity) async {
    final adapter = ref.read(adapterProvider);
    await adapter.addToUserSearch(identity.username);
    await ref.read(identityRepositoryProvider).saveIdentity(identity);
    final now = DateTime.now().millisecondsSinceEpoch;
    await adapter.upsertIdentity(
      BackendIdentity(
        username: identity.username,
        uid: await adapter.currentUid(),
        displayName: identity.displayName,
        gender: identity.gender?.name,
        registeredAt: identity.createdAt,
        lastSeen: now,
        lastHeartbeat: now,
        online: true,
      ),
    );
    await adapter.setPresence(identity.username, true);
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
    await _runtime().acceptFriend(username);
  }

  Future<void> reject(String username) async {
    await _runtime().rejectFriend(username);
  }

  Future<void> unfriend(String username) async {
    await _runtime().unfriend(username);
  }

  Future<void> block(String username) async {
    await _runtime().blockFriend(username);
  }

  Future<void> unblock(String username) async {
    await _runtime().unblockFriend(username);
  }

  Future<void> refresh() async {
    await _runtime().refreshRelationships();
  }

  Future<void> refreshPeer(String username) async {
    await _runtime().refreshPeer(username);
  }

  RainRuntimeController _runtime() {
    final runtime = ref.read(runtimeControllerProvider).valueOrNull;
    if (runtime == null) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }
}

final messagesProvider =
    AsyncNotifierProvider.family<
      MessagesController,
      List<StoredMessage>,
      String
    >(MessagesController.new);

class MessagesController
    extends FamilyAsyncNotifier<List<StoredMessage>, String> {
  late String _peerId;
  StreamSubscription<List<StoredMessage>>? _subscription;

  @override
  Future<List<StoredMessage>> build(String peerId) {
    _peerId = peerId;
    final completer = Completer<List<StoredMessage>>();
    var completed = false;
    _subscription = ref
        .watch(messageStoreProvider)
        .watchConversation(peerId)
        .listen(
          (List<StoredMessage> messages) {
            state = AsyncValue.data(messages);
            if (!completed) {
              completed = true;
              completer.complete(messages);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
            if (!completed) {
              completed = true;
              completer.completeError(error, stackTrace);
            }
          },
        );
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return completer.future;
  }

  Future<void> markRead() async {
    await _runtime().markConversationRead(_peerId);
  }

  Future<void> resend(String messageId) async {
    await _runtime().resendMessage(messageId);
  }

  Future<void> send(String content) async {
    await _runtime().sendMessage(_peerId, content);
  }

  Future<void> sendFile({
    required String fileName,
    required int fileSize,
    required Stream<List<int>> Function() openRead,
    String? localPath,
    String? mimeType,
  }) async {
    await _runtime().sendFile(
      peerId: _peerId,
      fileName: fileName,
      fileSize: fileSize,
      openRead: openRead,
      localPath: localPath,
      mimeType: mimeType,
    );
  }

  RainRuntimeController _runtime() {
    final runtime = ref.read(runtimeControllerProvider).valueOrNull;
    if (runtime == null) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }
}

final fileTransfersProvider =
    AsyncNotifierProvider.family<
      FileTransfersController,
      List<FileTransferRecord>,
      String
    >(FileTransfersController.new);

class FileTransfersController
    extends FamilyAsyncNotifier<List<FileTransferRecord>, String> {
  late String _peerId;
  StreamSubscription<List<FileTransferRecord>>? _subscription;

  @override
  Future<List<FileTransferRecord>> build(String peerId) {
    _peerId = peerId;
    final completer = Completer<List<FileTransferRecord>>();
    var completed = false;
    _subscription = ref
        .watch(fileTransferStoreProvider)
        .watchPeerTransfers(peerId)
        .listen(
          (List<FileTransferRecord> transfers) {
            state = AsyncValue.data(transfers);
            if (!completed) {
              completed = true;
              completer.complete(transfers);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
            if (!completed) {
              completed = true;
              completer.completeError(error, stackTrace);
            }
          },
        );
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return completer.future;
  }

  Future<void> accept(String transferId) async {
    await _runtime().acceptFileTransfer(transferId);
  }

  Future<void> reject(String transferId) async {
    await _runtime().rejectFileTransfer(transferId);
  }

  Future<void> cancel(String transferId) async {
    await _runtime().cancelFileTransfer(transferId);
  }

  Future<void> retry(FileTransferRecord transfer) async {
    final localPath = transfer.localPath;
    if (transfer.direction != FileTransferDirection.outgoing ||
        localPath == null ||
        localPath.isEmpty) {
      throw StateError('Original file is no longer available.');
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('Original file is no longer available.');
    }
    await _runtime().sendFile(
      peerId: _peerId,
      fileName: transfer.fileName,
      fileSize: await file.length(),
      openRead: file.openRead,
      localPath: localPath,
      mimeType: transfer.mimeType,
    );
  }

  RainRuntimeController _runtime() {
    final runtime = ref.read(runtimeControllerProvider).valueOrNull;
    if (runtime == null) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }
}

final brainProvider = Provider<SessionManager?>((Ref ref) {
  final identity = ref.watch(identityProvider).valueOrNull;
  final environment = ref.watch(appEnvironmentProvider);

  if (identity == null || environment.shouldUseFallbackAdapter) {
    return null;
  }

  final brain = createDefaultProtocolBrain(
    selfUsername: identity.username,
    adapter: ref.watch(adapterProvider),
    iceServers: environment.iceServers,
    connectionMemoryStore: ref.watch(connectionMemoryStoreProvider),
  );

  return brain;
});

final runtimeControllerProvider =
    AsyncNotifierProvider<RuntimeController, RainRuntimeController?>(
      RuntimeController.new,
    );

class RuntimeController extends AsyncNotifier<RainRuntimeController?> {
  @override
  Future<RainRuntimeController?> build() async {
    final identity = ref.watch(identityProvider).valueOrNull;
    if (identity == null) {
      return null;
    }
    final environment = ref.watch(appEnvironmentProvider);
    await ref.read(backgroundServiceProvider.future);
    final controller = RainRuntimeController(
      selfIdentity: identity,
      adapter: ref.watch(adapterProvider),
      brain: ref.watch(brainProvider),
      database: ref.watch(databaseProvider),
      friendStore: ref.watch(friendStoreProvider),
      messageStore: ref.watch(messageStoreProvider),
      offlineQueueStore: ref.watch(offlineQueueStoreProvider),
      messageDeliveryService: ref.watch(messageDeliveryServiceProvider),
      fileTransferStore: ref.watch(fileTransferStoreProvider),
      heartbeatInterval: environment.heartbeatInterval,
    );

    ref.onDispose(() {
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
    final controller = state.valueOrNull;
    if (controller == null) {
      return;
    }
    await controller.logOut();
    state = const AsyncValue.data(null);
    ref.invalidate(identityProvider);
    ref.invalidate(friendsProvider);
    ref.invalidate(fileTransfersProvider);
    ref.invalidate(connectionsProvider);
    ref.invalidate(recentSearchesProvider);
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
      unawaited(_replaceRuntime(next.valueOrNull));
    });
    scheduleMicrotask(() {
      unawaited(
        _replaceRuntime(ref.read(runtimeControllerProvider).valueOrNull),
      );
    });
    ref.onDispose(() {
      for (final subscription in _brainSubscriptions) {
        unawaited(subscription.cancel());
      }
      _brainSubscriptions.clear();
    });
    return const ConnectionsState();
  }

  Future<void> connect(String peerId, {bool waitForConnected = false}) async {
    final runtime = _requireRuntime();
    _upsert(
      peerId,
      (view) => view.copyWith(
        manualIntent: ManualConnectionIntent.connecting,
        actionBusy: true,
        localDetail: 'Checking presence and starting signaling.',
        error: null,
      ),
    );
    try {
      await runtime.connectPeer(
        peerId,
        interactive: true,
        waitForConnected: waitForConnected,
      );
      syncPeer(peerId);
    } catch (error) {
      _upsert(
        peerId,
        (view) => view.copyWith(
          manualIntent: ManualConnectionIntent.failed,
          actionBusy: false,
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
        disconnecting: false,
        localDetail: session?.detail,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  RainRuntimeController _requireRuntime() {
    final runtime = _runtime ?? ref.read(runtimeControllerProvider).valueOrNull;
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

  void _handleSession(Session session) {
    _upsert(
      session.peerId,
      (view) => view.copyWith(
        session: session,
        manualIntent: _intentForSession(session, fallback: view.manualIntent),
        actionBusy: false,
        disconnecting: false,
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

final userSearchProvider =
    AsyncNotifierProvider<UserSearchController, UserSearchState>(
      UserSearchController.new,
    );

class UserSearchController extends AsyncNotifier<UserSearchState> {
  int _searchSerial = 0;

  @override
  UserSearchState build() => const UserSearchState();

  Future<void> search(String query) async {
    final normalized = query.trim().toLowerCase();
    final searchSerial = ++_searchSerial;
    if (normalized.length < 2) {
      state = AsyncValue.data(UserSearchState(query: normalized));
      return;
    }

    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() async {
      final results = await ref.read(adapterProvider).searchUsers(normalized);
      return UserSearchState(query: normalized, results: results);
    });
    if (searchSerial == _searchSerial) {
      state = next;
      if (next.hasValue) {
        ref.read(recentSearchesProvider.notifier).add(normalized);
      }
    }
  }

  Future<void> refreshCurrent() async {
    final currentQuery = state.valueOrNull?.query.trim() ?? '';
    if (currentQuery.length < 2) {
      return;
    }
    await search(currentQuery);
  }

  Future<FriendRequestResult?> sendFriendRequest(String username) async {
    final previous = state.valueOrNull ?? const UserSearchState();
    state = AsyncValue.data(previous.copyWith(sendingTo: username));
    try {
      return await _runtime().sendFriendRequest(username);
    } finally {
      final current = state.valueOrNull ?? previous;
      state = AsyncValue.data(current.copyWith(sendingTo: null));
    }
  }

  RainRuntimeController _runtime() {
    final runtime = ref.read(runtimeControllerProvider).valueOrNull;
    if (runtime == null) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }
}
