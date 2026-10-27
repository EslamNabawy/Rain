import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/presentation/navigation/app_routes.dart';
import 'package:rain/presentation/screens/rain_app.dart';
import 'package:rain/presentation/screens/splash_screen.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain_core/rain_core.dart';

const _update = ForceUpdateResult(
  status: ForceUpdateStatus.current,
  currentVersion: '1.0.0',
  minVersion: '1.0.0',
  updateUrl: 'https://example.com',
);
const _identity = RainIdentity(
  username: 'alice',
  displayName: 'Alice',
  createdAt: 1,
  gender: null,
);

class _StartupHolder extends Notifier<AppStartupState> {
  @override
  AppStartupState build() => const AppStartupState.checkingUpdate();

  void set(AppStartupState next) => state = next;
}

final _holder = NotifierProvider<_StartupHolder, AppStartupState>(
  _StartupHolder.new,
);

Widget _app({bool disableAnimations = false}) {
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Text('shell-home')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      appStartupStateProvider.overrideWith((ref) => ref.watch(_holder)),
      appRouterProvider.overrideWithValue(router),
    ],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: const RainApp(),
    ),
  );
}

void main() {
  testWidgets('splash caption appears only after the caption delay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: RainTheme.dark(),
        home: const RainSplashScreen(caption: 'Starting secure link'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Starting secure link'), findsNothing);
    await tester.pump(RainMotion.splashCaptionDelay);
    await tester.pump(RainMotion.standard);
    expect(find.textContaining('Starting secure link'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('phase changes inside startup keep the splash mounted', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RainApp)),
    );
    final mark = find.byKey(
      const ValueKey<String>('rain-splash-peer-core-mark'),
    );
    expect(mark, findsOneWidget);
    final element = tester.element(mark);

    container
        .read(_holder.notifier)
        .set(const AppStartupState.validatingSession(updateResult: _update));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AnimatedSwitcher), findsWidgets);
    expect(tester.element(mark), same(element));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('startup to ready cross-fades into the app', (tester) async {
    await tester.pumpWidget(_app());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RainApp)),
    );
    container
        .read(_holder.notifier)
        .set(
          const AppStartupState.ready(
            updateResult: _update,
            identity: _identity,
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-fade both surfaces are mounted.
    expect(find.text('shell-home'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('rain-splash-peer-core-mark')),
      findsOneWidget,
    );
    await tester.pump(RainMotion.slow);
    await tester.pump(RainMotion.slow);
    expect(
      find.byKey(const ValueKey<String>('rain-splash-peer-core-mark')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion switches surfaces in one frame', (tester) async {
    await tester.pumpWidget(_app(disableAnimations: true));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RainApp)),
    );
    container
        .read(_holder.notifier)
        .set(
          const AppStartupState.ready(
            updateResult: _update,
            identity: _identity,
          ),
        );
    await tester.pump();
    await tester.pump();
    expect(find.text('shell-home'), findsOneWidget);
    expect(find.byType(RainSplashScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
