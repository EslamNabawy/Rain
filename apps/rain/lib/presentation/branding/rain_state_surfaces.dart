import 'package:flutter/material.dart';

import '../performance/rain_motion_policy.dart';
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
    final neutralBorder = isDark
        ? RainTextureTokens.cardBorderDark.withValues(
            alpha: RainTextureTokens.panelBorderAlphaDark,
          )
        : RainTextureTokens.cardBorderLight.withValues(
            alpha: RainTextureTokens.panelBorderAlphaLight,
          );

    final card = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(
              alpha: isDark
                  ? RainTextureTokens.panelFillAlphaDark
                  : RainTextureTokens.panelFillAlphaLight,
            ),
            borderRadius: BorderRadius.circular(
              compact ? RainRadius.lg : RainRadius.xl,
            ),
            border: Border.all(
              color: severity == RainStateSeverity.neutral
                  ? neutralBorder
                  : accent.withValues(alpha: 0.28),
            ),
            boxShadow: compact
                ? RainShadows.panel(isDark)
                : RainShadows.raised(isDark),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? RainSpace.lg : 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    color: accent,
                    size: iconSize ?? (compact ? 28 : 40),
                  ),
                  const SizedBox(height: RainSpace.md),
                ],
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: RainSpace.sm),
                Text(
                  message,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.66),
                  ),
                  textAlign: TextAlign.center,
                ),
                if (action != null) ...<Widget>[
                  const SizedBox(height: RainSpace.lg),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: RainMotionPolicy.of(context).d(RainMotion.standard),
      curve: RainMotion.enter,
      child: card,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(scale: 0.98 + 0.02 * value, child: child),
        );
      },
    );
  }
}

enum RainSkeletonVariant { lines, messages, friends }

/// Placeholder rows shown while content loads. Pulses softly unless motion is
/// reduced, in which case it renders a fixed fill and owns no ticker.
class RainStreakSkeleton extends StatefulWidget {
  const RainStreakSkeleton({
    super.key,
    this.rows = 3,
    this.variant = RainSkeletonVariant.lines,
  });

  final int rows;
  final RainSkeletonVariant variant;

  @override
  State<RainStreakSkeleton> createState() => _RainStreakSkeletonState();
}

class _RainStreakSkeletonState extends State<RainStreakSkeleton>
    with SingleTickerProviderStateMixin {
  static const double _restAlpha = 0.12;

  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (RainMotionPolicy.of(context).reduced) {
      _controller?.dispose();
      _controller = null;
    } else {
      _controller ??= AnimationController(
        vsync: this,
        duration: RainMotion.skeletonPulse,
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = scheme.brightness == Brightness.dark
        ? RainColors.mistCyan
        : RainColors.primaryLight;
    final controller = _controller;
    if (controller == null) {
      return _content(baseColor.withValues(alpha: _restAlpha));
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? _) {
        return _content(
          baseColor.withValues(alpha: 0.08 + 0.08 * controller.value),
        );
      },
    );
  }

  Widget _content(Color fill) {
    final rowCount = widget.rows < 0 ? 0 : widget.rows;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(rowCount, (int index) {
        return switch (widget.variant) {
          RainSkeletonVariant.lines => _lineRow(index, fill),
          RainSkeletonVariant.messages => _messageRow(index, fill),
          RainSkeletonVariant.friends => _friendRow(index, fill),
        };
      }),
    );
  }

  Widget _bar(Color fill, double height, {Key? key}) {
    return Container(
      key: key,
      height: height,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(RainRadius.pill),
      ),
    );
  }

  Widget _lineRow(int index, Color fill) {
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
          color: fill,
          borderRadius: BorderRadius.circular(RainRadius.pill),
        ),
      ),
    );
  }

  Widget _messageRow(int index, Color fill) {
    final outgoing = index.isOdd;
    final width = switch (index % 3) {
      0 => 0.62,
      1 => 0.46,
      _ => 0.74,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RainSpace.xs + 2),
      child: Align(
        alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: width,
          child: Container(
            key: ValueKey<String>('rain_skeleton_message_$index'),
            height: 40,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(RainRadius.md),
            ),
          ),
        ),
      ),
    );
  }

  Widget _friendRow(int index, Color fill) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RainSpace.sm),
      child: Row(
        key: ValueKey<String>('rain_skeleton_friend_$index'),
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          ),
          const SizedBox(width: RainSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FractionallySizedBox(
                  widthFactor: index.isEven ? 0.55 : 0.4,
                  child: _bar(fill, 12),
                ),
                const SizedBox(height: RainSpace.sm),
                FractionallySizedBox(
                  widthFactor: index.isEven ? 0.8 : 0.65,
                  child: _bar(fill, 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
