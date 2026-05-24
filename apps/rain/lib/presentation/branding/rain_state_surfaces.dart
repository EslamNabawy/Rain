import 'package:flutter/material.dart';

import '../theme/rain_theme.dart';

enum RainStateSeverity { neutral, warning, error }

class RainMistStateCard extends StatelessWidget {
  const RainMistStateCard({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.iconSize,
    this.action,
    this.severity = RainStateSeverity.neutral,
    this.compact = false,
    this.maxWidth = 360,
  });

  final String title;
  final String message;
  final IconData? icon;
  final double? iconSize;
  final Widget? action;
  final RainStateSeverity severity;
  final bool compact;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = scheme.brightness == Brightness.dark;
    final accent = switch (severity) {
      RainStateSeverity.neutral => RainColors.mistCyan,
      RainStateSeverity.warning => RainColors.warning,
      RainStateSeverity.error => RainColors.errorCoral,
    };

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: isDark ? 0.72 : 0.84),
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            border: Border.all(color: accent.withValues(alpha: 0.24)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                blurRadius: compact ? 18 : 28,
                offset: Offset(0, compact ? 10 : 16),
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.08),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    color: accent,
                    size: iconSize ?? (compact ? 28 : 40),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.66),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: 16),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RainStreakSkeleton extends StatelessWidget {
  const RainStreakSkeleton({super.key, this.rows = 3});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rowCount = rows < 0 ? 0 : rows;
    final baseColor = scheme.brightness == Brightness.dark
        ? RainColors.mistCyan
        : RainColors.primaryLight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(rowCount, (int index) {
        final width = switch (index % 3) {
          0 => 0.72,
          1 => 0.96,
          _ => 0.48,
        };
        return FractionallySizedBox(
          widthFactor: width,
          alignment: Alignment.centerLeft,
          child: Container(
            key: ValueKey<String>('rain_streak_skeleton_row_$index'),
            height: 12,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}
