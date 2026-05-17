import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/state/app_providers.dart';
import 'package:rain/presentation/screens/friend_profile_screen.dart';
import 'package:rain/presentation/screens/root_screen.dart';
import 'package:rain/presentation/screens/search_screen.dart';
import 'package:rain/presentation/screens/settings_screen.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'rain_navigation_shell.dart';

final appRouterProvider = Provider<GoRouter>((Ref ref) {
  final refreshListenable = _RouterRefreshNotifier(ref);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    refreshListenable: refreshListenable,
    redirect: (BuildContext context, GoRouterState state) {
      final identity = ref.read(identityProvider);
      if (!identity.hasValue) {
        return null;
      }
      final isSignedIn = identity.valueOrNull != null;
      if (!isSignedIn && state.uri.path != '/') {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      ShellRoute(
        builder: (BuildContext context, GoRouterState state, Widget child) {
          return Consumer(
            builder: (BuildContext context, WidgetRef ref, Widget? _) {
              final identity = ref.watch(identityProvider).valueOrNull;
              final forceUpdate = ref.watch(forceUpdateProvider).valueOrNull;
              final networkStatus = ref
                  .watch(networkStatusProvider)
                  .valueOrNull;
              final canUseCurrentVersion =
                  forceUpdate != null && !forceUpdate.requiresUpdate;
              return RainNavigationShell(
                location: state.uri.path,
                showNavigation: identity != null && canUseCurrentVersion,
                networkStatusMessage:
                    networkStatus != null && networkStatus.blocksNetworkActions
                    ? networkStatus.message
                    : null,
                child: child,
              );
            },
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            name: AppRoutes.home,
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _rainPage(state, const RootScreen()),
          ),
          GoRoute(
            path: '/settings',
            name: AppRoutes.settings,
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _rainPage(state, const SettingsScreen()),
          ),
          GoRoute(
            path: '/search',
            name: AppRoutes.search,
            pageBuilder: (BuildContext context, GoRouterState state) =>
                _rainPage(state, const SearchScreen()),
          ),
          GoRoute(
            path: '/friend/:username',
            name: AppRoutes.friendProfile,
            pageBuilder: (BuildContext context, GoRouterState state) {
              final username = state.pathParameters['username'] ?? '';
              final friend = state.extra is FriendRecord
                  ? state.extra! as FriendRecord
                  : null;
              return _rainPage(
                state,
                FriendProfileScreen(username: username, initialFriend: friend),
              );
            },
          ),
        ],
      ),
    ],
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen<AsyncValue<RainIdentity?>>(identityProvider, (_, _) {
      notifyListeners();
    });
  }
}

CustomTransitionPage<void> _rainPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.name,
    arguments: state.extra,
    transitionDuration: RainMotion.page,
    reverseTransitionDuration: RainMotion.pageReverse,
    child: child,
    transitionsBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final fade = Tween<double>(begin: 0.72, end: 1).animate(curved);
          final slide = Tween<Offset>(
            begin: const Offset(0.018, 0),
            end: Offset.zero,
          ).animate(curved);

          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
  );
}

class AppRoutes {
  const AppRoutes._();

  static const String home = 'home';
  static const String settings = 'settings';
  static const String search = 'search';
  static const String friendProfile = 'friendProfile';

  static void openSettings(BuildContext context) {
    context.pushNamed(settings);
  }

  static void openSearch(BuildContext context) {
    context.pushNamed(search);
  }

  static void openFriendProfile(BuildContext context, FriendRecord friend) {
    context.pushNamed(
      friendProfile,
      pathParameters: <String, String>{'username': friend.username},
      extra: friend,
    );
  }
}
