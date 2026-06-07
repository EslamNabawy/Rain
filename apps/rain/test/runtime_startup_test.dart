import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/main.dart' as rain_app;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain/application/runtime/app_exit_coordinator.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/state/app_startup_state.dart';
import 'package:rain/application/state/core_providers.dart';
import 'package:rain/application/state/identity_providers.dart';
import 'package:rain/application/state/runtime_providers.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'package:rain_core/rain_core.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _FailingBootstrapper extends AppBootstrapper {
  @override
  Future<AppBootstrapState> bootstrap(AppEnvironment environment) async {
    throw StateError('release config missing');
  }
}

class _FailingAuthAdapter extends NoopSignalingAdapter {
  @override
  Future<void> ensureAuthenticated() async {
    throw StateError('auth backend down');
  }
}

class _ExpiredSessionAdapter extends NoopSignalingAdapter {
  @override
  Future<void> ensureAuthenticated() async {
    throw const SignalingSessionExpiredException('sign in again');
  }
}

class _RecordingPresenceAdapter extends NoopSignalingAdapter {
  final List<bool> presenceWrites = <bool>[];

  @override
  Future<void> setPresence(String username, bool online) async {
    presenceWrites.add(online);
    await super.setPresence(username, online);
  }
}

class _FailingSignOutAdapter extends _RecordingPresenceAdapter {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    throw StateError('sign out denied');
  }
}

class _FailingReauthAccountDeletionAdapter extends _RecordingPresenceAdapter {
  int reauthCalls = 0;
  int deleteAccountCalls = 0;

  @override
  Future<void> reauthenticate(String username, String password) async {
    reauthCalls += 1;
    throw const AccountDeletionException(
      kind: AccountDeletionFailureKind.reauthenticationFailed,
      message: 'Wrong password. Account deletion was not started.',
      destructiveActionStarted: false,
    );
  }

  @override
  Future<void> deleteAccount(String username) async {
    deleteAccountCalls += 1;
  }
}

class _BlockingReauthFailureAdapter extends _RecordingPresenceAdapter {
  final Completer<void> reauthStarted = Completer<void>();
  final Completer<void> releaseReauth = Completer<void>();
  int reauthCalls = 0;
  int deleteAccountCalls = 0;

  @override
  Future<void> reauthenticate(String username, String password) async {
    reauthCalls += 1;
    if (!reauthStarted.isCompleted) {
      reauthStarted.complete();
    }
    await releaseReauth.future;
    throw const AccountDeletionException(
      kind: AccountDeletionFailureKind.reauthenticationFailed,
      message: 'Wrong password. Account deletion was not started.',
      destructiveActionStarted: false,
    );
  }

  @override
  Future<void> deleteAccount(String username) async {
    deleteAccountCalls += 1;
  }
}

class _FailingBackendAccountDeletionAdapter extends _RecordingPresenceAdapter {
  int reauthCalls = 0;
  int deleteAccountCalls = 0;

  @override
  Future<void> reauthenticate(String username, String password) async {
    reauthCalls += 1;
  }

  @override
  Future<void> deleteAccount(String username) async {
    deleteAccountCalls += 1;
    throw const AccountDeletionException(
      kind: AccountDeletionFailureKind.backendCleanupFailed,
      message: 'Could not finish deleting backend account data.',
      destructiveActionStarted: false,
    );
  }
}

class _BlockingOfflinePresenceAdapter extends _RecordingPresenceAdapter {
  final Completer<void> offlineStarted = Completer<void>();
  final Completer<void> releaseOffline = Completer<void>();
  int deleteAccountCalls = 0;

  @override
  Future<void> setPresence(String username, bool online) async {
    if (!online && !offlineStarted.isCompleted) {
      offlineStarted.complete();
      await releaseOffline.future;
    }
    await super.setPresence(username, online);
  }

  @override
  Future<void> deleteAccount(String username) async {
    deleteAccountCalls += 1;
  }
}

class _SignedInIdentityController extends IdentityController {
  @override
  Future<RainIdentity?> build() async {
    return const RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 1,
      gender: RainGender.female,
    );
  }
}

class _ReadyForceUpdateController extends ForceUpdateController {
  @override
  Future<ForceUpdateResult> build() async {
    return const ForceUpdateResult(
      status: ForceUpdateStatus.current,
      currentVersion: '1.0.8',
      minVersion: '1.0.8',
      updateUrl: 'https://example.com',
    );
  }
}

class _DisabledBackgroundServiceController extends BackgroundServiceController {
  @override
  Future<bool> build() async => false;
}

class _RecordingAuthOwnershipAdapter extends NoopSignalingAdapter {
  final List<String> checkedUsernames = <String>[];

  @override
  Future<void> ensureSignedInAs(String username) async {
    checkedUsernames.add(username);
    await super.ensureSignedInAs(username);
  }
}

final class _RecordedRuntimeError {
  const _RecordedRuntimeError(this.error, this.source, this.fatal);

  final Object error;
  final String source;
  final bool fatal;
}

ProviderContainer _runtimeProviderContainer(
  RainDatabase db,
  SignalingAdapter adapter,
) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        AppBootstrapState(
          environment: AppEnvironment.fromEnvironment(
            runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
          ),
          database: db,
          adapter: adapter,
          forceUpdateService: ForceUpdateService(
            remoteConfig: null,
            updateUrl: 'https://example.com',
          ),
        ),
      ),
      networkStatusProvider.overrideWithValue(
        const AsyncData<NetworkStatusState>(NetworkStatusState.online()),
      ),
      forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
      identityProvider.overrideWith(_SignedInIdentityController.new),
      backgroundServiceProvider.overrideWith(
        _DisabledBackgroundServiceController.new,
      ),
    ],
  );
}

Future<RainRuntimeController?> _readReadyRuntime(
  ProviderContainer container,
) async {
  await container.read(identityProvider.future);
  await container.read(forceUpdateProvider.future);
  await container.pump();
  expect(container.read(authenticatedSessionProvider), isNotNull);
  return container.read(runtimeControllerProvider.future);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() {
    SharedPreferencesAsyncPlatform.instance = null;
  });

  testWidgets('app startup failure renders a visible error screen', (
    tester,
  ) async {
    await rain_app.runRainApp(
      environment: AppEnvironment.fromEnvironment(
        runtimeEnvironment: const <String, String>{},
      ),
      bootstrapper: _FailingBootstrapper(),
    );

    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Rain could not start.'), findsOneWidget);
    expect(find.textContaining('release config missing'), findsOneWidget);
  });

  test('runtime startup surfaces signaling authentication failures', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      ),
      adapter: _FailingAuthAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
    );
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.start(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Could not authenticate signaling backend'),
        ),
      ),
    );
  });

  test('runtime startup verifies Firebase auth owns local identity', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = _RecordingAuthOwnershipAdapter();
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      ),
      adapter: adapter,
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
    );
    addTearDown(runtime.dispose);

    await runtime.start();

    expect(adapter.checkedUsernames, <String>['alice']);
  });

  test('runtime does not poll friend relationships by default', () {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      ),
      adapter: NoopSignalingAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
    );
    addTearDown(runtime.dispose);

    expect(runtime.friendRequestRefreshInterval, Duration.zero);
  });

  test('runtime startup recovers stuck offline sends to queued', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );
    final messageStore = MessageStore(db);
    final offlineQueueStore = OfflineQueueStore(db);
    final envelope = await messageStore.composeOutgoingEnvelope(
      from: 'alice',
      to: 'bob',
      content: 'still needs delivery',
    );
    await messageStore.storeOutgoingEnvelope(
      envelope,
      status: MessageStatus.sent,
    );
    await offlineQueueStore.enqueue(envelope);
    await offlineQueueStore.markStatus(
      envelope.id,
      QueuedMessageStatus.sending,
    );

    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: NoopSignalingAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();

    final messageRow =
        await (db.select(db.messages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(messageRow.status, MessageStatus.queued.name);
    final queuedRow =
        await (db.select(db.queuedMessages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(queuedRow.status, QueuedMessageStatus.queued.name);
  });

  test(
    'runtime startup probes media permissions without blocking startup',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const identity = RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      );
      var warmupCalls = 0;
      final recordedErrors = <_RecordedRuntimeError>[];
      final runtime = RainRuntimeController(
        selfIdentity: identity,
        adapter: NoopSignalingAdapter(),
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
        friendRequestRefreshInterval: Duration.zero,
        startupMediaPermissionWarmup: () async {
          warmupCalls += 1;
          throw StateError('Microphone permission denied');
        },
        errorRecorder:
            (
              Object error,
              StackTrace? stackTrace, {
              required String source,
              required bool fatal,
              String? flutterLibrary,
              String? flutterContext,
            }) {
              recordedErrors.add(_RecordedRuntimeError(error, source, fatal));
            },
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      await runtime.start();

      expect(warmupCalls, 1);
      expect(recordedErrors, hasLength(1));
      expect(recordedErrors.single.source, 'media-permission-warmup');
      expect(recordedErrors.single.fatal, isFalse);
      expect(recordedErrors.single.error, isA<StateError>());
    },
  );

  test(
    'runtime startup surfaces expired Firebase session without clearing inside provider',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await IdentityRepository(db).saveIdentity(
        const RainIdentity(
          username: 'alice',
          displayName: 'Alice',
          createdAt: 0,
          gender: RainGender.female,
        ),
      );

      final runtime = RainRuntimeController(
        selfIdentity: const RainIdentity(
          username: 'alice',
          displayName: 'Alice',
          createdAt: 0,
          gender: RainGender.female,
        ),
        adapter: _ExpiredSessionAdapter(),
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
      );
      addTearDown(runtime.dispose);

      await expectLater(
        runtime.start(),
        throwsA(isA<SignalingSessionExpiredException>()),
      );

      expect(await IdentityRepository(db).loadIdentity(), isNotNull);
    },
  );

  test('runtime logout clears the local identity session', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );
    await IdentityRepository(db).saveIdentity(identity);

    final messageStore = MessageStore(db);
    final offlineQueueStore = OfflineQueueStore(db);
    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: NoopSignalingAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();
    await runtime.logOut();

    expect(await IdentityRepository(db).loadIdentity(), isNull);
  });

  test(
    'runtime logout clears local identity even when backend sign out fails',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const identity = RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      );
      await IdentityRepository(db).saveIdentity(identity);

      final adapter = _FailingSignOutAdapter();
      final recordedErrors = <_RecordedRuntimeError>[];
      final messageStore = MessageStore(db);
      final offlineQueueStore = OfflineQueueStore(db);
      final runtime = RainRuntimeController(
        selfIdentity: identity,
        adapter: adapter,
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
        messageDeliveryService: MessageDeliveryService(
          messageStore: messageStore,
          offlineQueueStore: offlineQueueStore,
        ),
        friendRequestRefreshInterval: Duration.zero,
        errorRecorder:
            (
              Object error,
              StackTrace? stackTrace, {
              required String source,
              required bool fatal,
              String? flutterLibrary,
              String? flutterContext,
            }) {
              recordedErrors.add(_RecordedRuntimeError(error, source, fatal));
            },
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      await runtime.logOut();

      expect(await IdentityRepository(db).loadIdentity(), isNull);
      expect(adapter.signOutCalls, 1);
      expect(adapter.presenceWrites, <bool>[true, false]);
      expect(recordedErrors, hasLength(1));
      expect(recordedErrors.single.source, 'runtime-sign-out');
      expect(recordedErrors.single.fatal, isFalse);
    },
  );

  test(
    'runtime logout clears local identity after app-exit shutdown starts',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const identity = RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      );
      await IdentityRepository(db).saveIdentity(identity);

      final adapter = _BlockingOfflinePresenceAdapter();
      final messageStore = MessageStore(db);
      final offlineQueueStore = OfflineQueueStore(db);
      final runtime = RainRuntimeController(
        selfIdentity: identity,
        adapter: adapter,
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
        messageDeliveryService: MessageDeliveryService(
          messageStore: messageStore,
          offlineQueueStore: offlineQueueStore,
        ),
        friendRequestRefreshInterval: Duration.zero,
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      final exitFuture = runtime.closeForAppExit(AppExitReason.windowClose);
      await adapter.offlineStarted.future;
      final logoutFuture = runtime.logOut();
      adapter.releaseOffline.complete();
      await Future.wait(<Future<void>>[exitFuture, logoutFuture]);

      expect(await IdentityRepository(db).loadIdentity(), isNull);
      expect(adapter.presenceWrites, <bool>[true, false]);
    },
  );

  test('runtime rejects connect actions once shutdown has started', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );

    final adapter = _BlockingOfflinePresenceAdapter();
    final messageStore = MessageStore(db);
    final offlineQueueStore = OfflineQueueStore(db);
    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: adapter,
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();
    final shutdownFuture = runtime.closeForAppExit(AppExitReason.windowClose);
    await adapter.offlineStarted.future;

    await expectLater(
      runtime.connectPeer('bob', interactive: true),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('signing out'),
        ),
      ),
    );

    adapter.releaseOffline.complete();
    await shutdownFuture;
  });

  test('runtime provider signs out while logout cleanup is pending', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = _BlockingOfflinePresenceAdapter();
    final container = _runtimeProviderContainer(db, adapter);
    addTearDown(container.dispose);

    final runtime = await _readReadyRuntime(container);
    expect(runtime, isNotNull);
    expect(
      container.read(appStartupStateProvider).phase,
      AppStartupPhase.ready,
    );

    final logoutFuture = container
        .read(runtimeControllerProvider.notifier)
        .logOut();
    await adapter.offlineStarted.future;

    await expectLater(
      logoutFuture.timeout(const Duration(milliseconds: 100)),
      completes,
    );
    expect(
      container.read(appStartupStateProvider).phase,
      AppStartupPhase.signedOut,
    );
    expect(container.read(runtimeControllerProvider).value, isNull);
    expect(container.read(authenticatedSessionProvider), isNull);

    adapter.releaseOffline.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'runtime provider signs out while destructive account deletion cleanup is pending',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = _BlockingOfflinePresenceAdapter();
      final container = _runtimeProviderContainer(db, adapter);
      addTearDown(container.dispose);

      final runtime = await _readReadyRuntime(container);
      expect(runtime, isNotNull);
      expect(
        container.read(appStartupStateProvider).phase,
        AppStartupPhase.ready,
      );

      final deleteFuture = container
          .read(runtimeControllerProvider.notifier)
          .deleteAccount(password: 'secret1');
      await adapter.offlineStarted.future;

      await expectLater(
        deleteFuture.timeout(const Duration(milliseconds: 100)),
        completes,
      );
      expect(
        container.read(appStartupStateProvider).phase,
        AppStartupPhase.signedOut,
      );
      expect(container.read(runtimeControllerProvider).value, isNull);
      expect(container.read(authenticatedSessionProvider), isNull);
      expect(adapter.deleteAccountCalls, 1);

      adapter.releaseOffline.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'runtime provider restores session after non-destructive account deletion failure',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = _FailingReauthAccountDeletionAdapter();
      final container = _runtimeProviderContainer(db, adapter);
      addTearDown(container.dispose);

      final runtime = await _readReadyRuntime(container);
      expect(runtime, isNotNull);

      await expectLater(
        container
            .read(runtimeControllerProvider.notifier)
            .deleteAccount(password: 'wrong-password'),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.destructiveActionStarted,
            'destructiveActionStarted',
            isFalse,
          ),
        ),
      );

      expect(container.read(runtimeControllerProvider).value, isNotNull);
      expect(container.read(authenticatedSessionProvider), isNotNull);
      expect(
        container.read(appStartupStateProvider).phase,
        AppStartupPhase.ready,
      );
    },
  );

  test(
    'runtime provider keeps settings mounted while account password check is pending',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = _BlockingReauthFailureAdapter();
      final container = _runtimeProviderContainer(db, adapter);
      addTearDown(container.dispose);

      final runtime = await _readReadyRuntime(container);
      expect(runtime, isNotNull);
      expect(
        container.read(appStartupStateProvider).phase,
        AppStartupPhase.ready,
      );

      final deleteFuture = container
          .read(runtimeControllerProvider.notifier)
          .deleteAccount(password: 'wrong-password');
      await adapter.reauthStarted.future;

      expect(
        container.read(appStartupStateProvider).phase,
        AppStartupPhase.ready,
      );
      expect(container.read(runtimeControllerProvider).value, isNotNull);

      adapter.releaseReauth.complete();
      await expectLater(
        deleteFuture,
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.destructiveActionStarted,
            'destructiveActionStarted',
            isFalse,
          ),
        ),
      );

      expect(container.read(runtimeControllerProvider).value, isNotNull);
      expect(container.read(authenticatedSessionProvider), isNotNull);
      expect(
        container.read(appStartupStateProvider).phase,
        AppStartupPhase.ready,
      );
      expect(adapter.deleteAccountCalls, 0);
    },
  );

  test(
    'runtime provider stays signed in when backend account deletion fails before tombstone',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = _FailingBackendAccountDeletionAdapter();
      final container = _runtimeProviderContainer(db, adapter);
      addTearDown(container.dispose);

      final runtime = await _readReadyRuntime(container);
      expect(runtime, isNotNull);

      await expectLater(
        container
            .read(runtimeControllerProvider.notifier)
            .deleteAccount(password: 'secret1'),
        throwsA(
          isA<AccountDeletionException>()
              .having(
                (error) => error.kind,
                'kind',
                AccountDeletionFailureKind.backendCleanupFailed,
              )
              .having(
                (error) => error.destructiveActionStarted,
                'destructiveActionStarted',
                isFalse,
              ),
        ),
      );

      expect(container.read(runtimeControllerProvider).value, isNotNull);
      expect(container.read(authenticatedSessionProvider), isNotNull);
      expect(
        container.read(appStartupStateProvider).phase,
        AppStartupPhase.ready,
      );
      expect(adapter.reauthCalls, 1);
      expect(adapter.deleteAccountCalls, 1);
    },
  );

  test(
    'runtime account deletion does not clear local identity before reauth',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const identity = RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      );
      await IdentityRepository(db).saveIdentity(identity);

      final adapter = _FailingReauthAccountDeletionAdapter();
      final messageStore = MessageStore(db);
      final offlineQueueStore = OfflineQueueStore(db);
      final runtime = RainRuntimeController(
        selfIdentity: identity,
        adapter: adapter,
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
        messageDeliveryService: MessageDeliveryService(
          messageStore: messageStore,
          offlineQueueStore: offlineQueueStore,
        ),
        friendRequestRefreshInterval: Duration.zero,
      );
      addTearDown(runtime.dispose);

      await runtime.start();

      await expectLater(
        runtime.deleteAccount('wrong-password'),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.destructiveActionStarted,
            'destructiveActionStarted',
            isFalse,
          ),
        ),
      );

      expect(await IdentityRepository(db).loadIdentity(), isNotNull);
      expect(adapter.reauthCalls, 1);
      expect(adapter.deleteAccountCalls, 0);
      expect(adapter.presenceWrites, <bool>[true]);
    },
  );

  test(
    'runtime account deletion keeps local identity after backend cleanup failure',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const identity = RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      );
      await IdentityRepository(db).saveIdentity(identity);

      final adapter = _FailingBackendAccountDeletionAdapter();
      final messageStore = MessageStore(db);
      final offlineQueueStore = OfflineQueueStore(db);
      final runtime = RainRuntimeController(
        selfIdentity: identity,
        adapter: adapter,
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
        messageDeliveryService: MessageDeliveryService(
          messageStore: messageStore,
          offlineQueueStore: offlineQueueStore,
        ),
        friendRequestRefreshInterval: Duration.zero,
      );
      addTearDown(runtime.dispose);

      await runtime.start();

      await expectLater(
        runtime.deleteAccount('secret1'),
        throwsA(
          isA<AccountDeletionException>()
              .having(
                (error) => error.kind,
                'kind',
                AccountDeletionFailureKind.backendCleanupFailed,
              )
              .having(
                (error) => error.destructiveActionStarted,
                'destructiveActionStarted',
                isFalse,
              ),
        ),
      );

      expect(await IdentityRepository(db).loadIdentity(), isNotNull);
      expect(adapter.reauthCalls, 1);
      expect(adapter.deleteAccountCalls, 1);
      expect(adapter.presenceWrites, <bool>[true]);
    },
  );

  test(
    'runtime marks the user offline immediately when app detaches',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      const identity = RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      );
      final adapter = _RecordingPresenceAdapter();
      final runtime = RainRuntimeController(
        selfIdentity: identity,
        adapter: adapter,
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
        friendRequestRefreshInterval: Duration.zero,
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      runtime.didChangeAppLifecycleState(AppLifecycleState.detached);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(adapter.presenceWrites.last, isFalse);
    },
  );

  test('runtime app exit shutdown is idempotent', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );
    final adapter = _RecordingPresenceAdapter();
    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: adapter,
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();
    await Future.wait(<Future<void>>[
      runtime.closeForAppExit(AppExitReason.windowClose),
      runtime.closeForAppExit(AppExitReason.windowClose),
    ]);

    expect(adapter.presenceWrites, <bool>[true, false]);
  });

  test('runtime ignores network recovery after app exit shutdown', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );
    final adapter = _RecordingPresenceAdapter();
    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: adapter,
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();
    await runtime.closeForAppExit(AppExitReason.windowClose);
    adapter.presenceWrites.clear();

    await runtime.handleNetworkAvailable('network restored after close');

    expect(adapter.presenceWrites, isEmpty);
  });

  test('desktop shell close policy exits instead of hiding to tray', () {
    final source = File(
      '../../apps/rain/lib/infrastructure/window/desktop_shell_controller.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('windowManager.setPreventClose(true)'));
    expect(source, contains('AppExitCoordinator.instance'));
    expect(source, contains('.shutdown(AppExitReason.windowClose)'));
    expect(source, contains('_runBestEffortCleanup'));
    expect(source, contains('_criticalCloseBudget'));
    expect(source, contains('AppExitReason.windowClose'));
    expect(source, contains('windowManager.destroy()'));
    expect(source, contains('_runBoundedCloseStep'));
    expect(source, contains('Platform.isWindows'));
    expect(source, contains('exit(0)'));
    expect(source, isNot(contains('windowManager.hide()')));
    expect(source, isNot(contains('trayManager')));
  });
}
