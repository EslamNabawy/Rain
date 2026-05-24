import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
