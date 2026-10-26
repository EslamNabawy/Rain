/// # haptic_feedback_tile.dart
///
/// Settings switch for optional haptic feedback. Shown on Android only, the
/// one platform where Rain plays haptics.
///
/// **Key types:** HapticFeedbackTile
///
/// **Depends on:** hapticFeedbackEnabledProvider
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rain/application/state/feedback_settings_providers.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';

const Key hapticFeedbackTileKey = ValueKey<String>('qa.settings.haptics');

class HapticFeedbackTile extends ConsumerWidget {
  const HapticFeedbackTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    final setting = ref.watch(hapticFeedbackEnabledProvider);
    final enabled =
        setting.value ?? AppSettingsStore.defaultHapticFeedbackEnabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Divider(height: 1),
        SwitchListTile(
          key: hapticFeedbackTileKey,
          secondary: const Icon(Icons.vibration),
          title: const Text('Haptic feedback'),
          subtitle: Text(enabled ? 'On' : 'Off'),
          value: enabled,
          onChanged: setting.isLoading
              ? null
              : (bool value) => unawaited(
                  ref
                      .read(hapticFeedbackEnabledProvider.notifier)
                      .setEnabled(value),
                ),
        ),
      ],
    );
  }
}
