import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'core_providers.dart';

final identityRepositoryProvider = Provider(
  (Ref ref) => IdentityRepository(ref.watch(databaseProvider)),
);

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
    assertNetworkReady(ref);
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
    assertNetworkReady(ref);
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
    assertNetworkReady(ref);
    final identity = state.value;
    if (identity == null) {
      return;
    }
    await _saveBackendIdentity(identity.copyWith(displayName: displayName));
  }

  Future<void> updateGender(RainGender gender) async {
    assertNetworkReady(ref);
    final identity = state.value;
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
