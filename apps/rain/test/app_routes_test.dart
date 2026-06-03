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
import 'package:rain/presentation/screens/rain_app.dart';
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
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    },
  );
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

AppBootstrapState _bootstrap(RainDatabase db) {
  return AppBootstrapState(
    environment: AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
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
  Future<RainRuntimeController?> build() async => null;
}

class _SessionExpiredRuntimeController extends RuntimeController {
  @override
  Future<RainRuntimeController?> build() async {
    throw const SignalingSessionExpiredException('sign in again');
  }
}
