part of '../../screens/home_screen.dart';

enum FriendListDisplayMode { full, compact, rail }

class _FriendsListView extends StatelessWidget {
  const _FriendsListView({
    required this.friends,
    required this.selectedPeerId,
    required this.onSelect,
    required this.onRefresh,
    required this.adaptiveProfile,
    this.desktopHeaderTitle = 'Friends',
    this.compact = false,
    this.displayMode,
    this.onExpandRail,
  });

  final AsyncValue<List<FriendRecord>> friends;
  final String? selectedPeerId;
  final ValueChanged<FriendRecord> onSelect;
  final Future<void> Function() onRefresh;
  final AdaptiveDeviceProfile adaptiveProfile;
  final String? desktopHeaderTitle;
  final bool compact;
  final FriendListDisplayMode? displayMode;
  final VoidCallback? onExpandRail;

  FriendListDisplayMode get _effectiveDisplayMode {
    if (displayMode != null) {
      return displayMode!;
    }
    return compact ? FriendListDisplayMode.compact : FriendListDisplayMode.full;
  }

  @override
  Widget build(BuildContext context) {
    final mode = _effectiveDisplayMode;
    final rail = mode == FriendListDisplayMode.rail;
    return friends.when(
      data: (List<FriendRecord> items) {
        if (items.isEmpty) {
          return _wrapRefresh(
            context,
            ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                rail ? 8 : 16,
                rail ? 24 : (compact ? 72 : 96),
                rail ? 8 : 16,
                24,
              ),
              children: <Widget>[
                if (rail)
                  const Icon(Icons.group_outlined)
                else
                  AppStateMessage(
                    icon: Icons.group_outlined,
                    title: 'No friends yet',
                    message:
                        'Find a friend to start chatting and testing the peer connection flow.',
                    iconSize: compact ? 46 : 52,
                  ),
              ],
            ),
          );
        }

        return _wrapRefresh(
          context,
          ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(vertical: rail || compact ? 6 : 0),
            itemCount: items.length,
            itemBuilder: (BuildContext context, int index) {
              final friend = items[index];
              return RepaintBoundary(
                key: ValueKey<String>('friend-tile-${friend.username}'),
                child: _FriendTile(
                  friend: friend,
                  selected: friend.username == selectedPeerId,
                  compact: mode == FriendListDisplayMode.compact,
                  rail: rail,
                  onTap: () => onSelect(friend),
                ),
              );
            },
          ),
        );
      },
      error: (Object error, StackTrace stackTrace) => AppStateMessage(
        icon: Icons.error_outline,
        title: 'Could not load friends',
        message: error.toString(),
        iconColor: Theme.of(context).colorScheme.error,
      ),
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: RainStreakSkeleton(rows: 4),
        ),
      ),
    );
  }

  Widget _wrapRefresh(BuildContext context, Widget child) {
    if (adaptiveProfile.usesPullRefresh) {
      return RefreshIndicator(onRefresh: onRefresh, child: child);
    }
    if (_effectiveDisplayMode == FriendListDisplayMode.rail) {
      return Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Tooltip(
              message: 'Expand friends',
              child: IconButton.filledTonal(
                key: const ValueKey<String>(
                  'rain-friends-desktop-rail-expand-button',
                ),
                onPressed: onExpandRail,
                icon: const Icon(Icons.keyboard_double_arrow_right),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      );
    }
    return Column(
      children: <Widget>[
        _DesktopFriendsRefreshHeader(
          title: desktopHeaderTitle,
          onRefresh: onRefresh,
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _DesktopFriendsRefreshHeader extends StatefulWidget {
  const _DesktopFriendsRefreshHeader({
    required this.title,
    required this.onRefresh,
  });

  final String? title;
  final Future<void> Function() onRefresh;

  @override
  State<_DesktopFriendsRefreshHeader> createState() =>
      _DesktopFriendsRefreshHeaderState();
}

class _DesktopFriendsRefreshHeaderState
    extends State<_DesktopFriendsRefreshHeader> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
      child: Row(
        children: <Widget>[
          if (widget.title case final title? when title.trim().isNotEmpty)
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface.withValues(alpha: 0.86),
                ),
              ),
            )
          else
            const Spacer(),
          Tooltip(
            message: 'Refresh friends',
            child: IconButton.filledTonal(
              key: const ValueKey<String>(
                'rain-friends-desktop-refresh-button',
              ),
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({
    required this.friend,
    required this.selected,
    required this.onTap,
    this.compact = false,
    this.rail = false,
  });

  final FriendRecord friend;
  final bool selected;
  final bool compact;
  final bool rail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsController = ref.read(friendsProvider.notifier);
    final connectionRequests = ref.watch(connectionRequestProvider);
    final scheme = Theme.of(context).colorScheme;

    void openProfile() {
      AppRoutes.openFriendProfile(context, friend);
    }

    Future<void> runFriendAction(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_formatUiError(error)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }

    Future<void> confirmUnfriend() async {
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: 'Unfriend?',
        message:
            'Remove @${friend.username} from your friends and close the peer connection?',
        confirmLabel: 'Unfriend',
        confirmStyle: FilledButton.styleFrom(backgroundColor: scheme.error),
      );
      if (confirmed == true) {
        await runFriendAction(
          () => friendsController.unfriend(friend.username),
        );
      }
    }

    final statusColor = _statusColorForFriend(friend);
    final statusLabel = _labelForState(friend.state);
    final avatarSize = rail
        ? 40.0
        : compact
        ? 42.0
        : 44.0;
    final inboundConnectionRequestCount = connectionRequests.incomingSurfaces
        .where(
          (surface) =>
              surface.peerId == friend.username &&
              surface.direction == ConnectionRequestDirection.inbound &&
              !surface.status.isTerminal,
        )
        .length;

    if (rail) {
      return Tooltip(
        message: friend.displayName,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Material(
            color: selected
                ? scheme.primaryContainer.withValues(
                    alpha: scheme.brightness == Brightness.dark ? 0.30 : 0.52,
                  )
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: onTap,
              onLongPress: openProfile,
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 58,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    RainAvatar(
                      name: friend.displayName,
                      size: avatarSize,
                      statusColor: statusColor,
                      gender: friend.gender?.name,
                    ),
                    if (!selected && friend.unreadCount > 0)
                      Positioned(
                        top: 8,
                        right: 10,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: scheme.secondary,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 2),
                          ),
                        ),
                      ),
                    if (inboundConnectionRequestCount > 0)
                      Positioned(
                        bottom: 8,
                        right: 10,
                        child: _ConnectionRequestFriendBadge(
                          count: inboundConnectionRequestCount,
                          compact: true,
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

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 10, vertical: 3),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.24 : 0.46,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          onLongPress: openProfile,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    RainAvatar(
                      name: friend.displayName,
                      size: avatarSize,
                      statusColor: statusColor,
                      gender: friend.gender?.name,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  friend.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                              if (!selected && friend.unreadCount > 0)
                                Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 22,
                                  ),
                                  height: 22,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.secondary,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${friend.unreadCount}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSecondary,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                ),
                              if (inboundConnectionRequestCount >
                                  0) ...<Widget>[
                                const SizedBox(width: 6),
                                _ConnectionRequestFriendBadge(
                                  count: inboundConnectionRequestCount,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '@${friend.username}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurface.withValues(
                                          alpha: 0.62,
                                        ),
                                      ),
                                ),
                              ),
                              if (compact &&
                                  friend.state !=
                                      FriendState.friend) ...<Widget>[
                                const SizedBox(width: 8),
                                RainMiniStatusChip(
                                  label: statusLabel,
                                  color: statusColor,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (friend.state != FriendState.pendingIncoming &&
                        friend.state != FriendState.blocked &&
                        friend.state != FriendState.blockedByPeer) ...<Widget>[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        tooltip: 'Open peer actions',
                        iconSize: compact ? 20 : 24,
                        onSelected: (String value) async {
                          if (value == 'unfriend') {
                            await confirmUnfriend();
                          } else if (value == 'block') {
                            await runFriendAction(
                              () => friendsController.block(friend.username),
                            );
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                              if (friend.state == FriendState.friend)
                                const PopupMenuItem<String>(
                                  value: 'unfriend',
                                  child: Row(
                                    children: <Widget>[
                                      Icon(Icons.person_remove_outlined),
                                      SizedBox(width: 12),
                                      Text('Unfriend'),
                                    ],
                                  ),
                                ),
                              PopupMenuItem<String>(
                                value: 'block',
                                child: Row(
                                  children: <Widget>[
                                    Icon(
                                      Icons.block,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Block'),
                                  ],
                                ),
                              ),
                            ],
                      ),
                    ],
                  ],
                ),
                if (!compact && friend.state != FriendState.friend) ...<Widget>[
                  const SizedBox(height: 8),
                  RainMiniStatusChip(label: statusLabel, color: statusColor),
                ],
                if (friend.state == FriendState.pendingIncoming) ...<Widget>[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonal(
                        onPressed: () =>
                            friendsController.accept(friend.username),
                        child: const Text('Accept'),
                      ),
                      TextButton(
                        onPressed: () =>
                            friendsController.reject(friend.username),
                        child: const Text('Reject'),
                      ),
                      TextButton(
                        onPressed: () =>
                            friendsController.block(friend.username),
                        child: const Text('Block'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusColorForFriend(FriendRecord friend) {
    return switch (friend.state) {
      FriendState.friend =>
        friend.isOnline ? const Color(0xFF2DD4A3) : const Color(0xFF52646D),
      FriendState.pendingIncoming => const Color(0xFF7DD3FC),
      FriendState.pendingOutgoing => const Color(0xFFFBBF24),
      FriendState.blocked => const Color(0xFFFF6B6B),
      FriendState.blockedByPeer => const Color(0xFFFF6B6B),
    };
  }

  static String _labelForState(FriendState state) => switch (state) {
    FriendState.pendingOutgoing => 'Request sent',
    FriendState.pendingIncoming => 'Incoming',
    FriendState.friend => 'Friend',
    FriendState.blocked => 'Blocked',
    FriendState.blockedByPeer => 'Blocked you',
  };
}

class _ConnectionRequestFriendBadge extends StatelessWidget {
  const _ConnectionRequestFriendBadge({
    required this.count,
    this.compact = false,
  });

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count > 1 ? '$count' : '';
    return Tooltip(
      message: count == 1
          ? 'Pending connection request'
          : '$count pending connection requests',
      child: Semantics(
        label: count == 1
            ? 'Pending connection request'
            : '$count pending connection requests',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RainColors.mistCyan,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: scheme.surface.withValues(alpha: 0.88),
              width: 2,
            ),
          ),
          child: SizedBox(
            width: compact ? 16 : (label.isEmpty ? 18 : 24),
            height: compact ? 16 : 18,
            child: Center(
              child: label.isEmpty
                  ? Icon(
                      Icons.hub_outlined,
                      size: compact ? 10 : 11,
                      color: RainColors.backgroundDark,
                    )
                  : Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: RainColors.backgroundDark,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
