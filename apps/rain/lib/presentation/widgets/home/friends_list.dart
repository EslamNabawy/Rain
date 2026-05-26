part of '../../screens/home_screen.dart';

class _FriendsListView extends StatelessWidget {
  const _FriendsListView({
    required this.friends,
    required this.selectedPeerId,
    required this.onSelect,
    required this.onRefresh,
    this.compact = false,
  });

  final AsyncValue<List<FriendRecord>> friends;
  final String? selectedPeerId;
  final ValueChanged<FriendRecord> onSelect;
  final Future<void> Function() onRefresh;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return friends.when(
      data: (List<FriendRecord> items) {
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, compact ? 72 : 96, 16, 24),
              children: <Widget>[
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

        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(vertical: compact ? 6 : 0),
            itemCount: items.length,
            itemBuilder: (BuildContext context, int index) {
              final friend = items[index];
              return RepaintBoundary(
                key: ValueKey<String>('friend-tile-${friend.username}'),
                child: _FriendTile(
                  friend: friend,
                  selected: friend.username == selectedPeerId,
                  compact: compact,
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
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({
    required this.friend,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final FriendRecord friend;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsController = ref.read(friendsProvider.notifier);
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
    final avatarSize = compact ? 42.0 : 44.0;

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
                              if (friend.unreadCount > 0)
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
