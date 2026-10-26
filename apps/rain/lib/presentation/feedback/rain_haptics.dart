/// # rain_haptics.dart
///
/// Optional haptic feedback for sends, call actions and toggles. Android only,
/// and only while the user's haptic feedback setting is on.
///
/// **Key types:** RainHaptics, RainHapticKind
///
/// **Depends on:** HapticFeedback, hapticFeedbackEnabledProvider
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/state/feedback_settings_providers.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';

enum RainHapticKind { selection, light, medium }

abstract final class RainHaptics {
  static void selection(BuildContext context) =>
      play(context, RainHapticKind.selection);

  static void light(BuildContext context) =>
      play(context, RainHapticKind.light);

  static void medium(BuildContext context) =>
      play(context, RainHapticKind.medium);

  static void play(BuildContext context, RainHapticKind kind) {
    if (defaultTargetPlatform != TargetPlatform.android || !_enabled(context)) {
      return;
    }
    switch (kind) {
      case RainHapticKind.selection:
        HapticFeedback.selectionClick();
      case RainHapticKind.light:
        HapticFeedback.lightImpact();
      case RainHapticKind.medium:
        HapticFeedback.mediumImpact();
    }
  }

  /// Returns [callback] with a haptic tick in front of it; null stays null so
  /// disabled buttons stay disabled.
  static VoidCallback? wrap(
    BuildContext context,
    VoidCallback? callback,
    RainHapticKind kind,
  ) {
    if (callback == null) {
      return null;
    }
    return () {
      play(context, kind);
      callback();
    };
  }

  static bool _enabled(BuildContext context) {
    final ProviderContainer container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
    } on StateError {
      // Widgets pumped without a ProviderScope (isolated widget tests).
      return AppSettingsStore.defaultHapticFeedbackEnabled;
    }
    // Still loading counts as off so a tap never vibrates against a saved
    // "off"; this read starts the load, so later taps see the real value.
    return container.read(hapticFeedbackEnabledProvider).value ?? false;
  }
}
