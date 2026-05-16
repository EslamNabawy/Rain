import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/presentation/screens/search_screen.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('user search ignores stale result completions', () async {
    final adapter = _DelayedSearchAdapter();
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: <Override>[
        appBootstrapProvider.overrideWithValue(_bootstrap(adapter, db)),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(userSearchProvider.notifier);
    final firstSearch = notifier.search('al');
    final secondSearch = notifier.search('bo');

    adapter.complete('bo', const <BackendIdentity>[
      BackendIdentity(
        username: 'bob',
        uid: 'bob',
        displayName: 'Bob',
        gender: null,
        registeredAt: 0,
        lastSeen: 0,
        lastHeartbeat: 0,
        online: true,
      ),
    ]);
    await secondSearch;

    adapter.complete('al', const <BackendIdentity>[
      BackendIdentity(
        username: 'alice',
        uid: 'alice',
        displayName: 'Alice',
        gender: null,
        registeredAt: 0,
        lastSeen: 0,
        lastHeartbeat: 0,
        online: true,
      ),
    ]);
    await firstSearch;

    final state = container.read(userSearchProvider).valueOrNull;
    expect(state?.query, 'bo');
    expect(state?.results.single.username, 'bob');
  });

  test('refreshCurrent reruns the latest active query', () async {
    final adapter = _CountingSearchAdapter();
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: <Override>[
        appBootstrapProvider.overrideWithValue(_bootstrap(adapter, db)),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(userSearchProvider.notifier);
    await notifier.search('bo');
    await notifier.refreshCurrent();

    expect(adapter.queries, <String>['bo', 'bo']);
  });

  testWidgets('Find result rows stay usable on narrow mobile width', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _ImmediateSearchAdapter();
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appBootstrapProvider.overrideWithValue(_bootstrap(adapter, db)),
          identityProvider.overrideWith(_NoIdentityController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'long');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(
      find.text('Long Handle Display Name That Must Ellipsize'),
      findsOneWidget,
    );
    expect(find.byTooltip('Add friend'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('Find does not autofocus and shows memory-only recent searches', (
    WidgetTester tester,
  ) async {
    final adapter = _ImmediateSearchAdapter();
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appBootstrapProvider.overrideWithValue(_bootstrap(adapter, db)),
          identityProvider.overrideWith(_NoIdentityController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isFalse);

    await tester.enterText(find.byType(TextField), 'long');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('@long'), findsOneWidget);
  });

  testWidgets('Find input guidance is short and readable on mobile', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final adapter = _ImmediateSearchAdapter();
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appBootstrapProvider.overrideWithValue(_bootstrap(adapter, db)),
          identityProvider.overrideWith(_NoIdentityController.new),
        ],
        child: const MaterialApp(home: Scaffold(body: SearchScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Type handle, press Add, or pick from results'),
      findsNothing,
    );
    expect(find.text('Type @handle. Tap + to add.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

AppBootstrapState _bootstrap(SignalingAdapter adapter, RainDatabase db) {
  return AppBootstrapState(
    environment: AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{'RAIN_BACKEND': 'noop'},
    ),
    database: db,
    adapter: adapter,
    forceUpdateService: ForceUpdateService(
      remoteConfig: null,
      updateUrl: 'https://example.com',
    ),
  );
}

class _DelayedSearchAdapter extends NoopSignalingAdapter {
  final Map<String, Completer<List<BackendIdentity>>> _completers =
      <String, Completer<List<BackendIdentity>>>{};

  @override
  Future<List<BackendIdentity>> searchUsers(String query) {
    return _completers
        .putIfAbsent(query, () => Completer<List<BackendIdentity>>())
        .future;
  }

  void complete(String query, List<BackendIdentity> results) {
    _completers.putIfAbsent(query, () => Completer<List<BackendIdentity>>());
    _completers[query]!.complete(results);
  }
}

class _ImmediateSearchAdapter extends NoopSignalingAdapter {
  @override
  Future<List<BackendIdentity>> searchUsers(String query) async {
    return const <BackendIdentity>[
      BackendIdentity(
        username: 'long_handle_user',
        uid: 'long_handle_user',
        displayName: 'Long Handle Display Name That Must Ellipsize',
        gender: 'female',
        registeredAt: 0,
        lastSeen: 0,
        lastHeartbeat: 0,
        online: false,
      ),
    ];
  }
}

class _CountingSearchAdapter extends NoopSignalingAdapter {
  final List<String> queries = <String>[];

  @override
  Future<List<BackendIdentity>> searchUsers(String query) async {
    queries.add(query);
    return const <BackendIdentity>[];
  }
}

class _NoIdentityController extends IdentityController {
  @override
  Future<RainIdentity?> build() async => null;
}
