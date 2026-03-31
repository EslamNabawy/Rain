import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peer_core/peer_core.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import '../bootstrap/app_bootstrap.dart';
import '../services/force_update_service.dart';
import '../services/rain_runtime_controller.dart';

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

final connectionMemoryStoreProvider = Provider(
  (Ref ref) => DriftConnectionMemoryStore(ref.watch(databaseProvider)),
);

final messageDeliveryServiceProvider = Provider(
  (Ref ref) => MessageDeliveryService(
    messageStore: ref.watch(messageStoreProvider),
    offlineQueueStore: ref.watch(offlineQueueStoreProvider),
  ),
);

final identityProvider = StreamProvider<RainIdentity?>(
  (Ref ref) => ref.watch(identityRepositoryProvider).watchIdentity(),
);

final friendsProvider = StreamProvider<List<FriendRecord>>(
  (Ref ref) => ref.watch(friendStoreProvider).watchFriends(),
);

final messagesProvider = StreamProvider.family<List<StoredMessage>, String>((
  Ref ref,
  String peerId,
) {
  return ref.watch(messageStoreProvider).watchConversation(peerId);
});

final presenceProvider = StreamProvider.family<bool, String>((
  Ref ref,
  String username,
) {
  return ref.watch(adapterProvider).watchPresence(username);
});

final forceUpdateProvider = FutureProvider<ForceUpdateResult>((Ref ref) {
  return ref.watch(forceUpdateServiceProvider).check();
});

final brainProvider = Provider<ProtocolBrain?>((Ref ref) {
  final identity = ref.watch(identityProvider).valueOrNull;
  final environment = ref.watch(appEnvironmentProvider);

  if (identity == null || environment.shouldUseFallbackAdapter) {
    return null;
  }

  final brain = ProtocolBrainImpl(
    selfUsername: identity.username,
    adapter: ref.watch(adapterProvider),
    peerConfig: PeerConfig(
      iceServers: environment.iceServers,
      platform: FlutterWebRTCBridge(),
    ),
    peerFactory: DefaultPeerCore.new,
    connectionMemoryStore: ref.watch(connectionMemoryStoreProvider),
  );

  ref.onDispose(() {
    for (final session in brain.getSessions()) {
      unawaited(brain.disconnect(session.peerId));
    }
  });

  return brain;
});

final runtimeControllerProvider = Provider<RainRuntimeController?>((Ref ref) {
  final identity = ref.watch(identityProvider).valueOrNull;
  if (identity == null) {
    return null;
  }

  final controller = RainRuntimeController(
    selfIdentity: identity,
    adapter: ref.watch(adapterProvider),
    brain: ref.watch(brainProvider),
    friendStore: ref.watch(friendStoreProvider),
    messageStore: ref.watch(messageStoreProvider),
    offlineQueueStore: ref.watch(offlineQueueStoreProvider),
    messageDeliveryService: ref.watch(messageDeliveryServiceProvider),
  );

  unawaited(controller.start());
  ref.onDispose(controller.dispose);
  return controller;
});
