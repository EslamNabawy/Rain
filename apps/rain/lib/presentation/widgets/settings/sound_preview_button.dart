/// # sound_preview_button.dart
///
/// Compact "Play test sound" control shown next to the sound effects volume
/// slider so the user can hear the current level.
///
/// **Key types:** SoundPreviewButton
///
/// **Depends on:** Material
library;

import 'package:material_ui/material_ui.dart';

const Key soundPreviewButtonKey = ValueKey<String>('qa.settings.sound_test');

class SoundPreviewButton extends StatelessWidget {
  const SoundPreviewButton({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: soundPreviewButtonKey,
      tooltip: 'Play test sound',
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.play_circle_outline_rounded),
    );
  }
}
