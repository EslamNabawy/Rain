import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/presentation/screens/root_screen.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  testWidgets('RootScreen does not block when update check is unavailable', (
    WidgetTester tester,
  ) async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap(db)),
          forceUpdateProvider.overrideWith(
            _UnavailableForceUpdateController.new,
          ),
          identityProvider.overrideWith(_NoIdentityController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: RootScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not verify update status.'), findsNothing);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('RootScreen loading state uses Rain splash surface', (
    WidgetTester tester,
  ) async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap(db)),
          forceUpdateProvider.overrideWith(_LoadingForceUpdateController.new),
          identityProvider.overrideWith(_NoIdentityController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: RootScreen())),
      ),
    );
    await tester.pump();

    expect(find.text('Rain'), findsOneWidget);
    expect(find.text('Peer command link'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });
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

class _UnavailableForceUpdateController extends ForceUpdateController {
  @override
  Future<ForceUpdateResult> build() async {
    return const ForceUpdateResult(
      status: ForceUpdateStatus.checkUnavailable,
      currentVersion: '1.0.0',
      minVersion: '1.0.0',
      updateUrl: 'https://example.com',
    );
  }
}

class _LoadingForceUpdateController extends ForceUpdateController {
  @override
  Future<ForceUpdateResult> build() => Completer<ForceUpdateResult>().future;
}

class _NoIdentityController extends IdentityController {
  @override
  Future<RainIdentity?> build() async => null;
}
