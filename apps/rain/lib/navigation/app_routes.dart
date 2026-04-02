import 'package:flutter/material.dart';
import 'package:rain_core/rain_core.dart';

import '../screens/friend_profile_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static Route<void> settings() {
    return MaterialPageRoute<void>(builder: (_) => const SettingsScreen());
  }

  static Route<void> search() {
    return MaterialPageRoute<void>(builder: (_) => const SearchScreen());
  }

  static Route<void> friendProfile(FriendRecord friend) {
    return MaterialPageRoute<void>(
      builder: (_) => FriendProfileScreen(friend: friend),
    );
  }
}
