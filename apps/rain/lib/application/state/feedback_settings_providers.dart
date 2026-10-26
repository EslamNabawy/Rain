/// # feedback_settings_providers.dart
///
/// Riverpod provider for the user's haptic feedback preference.
///
/// **Key types:** hapticFeedbackEnabledProvider, HapticFeedbackSettingsController
///
/// **Depends on:** AppSettingsStore via core_providers
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core_providers.dart';

final hapticFeedbackEnabledProvider =
    AsyncNotifierProvider<HapticFeedbackSettingsController, bool>(
      HapticFeedbackSettingsController.new,
    );

class HapticFeedbackSettingsController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(appSettingsStoreProvider).loadHapticFeedbackEnabled();
  }

  Future<void> setEnabled(bool enabled) async {
    await ref.read(appSettingsStoreProvider).setHapticFeedbackEnabled(enabled);
    state = AsyncData<bool>(enabled);
  }
}
