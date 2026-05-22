part of '../../screens/home_screen.dart';

class _MobileLinkStatusBar extends StatelessWidget {
  const _MobileLinkStatusBar({
    required this.status,
    required this.diagnostics,
    required this.canConnectNow,
    required this.canDisconnectNow,
    required this.onConnect,
    required this.onDisconnect,
    required this.onTap,
    required this.enabled,
  });

  final _ConnectionStatus status;
  final ConnectionDiagnostics diagnostics;
  final bool canConnectNow;
  final bool canDisconnectNow;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final action = status.isConnected ? onDisconnect : onConnect;
    final actionEnabled = status.isConnected ? canDisconnectNow : canConnectNow;
    final actionIcon = status.isConnected ? Icons.link_off : Icons.hub_outlined;
    final actionLabel = status.isConnected ? 'Disconnect' : 'Connect';
    final detail = _mobileLinkDetail(diagnostics, status);

    return Semantics(
      button: enabled,
      label: 'Connection ${status.label}. $detail',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                status.color.withValues(alpha: 0.08),
                scheme.surfaceContainerHighest.withValues(alpha: 0.62),
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: status.color.withValues(alpha: 0.28)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: <Widget>[
                  _MobileLinkGlyph(status: status),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          status.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: status.color,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.66),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MobileLinkMeter(color: status.color, level: _linkLevel()),
                  const SizedBox(width: 8),
                  SizedBox.square(
                    dimension: 40,
                    child: IconButton.filledTonal(
                      tooltip: actionLabel,
                      onPressed: actionEnabled ? action : null,
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: WidgetStatePropertyAll(Size.square(40)),
                        fixedSize: WidgetStatePropertyAll(Size.square(40)),
                        padding: WidgetStatePropertyAll(EdgeInsets.zero),
                      ),
                      icon: Icon(actionIcon, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _linkLevel() {
    if (status.isBusy) {
      return 2;
    }
    return switch (diagnostics.route.kind) {
      PeerRouteKind.direct => 4,
      PeerRouteKind.relay => 3,
      PeerRouteKind.unknown => status.isConnected ? 2 : 1,
    };
  }
}

class _MobileLinkGlyph extends StatelessWidget {
  const _MobileLinkGlyph({required this.status});

  final _ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: status.isBusy
              ? SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: status.color,
                  ),
                )
              : Icon(status.icon, size: 18, color: status.color),
        ),
      ),
    );
  }
}

class _MobileLinkMeter extends StatelessWidget {
  const _MobileLinkMeter({required this.color, required this.level});

  final Color color;
  final int level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final boundedLevel = level.clamp(0, 4).toInt();

    return SizedBox(
      width: 30,
      height: 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(4, (int index) {
          final active = index < boundedLevel;
          return Container(
            width: 4,
            height: 8 + (index * 4),
            margin: EdgeInsets.only(left: index == 0 ? 0 : 4),
            decoration: BoxDecoration(
              color: active
                  ? color
                  : scheme.outlineVariant.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    );
  }
}

class _LinkStat {
  const _LinkStat({required this.label, required this.value});

  final String label;
  final String value;
}

class _LinkStatGrid extends StatelessWidget {
  const _LinkStatGrid({required this.stats});

  final List<_LinkStat> stats;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final stat in stats)
          _LinkStatCard(label: stat.label, value: stat.value),
      ],
    );
  }
}

class _LinkStatCard extends StatelessWidget {
  const _LinkStatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 118,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.38),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
