import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/runtime/media_device_settings.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
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

  Future<void> testSelectedMicrophone() {
    return ref
        .read(mediaDeviceSettingsProvider)
        .testSelectedMicrophoneAvailability();
  }
}

final voiceAudioSettingsProvider =
    AsyncNotifierProvider<VoiceAudioSettingsController, AppAudioSettings>(
      VoiceAudioSettingsController.new,
    );

class VoiceAudioSettingsController extends AsyncNotifier<AppAudioSettings> {
  @override
  Future<AppAudioSettings> build() {
    return ref.watch(appSettingsStoreProvider).loadAudioSettings();
  }

  Future<void> setSoundEffectsEnabled(bool enabled) {
    return _persist(
      write: (AppSettingsStore store) => store.setSoundEffectsEnabled(enabled),
      apply: (AppAudioSettings current) =>
          current.copyWith(soundEffectsEnabled: enabled),
    );
  }

  Future<void> setSoundEffectsVolume(double volume) {
    final normalized = AppSettingsStore.normalizeSoundEffectsVolume(volume);
    return _persist(
      write: (AppSettingsStore store) =>
          store.setSoundEffectsVolume(normalized),
      apply: (AppAudioSettings current) =>
          current.copyWith(soundEffectsVolume: normalized),
    );
  }

  Future<void> setCallSoundsEnabled(bool enabled) {
    return _persist(
      write: (AppSettingsStore store) => store.setCallSoundsEnabled(enabled),
      apply: (AppAudioSettings current) =>
          current.copyWith(callSoundsEnabled: enabled),
    );
  }

  Future<void> setReduceSoundsDuringCall(bool enabled) {
    return _persist(
      write: (AppSettingsStore store) =>
          store.setReduceSoundsDuringCall(enabled),
      apply: (AppAudioSettings current) =>
          current.copyWith(reduceSoundsDuringCall: enabled),
    );
  }

  Future<void> setDefaultOutputPreference(
    CallAudioOutputPreference preference,
  ) {
    return _persist(
      write: (AppSettingsStore store) =>
          store.setDefaultCallAudioOutputPreference(preference),
      apply: (AppAudioSettings current) =>
          current.copyWith(defaultOutputPreference: preference),
    );
  }

  Future<AppAudioSettings> _currentSettings() async {
    return state.value ??
        ref.read(appSettingsStoreProvider).loadAudioSettings();
  }

  Future<void> _persist({
    required Future<void> Function(AppSettingsStore store) write,
    required AppAudioSettings Function(AppAudioSettings current) apply,
  }) async {
    final store = ref.read(appSettingsStoreProvider);
    final previous = await _currentSettings();
    final next = apply(previous);
    state = AsyncValue.data(next);
    try {
      await write(store);
    } catch (error, stackTrace) {
      state = AsyncValue.data(previous);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
