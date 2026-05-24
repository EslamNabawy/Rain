part of '../../screens/home_screen.dart';

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({required this.identity, required this.isCompact});

  final RainIdentity? identity;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = identity?.displayName ?? 'Rain';
    final handle = identity == null ? '@rain' : '@${identity!.username}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 12 : 18,
        isCompact ? 10 : 14,
        isCompact ? 10 : 18,
        isCompact ? 10 : 14,
      ),
      child: RainStreakSurface(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          key: const ValueKey<String>('rain-shell-header-surface'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(
              alpha: scheme.brightness == Brightness.dark ? 0.58 : 0.76,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: <Widget>[
              const _RainHeaderIcon(size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      TextSpan(
                        text: '  |  $handle',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RainHeaderIcon extends StatelessWidget {
  const _RainHeaderIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RainStreakSurface(
      borderRadius: BorderRadius.circular(size * 0.30),
      child: Container(
        width: size,
        height: size,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.30),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.22),
          child: RainPeerCoreMark(size: size * 0.72, useTinyVariant: size < 44),
        ),
      ),
    );
  }
}
