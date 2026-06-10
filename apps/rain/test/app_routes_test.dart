import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain/presentation/navigation/app_routes.dart';
import 'package:rain/presentation/navigation/rain_navigation_shell.dart';
import 'package:rain/presentation/screens/friend_profile_screen.dart';
import 'package:rain/presentation/screens/rain_app.dart';
import 'package:rain/presentation/screens/search_screen.dart';
import 'package:rain/presentation/screens/settings_screen.dart';
import 'package:rain/presentation/screens/splash_screen.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app shell readiness waits for signed-in runtime startup', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = _runtimeLoadingContainer(db);
    addTearDown(container.dispose);

    await container.read(identityProvider.future);
    await container.read(forceUpdateProvider.future);

    expect(
      container.read(runtimeControllerProvider),
      isA<AsyncLoading<RainRuntimeController?>>(),
    );
    expect(container.read(appShellReadinessProvider).showNavigation, isFalse);
    expect(
      container.read(appShellReadinessProvider).phase,
      AppStartupPhase.startingRuntime,
    );
  });

  test('app shell readiness allows navigation after runtime settles', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = _runtimeSettledContainer(db);
    addTearDown(container.dispose);

    await container.read(identityProvider.future);
    await container.read(forceUpdateProvider.future);
    await container.read(runtimeControllerProvider.future);

    expect(container.read(appShellReadinessProvider).showNavigation, isTrue);
    expect(
      container.read(appShellReadinessProvider).phase,
      AppStartupPhase.ready,
    );
  });

  test('startup state checks update before validating session', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(db)),
        networkStatusProvider.overrideWith(
          (Ref ref) => Stream<NetworkStatusState>.value(
            const NetworkStatusState.online(),
          ),
        ),
        forceUpdateProvider.overrideWith(_LoadingForceUpdateController.new),
        identityProvider.overrideWith(_SignedInIdentityController.new),
        runtimeControllerProvider.overrideWith(_SettledRuntimeController.new),
      ],
    );
    addTearDown(container.dispose);

    final startup = container.read(appStartupStateProvider);

    expect(startup.phase, AppStartupPhase.checkingUpdate);
    expect(startup.showNavigation, isFalse);
  });

  test('startup state blocks on required update before identity', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(db)),
        networkStatusProvider.overrideWith(
          (Ref ref) => Stream<NetworkStatusState>.value(
            const NetworkStatusState.online(),
          ),
        ),
        forceUpdateProvider.overrideWith(_RequiredForceUpdateController.new),
        identityProvider.overrideWith(_SignedInIdentityController.new),
        runtimeControllerProvider.overrideWith(_SettledRuntimeController.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(forceUpdateProvider.future);
    final startup = container.read(appStartupStateProvider);

    expect(startup.phase, AppStartupPhase.updateRequired);
    expect(startup.showNavigation, isFalse);
  });

  test('startup state validates session before runtime startup', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(db)),
        networkStatusProvider.overrideWith(
          (Ref ref) => Stream<NetworkStatusState>.value(
            const NetworkStatusState.online(),
          ),
        ),
        forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
        identityProvider.overrideWith(_LoadingIdentityController.new),
        runtimeControllerProvider.overrideWith(_SettledRuntimeController.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(forceUpdateProvider.future);
    final startup = container.read(appStartupStateProvider);

    expect(startup.phase, AppStartupPhase.validatingSession);
    expect(startup.showNavigation, isFalse);
  });

  test('startup state exposes signed-out as an app phase', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(db)),
        networkStatusProvider.overrideWith(
          (Ref ref) => Stream<NetworkStatusState>.value(
            const NetworkStatusState.online(),
          ),
        ),
        forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
        identityProvider.overrideWith(_SignedOutIdentityController.new),
        runtimeControllerProvider.overrideWith(_LoadingRuntimeController.new),
      ],
    );
    addTearDown(container.dispose);

    await container.read(forceUpdateProvider.future);
    await container.read(identityProvider.future);
    final startup = container.read(appStartupStateProvider);

    expect(startup.phase, AppStartupPhase.signedOut);
    expect(startup.showNavigation, isFalse);
  });

  test('startup redirect blocks protected routes until ready', () async {
    final update = const ForceUpdateResult(
      status: ForceUpdateStatus.current,
      currentVersion: '1.0.0',
      minVersion: '1.0.0',
      updateUrl: 'https://example.com',
    );
    final identity = const RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 1,
      gender: null,
    );

    expect(
      appStartupRedirectForPath(
        AppStartupState.validatingSession(updateResult: update),
        '/settings',
      ),
      '/',
    );
    expect(
      appStartupRedirectForPath(
        AppStartupState.signedOut(updateResult: update),
        '/search',
      ),
      '/',
    );
    expect(
      appStartupRedirectForPath(
        AppStartupState.startingRuntime(
          updateResult: update,
          identity: identity,
        ),
        '/friend/bob',
      ),
      '/',
    );
    expect(
      appStartupRedirectForPath(
        AppStartupState.deletingAccount(
          updateResult: update,
          identity: identity,
        ),
        '/settings',
      ),
      isNull,
    );
    expect(
      appStartupRedirectForPath(
        AppStartupState.ready(updateResult: update, identity: identity),
        '/settings',
      ),
      isNull,
    );
  });

  test('startup state reconciles expired sessions before home', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap(db)),
        networkStatusProvider.overrideWith(
          (Ref ref) => Stream<NetworkStatusState>.value(
            const NetworkStatusState.online(),
          ),
        ),
        forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
        identityProvider.overrideWith(_SignedInIdentityController.new),
        runtimeControllerProvider.overrideWith(
          _SessionExpiredRuntimeController.new,
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(forceUpdateProvider.future);
    await container.read(identityProvider.future);
    expect(
      container.read(appStartupStateProvider).phase,
      AppStartupPhase.startingRuntime,
    );
    await container.pump();
    final startup = container.read(appStartupStateProvider);

    expect(startup.phase, AppStartupPhase.sessionExpired);
    expect(startup.showNavigation, isFalse);
  });

  testWidgets(
    'signed-in runtime loading shows splash without bottom navigation',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(_runtimeLoadingScope(db, child: const RainApp()));
      await tester.pump();
      await tester.pump();

      expect(find.byType(RainSplashScreen), findsOneWidget);
      expect(find.byType(RainNavigationShell), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    },
  );

  testWidgets('signed-out state renders auth flow without app shell', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(_signedOutScope(db, child: const RainApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Create account'), findsOneWidget);
    expect(find.byType(RainNavigationShell), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('protected routes do not render while runtime is loading', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = _runtimeLoadingContainer(db);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const RainApp()),
    );
    await tester.pump();
    container.read(appRouterProvider).go('/settings');
    await tester.pump();
    await tester.pump();

    expect(find.byType(RainSplashScreen), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(FriendProfileScreen), findsNothing);
    expect(find.byType(RainNavigationShell), findsNothing);
  });

  testWidgets('protected routes do not render while signed out', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = _signedOutContainer(db);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const RainApp()),
    );
    await tester.pump();
    container.read(appRouterProvider).go('/search');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Create account'), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.byType(FriendProfileScreen), findsNothing);
    expect(find.byType(RainNavigationShell), findsNothing);
  });

  testWidgets('required update blocks the routed shell globally', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(_requiredUpdateScope(db, child: const RainApp()));
    await tester.pumpAndSettle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.byType(RainNavigationShell), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('startup failures block the routed shell globally', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(_failedUpdateScope(db, child: const RainApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Rain could not start.'), findsOneWidget);
    expect(find.byType(RainNavigationShell), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
  });
}

ProviderContainer _runtimeLoadingContainer(RainDatabase db) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(db)),
      networkStatusProvider.overrideWith(
        (Ref ref) =>
            Stream<NetworkStatusState>.value(const NetworkStatusState.online()),
      ),
      forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
      identityProvider.overrideWith(_SignedInIdentityController.new),
      runtimeControllerProvider.overrideWith(_LoadingRuntimeController.new),
    ],
  );
}

ProviderContainer _runtimeSettledContainer(RainDatabase db) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(db)),
      networkStatusProvider.overrideWith(
        (Ref ref) =>
            Stream<NetworkStatusState>.value(const NetworkStatusState.online()),
      ),
      forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
      identityProvider.overrideWith(_SignedInIdentityController.new),
      runtimeControllerProvider.overrideWith(_SettledRuntimeController.new),
    ],
  );
}

ProviderContainer _signedOutContainer(RainDatabase db) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(db, fallback: false)),
      networkStatusProvider.overrideWith(
        (Ref ref) =>
            Stream<NetworkStatusState>.value(const NetworkStatusState.online()),
      ),
      forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
      identityProvider.overrideWith(_SignedOutIdentityController.new),
      runtimeControllerProvider.overrideWith(_LoadingRuntimeController.new),
    ],
  );
}

ProviderScope _runtimeLoadingScope(RainDatabase db, {required Widget child}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(db)),
      networkStatusProvider.overrideWith(
        (Ref ref) =>
            Stream<NetworkStatusState>.value(const NetworkStatusState.online()),
      ),
      forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
      identityProvider.overrideWith(_SignedInIdentityController.new),
      runtimeControllerProvider.overrideWith(_LoadingRuntimeController.new),
    ],
    child: child,
  );
}

ProviderScope _signedOutScope(RainDatabase db, {required Widget child}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(db, fallback: false)),
      networkStatusProvider.overrideWith(
        (Ref ref) =>
            Stream<NetworkStatusState>.value(const NetworkStatusState.online()),
      ),
      forceUpdateProvider.overrideWith(_ReadyForceUpdateController.new),
      identityProvider.overrideWith(_SignedOutIdentityController.new),
      runtimeControllerProvider.overrideWith(_LoadingRuntimeController.new),
    ],
    child: child,
  );
}

ProviderScope _requiredUpdateScope(RainDatabase db, {required Widget child}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(db)),
      networkStatusProvider.overrideWith(
        (Ref ref) =>
            Stream<NetworkStatusState>.value(const NetworkStatusState.online()),
      ),
      forceUpdateProvider.overrideWith(_RequiredForceUpdateController.new),
      identityProvider.overrideWith(_SignedInIdentityController.new),
      runtimeControllerProvider.overrideWith(_SettledRuntimeController.new),
    ],
    child: child,
  );
}

ProviderScope _failedUpdateScope(RainDatabase db, {required Widget child}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(db)),
      networkStatusProvider.overrideWith(
        (Ref ref) =>
            Stream<NetworkStatusState>.value(const NetworkStatusState.online()),
      ),
      forceUpdateProvider.overrideWith(_FailedForceUpdateController.new),
      identityProvider.overrideWith(_SignedInIdentityController.new),
      runtimeControllerProvider.overrideWith(_SettledRuntimeController.new),
    ],
    child: child,
  );
}

AppBootstrapState _bootstrap(RainDatabase db, {bool fallback = true}) {
  return AppBootstrapState(
    environment: AppEnvironment.fromEnvironment(
      runtimeEnvironment: fallback
          ? const <String, String>{'RAIN_BACKEND': 'noop'}
          : const <String, String>{'RAIN_BACKEND': 'firebase'},
    ),
    database: db,
    adapter: NoopSignalingAdapter(),
    forceUpdateService: ForceUpdateService(
      remoteConfig: null,
      updateUrl: 'https://example.com',
    ),
  );
}

class _ReadyForceUpdateController extends ForceUpdateController {
  @override
  Future<ForceUpdateResult> build() async {
    return const ForceUpdateResult(
      status: ForceUpdateStatus.current,
      currentVersion: '1.0.0',
      minVersion: '1.0.0',
      updateUrl: 'https://example.com',
    );
  }
}

class _LoadingForceUpdateController extends ForceUpdateController {
  @override
  Future<ForceUpdateResult> build() {
    return Completer<ForceUpdateResult>().future;
  }
}

class _RequiredForceUpdateController extends ForceUpdateController {
  @override
  Future<ForceUpdateResult> build() async {
    return const ForceUpdateResult(
      status: ForceUpdateStatus.updateRequired,
      currentVersion: '1.0.0',
      minVersion: '2.0.0',
      updateUrl: 'https://example.com',
    );
  }
}

class _FailedForceUpdateController extends ForceUpdateController {
  @override
  Future<ForceUpdateResult> build() {
    throw StateError('update check failed');
  }
}

class _SignedInIdentityController extends IdentityController {
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

class _LoadingIdentityController extends IdentityController {
  @override
  Future<RainIdentity?> build() {
    return Completer<RainIdentity?>().future;
  }
}

class _SignedOutIdentityController extends IdentityController {
  @override
  Future<RainIdentity?> build() async => null;
}

class _LoadingRuntimeController extends RuntimeController {
  @override
  Future<RainRuntimeController?> build() {
    return Completer<RainRuntimeController?>().future;
  }
}

class _SettledRuntimeController extends RuntimeController {
  @override
  Future<RainRuntimeController?> build() async {
    final database = ref.watch(databaseProvider);
    final messageStore = MessageStore(database);
    final offlineQueueStore = OfflineQueueStore(database);
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: null,
      ),
      adapter: NoopSignalingAdapter(),
      brain: null,
      database: database,
      friendStore: FriendStore(database),
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    ref.onDispose(() => unawaited(runtime.dispose()));
    return runtime;
  }
}

class _SessionExpiredRuntimeController extends RuntimeController {
  @override
  Future<RainRuntimeController?> build() =>
      Future<RainRuntimeController?>.error(
        const SignalingSessionExpiredException('sign in again'),
        StackTrace.current,
      );
}
