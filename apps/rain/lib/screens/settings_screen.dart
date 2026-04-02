import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain_core/rain_core.dart';

import '../providers/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);
    final notifier = ref.read(themeModeProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _SectionHeader(title: 'Profile'),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  (identity?.displayName.isNotEmpty == true
                          ? identity!.displayName[0]
                          : '?')
                      .toUpperCase(),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(identity?.displayName ?? 'Unknown'),
              subtitle: Text('@${identity?.username ?? 'unknown'}'),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showEditDisplayName(context, ref, identity),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Appearance'),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  title: const Text('Dark'),
                  leading: Icon(
                    themeMode == AppThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.circle_outlined,
                    color: themeMode == AppThemeMode.dark
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  trailing: themeMode == AppThemeMode.dark
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => notifier.setDark(),
                ),
                ListTile(
                  title: const Text('Light'),
                  leading: Icon(
                    themeMode == AppThemeMode.light
                        ? Icons.light_mode
                        : Icons.circle_outlined,
                    color: themeMode == AppThemeMode.light
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  trailing: themeMode == AppThemeMode.light
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => notifier.setLight(),
                ),
                ListTile(
                  title: const Text('System'),
                  leading: Icon(
                    themeMode == AppThemeMode.system
                        ? Icons.settings_brightness
                        : Icons.circle_outlined,
                    color: themeMode == AppThemeMode.system
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  trailing: themeMode == AppThemeMode.system
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => notifier.setSystem(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Blocked Users'),
          _BlockedUsersList(),
        ],
      ),
    );
  }

  Future<void> _showEditDisplayName(
    BuildContext context,
    WidgetRef ref,
    RainIdentity? identity,
  ) async {
    if (identity == null) return;

    final controller = TextEditingController(text: identity.displayName);

    final newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Edit Display Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Display name'),
          autofocus: true,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null &&
        newName.isNotEmpty &&
        newName != identity.displayName) {
      final repo = ref.read(identityRepositoryProvider);
      await repo.updateDisplayName(newName);
    }

    controller.dispose();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _BlockedUsersList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);

    return friends.when(
      data: (List<FriendRecord> items) {
        final blocked = items
            .where((f) => f.state == FriendState.blocked)
            .toList();

        if (blocked.isEmpty) {
          return Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('No blocked users'),
              subtitle: const Text('When you block someone, they appear here'),
            ),
          );
        }

        return Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: blocked.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final friend = blocked[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  child: Text(
                    friend.displayName.isNotEmpty
                        ? friend.displayName[0].toUpperCase()
                        : '?',
                  ),
                ),
                title: Text(friend.displayName),
                subtitle: Text('@${friend.username}'),
                trailing: TextButton(
                  onPressed: () => _confirmUnblock(context, ref, friend),
                  child: const Text('Unblock'),
                ),
              );
            },
          ),
        );
      },
      error: (Object error, StackTrace stackTrace) => Card(
        child: ListTile(
          leading: Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Could not load blocked users'),
          subtitle: Text(error.toString()),
        ),
      ),
      loading: () => const Card(
        child: ListTile(
          leading: CircularProgressIndicator(),
          title: Text('Loading...'),
        ),
      ),
    );
  }

  Future<void> _confirmUnblock(
    BuildContext context,
    WidgetRef ref,
    FriendRecord friend,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Unblock user?'),
        content: Text(
          'Unblocking @${friend.username} will allow them to send you friend requests again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(runtimeControllerProvider)?.unblockFriend(friend.username);
    }
  }
}
