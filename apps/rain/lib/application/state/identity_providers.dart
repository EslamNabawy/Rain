/// # identity_providers.dart
///
/// Riverpod providers for user identity and session management:
/// [IdentityController] loads/persists [RainIdentity] from the local database,
/// [AuthenticatedSessionController] tracks the current authenticated session
/// with generation-based invalidation.
///
/// **Key types:** [AuthenticatedSession], [AuthenticatedSessionController]
///
/// **Depends on:** protocol_brain, rain_core, core providers
library;

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

final authenticatedSessionProvider =
    NotifierProvider<AuthenticatedSessionController, AuthenticatedSession?>(
      AuthenticatedSessionController.new,
    );

final class AuthenticatedSession {
  const AuthenticatedSession({
    required this.identity,
    required this.sessionGeneration,
  });

  final RainIdentity identity;
  final int sessionGeneration;
}

class AuthenticatedSessionController extends Notifier<AuthenticatedSession?> {
  AuthenticatedSession? _current;
  int _nextGeneration = 0;

  @override
  AuthenticatedSession? build() {
    final identityState = ref.watch(identityProvider);
    if (identityState.isLoading) {
      return _current;
    }
    if (!identityState.hasValue) {
      _current = null;
      return null;
    }

    final identity = identityState.requireValue;
    if (identity == null) {
      _current = null;
      return null;
    }

    final previous = _current;
    if (previous != null && previous.identity.username == identity.username) {
      _current = AuthenticatedSession(
        identity: identity,
        sessionGeneration: previous.sessionGeneration,
      );
      return _current;
    }

    _current = AuthenticatedSession(
      identity: identity,
      sessionGeneration: ++_nextGeneration,
    );
    return _current;
  }

  void endSession() {
    _nextGeneration += 1;
    _current = null;
    state = null;
  }
}

class IdentityController extends AsyncNotifier<RainIdentity?> {
  StreamSubscription<RainIdentity?>? _subscription;
  int _validationRequestId = 0;

  @override
  Future<RainIdentity?> build() async {
    final repository = ref.watch(identityRepositoryProvider);
    ref.onDispose(() {
      _validationRequestId += 1;
      unawaited(_subscription?.cancel());
    });
    final cachedIdentity = await repository.loadIdentity();
    if (!ref.mounted) {
      return null;
    }
    final restoredIdentity = await _validateCachedIdentity(cachedIdentity);
    if (!ref.mounted) {
      return restoredIdentity;
    }
    _subscription = repository.watchIdentity().listen(
      (RainIdentity? identity) {
        if (!ref.mounted) {
          return;
        }
        final requestId = ++_validationRequestId;
        unawaited(
          _validateCachedIdentity(identity)
              .then((RainIdentity? validated) {
                if (ref.mounted && requestId == _validationRequestId) {
                  state = AsyncValue.data(validated);
                }
              })
              .catchError((Object error, StackTrace stackTrace) {
                if (ref.mounted && requestId == _validationRequestId) {
                  state = AsyncValue.error(error, stackTrace);
                }
              }),
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        if (ref.mounted) {
          state = AsyncValue.error(error, stackTrace);
        }
      },
    );
    return restoredIdentity;
  }

  Future<void> register({
    required String username,
    required String displayName,
    required String password,
    required RainGender gender,
  }) async {
    assertNetworkReady(ref);
    final adapter = ref.read(adapterProvider);
    var authCreated = false;
    try {
      await adapter.register(username, password);
      authCreated = true;
      final now = DateTime.now().millisecondsSinceEpoch;
      await _saveBackendIdentity(
        RainIdentity(
          username: username,
          displayName: displayName,
          createdAt: now,
          gender: gender,
        ),
      );
    } catch (_) {
      if (authCreated) {
        try {
          await adapter.signOut();
        } catch (_) {
          // A failed backend registration must not keep a local Firebase session
          // that the app could mistake for a valid Rain identity.
        }
      }
      rethrow;
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    assertNetworkReady(ref);
    final adapter = ref.read(adapterProvider);
    try {
      await adapter.login(username, password);
    } catch (error, stackTrace) {
      if (await ref
          .read(appSettingsStoreProvider)
          .wasRainUsernameDeletedOnThisDevice(username)) {
        throw Exception(
          'This Rain account was deleted on this device and cannot be used to sign in again. Create a new account with another username.',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final existing = await adapter.fetchIdentity(username);
    final currentUid = (await adapter.currentUid()).trim();
    final backendUid = existing?.uid.trim() ?? '';
    if (existing == null ||
        currentUid.isEmpty ||
        backendUid.isEmpty ||
        backendUid != currentUid) {
      try {
        await adapter.signOut();
      } catch (_) {
        // A backend-missing login must not keep a Firebase session that the app
        // could later use to recreate a deleted Rain account.
      }
      throw const SignalingSessionExpiredException(
        'This Rain account no longer exists. Create a new account or use another username.',
      );
    }
    await _saveBackendIdentity(
      RainIdentity(
        username: username,
        displayName: existing.displayName,
        createdAt: existing.registeredAt,
        gender: existing.gender == null
            ? null
            : RainGender.values.byName(existing.gender!),
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
    await _clearInvalidCachedSession();
  }

  Future<void> _saveBackendIdentity(RainIdentity identity) async {
    final adapter = ref.read(adapterProvider);
    final repository = ref.read(identityRepositoryProvider);
    await adapter.addToUserSearch(identity.username);
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
    await repository.saveIdentity(identity);
  }

  Future<RainIdentity?> _validateCachedIdentity(RainIdentity? identity) async {
    if (identity == null) {
      return null;
    }

    final adapter = ref.read(adapterProvider);
    final repository = ref.read(identityRepositoryProvider);
    try {
      await adapter.ensureSignedInAs(identity.username);
      if (!ref.mounted) {
        return null;
      }
      final backendIdentity = await adapter.fetchIdentity(identity.username);
      if (!ref.mounted) {
        return null;
      }
      final currentUid = (await adapter.currentUid()).trim();
      if (!ref.mounted) {
        return null;
      }
      final backendUid = backendIdentity?.uid.trim() ?? '';
      if (backendIdentity == null ||
          currentUid.isEmpty ||
          backendUid.isEmpty ||
          backendUid != currentUid) {
        await _clearInvalidCachedSession();
        return null;
      }

      final validated = RainIdentity(
        username: backendIdentity.username,
        displayName: backendIdentity.displayName,
        createdAt: backendIdentity.registeredAt == 0
            ? identity.createdAt
            : backendIdentity.registeredAt,
        gender: _backendGender(backendIdentity.gender),
      );
      if (!_sameIdentity(identity, validated)) {
        if (!ref.mounted) {
          return null;
        }
        await repository.saveIdentity(validated);
      }
      return validated;
    } on SignalingSessionExpiredException {
      await _clearInvalidCachedSession();
      return null;
    }
  }

  Future<void> _clearInvalidCachedSession() async {
    if (!ref.mounted) {
      return;
    }
    final adapter = ref.read(adapterProvider);
    final database = ref.read(databaseProvider);
    try {
      await adapter.signOut();
    } catch (_) {
      // Local session clearing must not depend on backend sign-out success.
    }
    await database.clearSessionData();
  }

  RainGender? _backendGender(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final gender in RainGender.values) {
      if (gender.name == normalized) {
        return gender;
      }
    }
    return null;
  }

  bool _sameIdentity(RainIdentity left, RainIdentity right) {
    return left.username == right.username &&
        left.displayName == right.displayName &&
        left.createdAt == right.createdAt &&
        left.gender == right.gender;
  }
}
