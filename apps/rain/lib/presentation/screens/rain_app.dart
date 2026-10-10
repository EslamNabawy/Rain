/// # rain_app
///
/// Root MaterialApp widget for Rain. Configures routing, theming (light/dark),
/// and startup-phase-based surface navigation including standalone surfaces
/// for signed-out and account-deletion states.
///
/// **Key types:** RainApp, _StandaloneSurfaceNavigator
///
/// **Depends on:** appRouterProvider, RainTheme, startup_surface
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/state/app_providers.dart';
import 'package:rain/presentation/navigation/app_routes.dart';
import 'package:rain/presentation/screens/root_screen.dart';
import 'package:rain/presentation/screens/startup_surface.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

class RainApp extends ConsumerWidget {
  const RainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = ref.watch(appRouterProvider);
    final startup = ref.watch(appStartupStateProvider);

    return MaterialApp.router(
      title: 'Rain',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode.themeMode,
      theme: RainTheme.light(),
      darkTheme: RainTheme.dark(),
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        if (!startup.usesRoutedAppShell) {
          if (startup.phase == AppStartupPhase.signedOut) {
            return _StandaloneSurfaceNavigator(child: const RootScreen());
          }
          return RainStartupSurface(state: startup);
        }
        if (startup.phase == AppStartupPhase.deletingAccount) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              const ModalBarrier(color: Colors.transparent, dismissible: false),
              RainStartupSurface(state: startup),
            ],
          );
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

class _StandaloneSurfaceNavigator extends StatelessWidget {
  const _StandaloneSurfaceNavigator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (_) {
        return PageRouteBuilder<void>(
          pageBuilder:
              (
                BuildContext context,
                Animation<double> animation,
                Animation<double> secondaryAnimation,
              ) => child,
          transitionsBuilder:
              (
                BuildContext context,
                Animation<double> animation,
                Animation<double> secondaryAnimation,
                Widget child,
              ) => child,
        );
      },
    );
  }
}
