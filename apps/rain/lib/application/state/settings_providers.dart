import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppThemeMode { dark, light, system }

extension AppThemeModeX on AppThemeMode {
  ThemeMode get themeMode => switch (this) {
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.system => ThemeMode.system,
  };
}

final themeModeProvider = NotifierProvider<ThemeModeController, AppThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() => AppThemeMode.dark;

  void setDark() => state = AppThemeMode.dark;
  void setLight() => state = AppThemeMode.light;
  void setSystem() => state = AppThemeMode.system;
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
      RecentSearchesController.new,
    );

class RecentSearchesController extends Notifier<List<String>> {
  static const int maxRecentSearches = 5;

  @override
  List<String> build() => const <String>[];

  void add(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return;
    }
    state = <String>[
      normalized,
      ...state.where((String item) => item != normalized),
    ].take(maxRecentSearches).toList(growable: false);
  }

  void clear() {
    state = const <String>[];
  }
}
