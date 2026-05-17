import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/state/app_providers.dart';
import 'package:rain/presentation/widgets/app_components.dart';
import 'package:rain/presentation/widgets/app_dialogs.dart';
import 'package:rain/presentation/widgets/rain_command_widgets.dart';

class FriendProfileScreen extends ConsumerWidget {
  const FriendProfileScreen({
    super.key,
    required this.username,
    this.initialFriend,
  });

  final String username;
  final FriendRecord? initialFriend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider).valueOrNull;
    FriendRecord? currentFriend = initialFriend;
    for (final friend in friends ?? const <FriendRecord>[]) {
      if (friend.username == username) {
        currentFriend = friend;
        break;
      }
    }

    if (currentFriend == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Friend Profile')),
        body: const Center(
          child: AppStateMessage(
            icon: Icons.person_off_outlined,
            title: 'Friend not found',
            message: 'This profile is not available right now.',
          ),
        ),
      );
    }

    final friend = currentFriend;
    final isOnline = friend.isOnline;

    return Scaffold(
      appBar: AppBar(title: const Text('Friend Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Center(
            child: Column(
              children: <Widget>[
                RainAvatar(
                  name: friend.displayName,
                  size: 96,
                  statusColor: isOnline ? const Color(0xFF2DD4A3) : null,
                  gender: friend.gender?.name,
                ),
                const SizedBox(height: 16),
                Text(
                  friend.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '@${friend.username}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline
                            ? const Color(0xFF2DD4A3)
                            : const Color(0xFF52646D),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isOnline ? 'Online' : 'Offline',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _InfoSection(
            title: 'Status',
            children: <Widget>[
              _InfoTile(
                label: 'Relationship',
                value: _friendStateLabel(friend.state),
              ),
              if (friend.addedAt > 0)
                _InfoTile(
                  label: 'Friends since',
                  value: _formatDate(friend.addedAt),
                ),
              if (friend.lastOnlineAt != null && !isOnline)
                _InfoTile(
                  label: 'Last online',
                  value: _formatDate(friend.lastOnlineAt!),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (friend.state == FriendState.friend) ...<Widget>[
            FilledButton.icon(
              onPressed: () => _confirmUnfriend(context, ref, friend),
              icon: const Icon(Icons.person_remove),
              label: const Text('Unfriend'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _confirmBlock(context, ref, friend),
              icon: const Icon(Icons.block),
              label: const Text('Block'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          if (friend.state == FriendState.pendingIncoming) ...<Widget>[
            FilledButton.icon(
              onPressed: () async {
                await ref
                    .read(friendsProvider.notifier)
                    .accept(friend.username);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.check),
              label: const Text('Accept Request'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(friendsProvider.notifier)
                    .reject(friend.username);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.close),
              label: const Text('Reject Request'),
            ),
          ],
          if (friend.state == FriendState.pendingOutgoing) ...<Widget>[
            Card(
              child: ListTile(
                leading: const Icon(Icons.hourglass_top),
                title: const Text('Request pending'),
                subtitle: const Text('Waiting for them to accept'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await ref
                    .read(friendsProvider.notifier)
                    .reject(friend.username);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel Request'),
            ),
          ],
          if (friend.state == FriendState.blocked) ...<Widget>[
            FilledButton.icon(
              onPressed: () => _confirmUnblock(context, ref, friend),
              icon: const Icon(Icons.check),
              label: const Text('Unblock'),
            ),
          ],
          if (friend.state == FriendState.blockedByPeer) ...<Widget>[
            const Card(
              child: ListTile(
                leading: Icon(Icons.block_outlined),
                title: Text('Blocked by peer'),
                subtitle: Text('They must unblock you before chat can resume'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _friendStateLabel(FriendState state) => switch (state) {
    FriendState.pendingOutgoing => 'Request sent',
    FriendState.pendingIncoming => 'Incoming request',
    FriendState.friend => 'Friend',
    FriendState.blocked => 'Blocked',
    FriendState.blockedByPeer => 'Blocked you',
  };

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _confirmUnfriend(
    BuildContext context,
    WidgetRef ref,
    FriendRecord friend,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Unfriend?',
      message:
          'Remove @${friend.username} from your friends and close the peer connection?',
      confirmLabel: 'Unfriend',
      confirmStyle: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );

    if (confirmed == true) {
      await ref.read(friendsProvider.notifier).unfriend(friend.username);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _confirmBlock(
    BuildContext context,
    WidgetRef ref,
    FriendRecord friend,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Block user?',
      message:
          'Blocking @${friend.username} will remove them from your friends and prevent them from sending you messages or friend requests.',
      confirmLabel: 'Block',
      confirmStyle: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );

    if (confirmed == true) {
      await ref.read(friendsProvider.notifier).block(friend.username);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _confirmUnblock(
    BuildContext context,
    WidgetRef ref,
    FriendRecord friend,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Unblock user?',
      message:
          'Unblocking @${friend.username} will allow them to send you friend requests again.',
      confirmLabel: 'Unblock',
    );

    if (confirmed == true) {
      await ref.read(friendsProvider.notifier).unblock(friend.username);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppSectionTitle(title: title),
        AppSectionCard(child: Column(children: children)),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
