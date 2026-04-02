import 'package:flutter/material.dart';
import 'package:rain_core/rain_core.dart';

import '../screens/friend_profile_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static Route<void> settings() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/settings'),
      maintainState: false,
      builder: (_) => const SettingsScreen(),
    );
  }

  static Route<void> search() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/search'),
      maintainState: false,
      builder: (_) => const SearchScreen(),
    );
  }

  static Route<void> friendProfile(FriendRecord friend) {
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: '/friend/${friend.username}'),
      maintainState: false,
      builder: (_) => FriendProfileScreen(friend: friend),
    );
  }
}
