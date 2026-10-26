/// # rain_snack.dart
///
/// One snackbar helper: themed floating snackbar with a leading severity icon,
/// 4 s duration (6 s for errors) and an optional action.
///
/// **Key types:** showRainSnack
///
/// **Depends on:** RainStateSeverity, theme snackBarTheme
library;

import 'package:flutter/material.dart';

import 'package:rain/presentation/branding/rain_state_surfaces.dart';

const Duration rainSnackDuration = Duration(seconds: 4);
const Duration rainErrorSnackDuration = Duration(seconds: 6);

/// Takes the messenger (not a BuildContext) so callers can capture it before
/// an `await` and still show the snackbar safely afterwards.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showRainSnack(
  ScaffoldMessengerState messenger,
  String message, {
  RainStateSeverity severity = RainStateSeverity.neutral,
  SnackBarAction? action,
}) {
  final theme = Theme.of(messenger.context);
  final scheme = theme.colorScheme;
  final isError = severity == RainStateSeverity.error;
  final foreground = isError
      ? scheme.onError
      : theme.snackBarTheme.contentTextStyle?.color ?? scheme.onInverseSurface;
  final icon = switch (severity) {
    RainStateSeverity.neutral => Icons.check_circle_outline_rounded,
    RainStateSeverity.warning => Icons.warning_amber_rounded,
    RainStateSeverity.error => Icons.error_outline_rounded,
  };
  return messenger.showSnackBar(
    SnackBar(
      backgroundColor: isError ? scheme.error : null,
      duration: isError ? rainErrorSnackDuration : rainSnackDuration,
      action: action,
      content: Row(
        children: <Widget>[
          Icon(
            icon,
            key: ValueKey<String>('rain-snack-icon-${severity.name}'),
            size: 20,
            color: foreground,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: isError ? TextStyle(color: foreground) : null,
            ),
          ),
        ],
      ),
    ),
  );
}
