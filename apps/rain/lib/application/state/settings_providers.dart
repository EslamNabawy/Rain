import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/runtime/media_device_settings.dart';
import 'core_providers.dart';

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

final microphoneSelectionProvider =
    AsyncNotifierProvider<
      MicrophoneSelectionController,
      MicrophoneSelectionState
    >(MicrophoneSelectionController.new);

class MicrophoneSelectionController
    extends AsyncNotifier<MicrophoneSelectionState> {
  @override
  Future<MicrophoneSelectionState> build() {
    return ref.watch(mediaDeviceSettingsProvider).loadMicrophoneSelection();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(mediaDeviceSettingsProvider).loadMicrophoneSelection(),
    );
  }

  Future<void> selectMicrophone(String? deviceId) async {
    final service = ref.read(mediaDeviceSettingsProvider);
    final previous = state.value;
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() async {
      await service.selectMicrophone(deviceId);
      return service.loadMicrophoneSelection();
    });
    state = next;
    if (next.hasError && previous != null) {
      state = AsyncValue.data(previous);
      Error.throwWithStackTrace(next.error!, next.stackTrace!);
    }
  }
}
