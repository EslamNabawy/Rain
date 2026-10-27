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

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/state/app_providers.dart';
import 'package:rain/presentation/navigation/app_routes.dart';
import 'package:rain/presentation/performance/rain_motion_policy.dart';
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
        final (String kind, Widget surface) = _surfaceFor(startup, child);
        return AnimatedSwitcher(
          duration: RainMotionPolicy.of(context).d(RainMotion.slow),
          switchInCurve: RainMotion.enter,
          switchOutCurve: RainMotion.exit,
          layoutBuilder: (Widget? current, List<Widget> previous) {
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[...previous, ?current],
            );
          },
          transitionBuilder: (Widget child, Animation<double> animation) =>
              FadeTransition(opacity: animation, child: child),
          child: KeyedSubtree(key: ValueKey<String>(kind), child: surface),
        );
      },
    );
  }
}

/// Picks the surface and its switcher key. Phase changes inside 'startup' keep
/// the key so the splash stays mounted and only its caption changes. Account
/// deletion overlays the routed shell, so it shares the 'shell' key: the router
/// navigator holds a GlobalKey and must not be mounted twice during a fade.
(String, Widget) _surfaceFor(AppStartupState startup, Widget? child) {
  if (!startup.usesRoutedAppShell) {
    if (startup.phase == AppStartupPhase.signedOut) {
      return (
        'standalone',
        _StandaloneSurfaceNavigator(child: const RootScreen()),
      );
    }
    return ('startup', RainStartupSurface(state: startup));
  }
  if (startup.phase == AppStartupPhase.deletingAccount) {
    return (
      'shell',
      Stack(
        fit: StackFit.expand,
        children: <Widget>[
          child ?? const SizedBox.shrink(),
          const ModalBarrier(color: Colors.transparent, dismissible: false),
          RainStartupSurface(state: startup),
        ],
      ),
    );
  }
  return ('shell', child ?? const SizedBox.shrink());
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
