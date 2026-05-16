import 'package:flutter/material.dart';

class RainAvatar extends StatelessWidget {
  const RainAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.statusColor,
  });

  final String name;
  final double size;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(size * 0.34),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.42),
                ),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          if (statusColor != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.25,
                height: size * 0.25,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class RainMiniStatusChip extends StatelessWidget {
  const RainMiniStatusChip({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RainLiveLinkBar extends StatelessWidget {
  const RainLiveLinkBar({
    super.key,
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
    required this.strength,
    this.isBusy = false,
    this.onTap,
  });

  final String label;
  final String detail;
  final Color color;
  final IconData icon;
  final int strength;
  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final boundedStrength = strength.clamp(0, 4).toInt();

    return Semantics(
      button: onTap != null,
      label: 'Live Link Bar. $label. $detail',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  Container(
                    constraints: const BoxConstraints(maxWidth: 142),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (isBusy)
                          SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: color,
                            ),
                          )
                        else
                          Icon(icon, size: 15, color: color),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List<Widget>.generate(4, (int index) {
                      final active = index < boundedStrength;
                      return Container(
                        key: ValueKey<String>(
                          'rain-link-meter-${active ? 'on' : 'off'}-$index',
                        ),
                        width: 5,
                        height: 18,
                        margin: EdgeInsets.only(left: index == 0 ? 0 : 4),
                        decoration: BoxDecoration(
                          color: active
                              ? color
                              : scheme.outlineVariant.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RainMessageDayDivider extends StatelessWidget {
  const RainMessageDayDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Divider(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.58),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: scheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class RainMessageBubble extends StatelessWidget {
  const RainMessageBubble({
    super.key,
    required this.text,
    required this.timeLabel,
    required this.isOutgoing,
    required this.startsCluster,
    required this.endsCluster,
    required this.maxWidth,
    this.deliveryLabel,
    this.deliveryColor,
    this.onRetry,
    this.onOpenActions,
  });

  final String text;
  final String timeLabel;
  final bool isOutgoing;
  final bool startsCluster;
  final bool endsCluster;
  final double maxWidth;
  final String? deliveryLabel;
  final Color? deliveryColor;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final bubbleColor = isOutgoing
        ? (isDark ? const Color(0xFF1D7E8E) : scheme.primaryContainer)
        : (isDark ? const Color(0xFF18262E) : scheme.surfaceContainerHighest);
    final textColor = isOutgoing
        ? (isDark ? Colors.white : scheme.onPrimaryContainer)
        : scheme.onSurface;
    final metadataColor = textColor.withValues(alpha: 0.72);
    final tailRadius = const Radius.circular(6);
    final roundRadius = const Radius.circular(20);
    final radius = BorderRadius.only(
      topLeft: roundRadius,
      topRight: roundRadius,
      bottomLeft: isOutgoing || !endsCluster ? roundRadius : tailRadius,
      bottomRight: isOutgoing && endsCluster ? tailRadius : roundRadius,
    );

    return GestureDetector(
      onLongPress: onOpenActions,
      onSecondaryTap: onOpenActions,
      child: Align(
        alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            margin: EdgeInsets.only(
              top: startsCluster ? 8 : 2,
              bottom: endsCluster ? 8 : 1,
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 9),
            decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    height: 1.28,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      timeLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: metadataColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isOutgoing && deliveryLabel != null) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: deliveryColor ?? metadataColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        deliveryLabel!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: deliveryColor ?? metadataColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (onOpenActions != null) ...<Widget>[
                      const SizedBox(width: 4),
                      SizedBox.square(
                        dimension: 28,
                        child: IconButton(
                          tooltip: 'Message actions',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: onOpenActions,
                          icon: Icon(
                            Icons.more_horiz,
                            size: 17,
                            color: metadataColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (onRetry != null) ...<Widget>[
                  const SizedBox(height: 7),
                  TextButton.icon(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: deliveryColor ?? textColor,
                    ),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RainComposerCommandStrip extends StatelessWidget {
  const RainComposerCommandStrip({
    super.key,
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
    this.isBusy = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String label;
  final String detail;
  final Color color;
  final IconData icon;
  final bool isBusy;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final compact = constraints.maxWidth < 360;

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.46),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isBusy
                      ? SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        )
                      : Icon(icon, color: color, size: 16),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Row(
                  children: <Widget>[
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(width: 8),
                compact
                    ? IconButton(
                        tooltip: actionLabel,
                        visualDensity: VisualDensity.compact,
                        onPressed: onAction,
                        icon: Icon(actionIcon ?? Icons.tune, size: 18),
                      )
                    : TextButton.icon(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: color,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        icon: Icon(actionIcon ?? Icons.tune, size: 16),
                        label: Text(actionLabel!),
                      ),
              ],
            ],
          ),
        );
      },
    );
  }
}
