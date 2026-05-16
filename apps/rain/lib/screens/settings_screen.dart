import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rain_core/rain_core.dart';

import '../navigation/app_routes.dart';
import '../providers/app_providers.dart';
import '../widgets/app_components.dart';
import '../widgets/app_dialogs.dart';

String _formatSettingsError(Object error) {
  final raw = error.toString().trim();
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }
  }
  return raw;
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider).valueOrNull;
    final runtime = ref.watch(runtimeControllerProvider).valueOrNull;
    final themeMode = ref.watch(themeModeProvider);
    final themeController = ref.read(themeModeProvider.notifier);

    return AppPageFrame(
      title: 'Settings',
      icon: Icons.tune,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const AppSectionTitle(title: 'Profile'),
          AppSectionCard(
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
              subtitle: Text(
                [
                  '@${identity?.username ?? 'unknown'}',
                  _genderLabel(identity?.gender),
                ].join(' | '),
              ),
              trailing: PopupMenuButton<_ProfileAction>(
                onSelected: (value) {
                  switch (value) {
                    case _ProfileAction.editDisplayName:
                      _showEditDisplayName(context, ref, identity);
                      break;
                    case _ProfileAction.editGender:
                      _showEditGender(context, ref, identity);
                      break;
                  }
                },
                itemBuilder: (BuildContext context) =>
                    const <PopupMenuEntry<_ProfileAction>>[
                      PopupMenuItem<_ProfileAction>(
                        value: _ProfileAction.editDisplayName,
                        child: Text('Edit display name'),
                      ),
                      PopupMenuItem<_ProfileAction>(
                        value: _ProfileAction.editGender,
                        child: Text('Edit gender'),
                      ),
                    ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const AppSectionTitle(title: 'Session'),
          AppSectionCard(
            child: ListTile(
              leading: Icon(
                Icons.logout,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Log out'),
              subtitle: const Text('Clear Rain session on this device'),
              onTap: runtime == null
                  ? null
                  : () => _confirmLogOut(context, ref),
            ),
          ),
          const SizedBox(height: 24),
          const AppSectionTitle(title: 'Appearance'),
          AppSectionCard(
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
                  onTap: () => themeController.setDark(),
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
                  onTap: () => themeController.setLight(),
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
                  onTap: () => themeController.setSystem(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const AppSectionTitle(title: 'Blocked Users'),
          const _BlockedUsersList(),
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

    final newName = await showAppTextInputDialog(
      context: context,
      title: 'Edit display name',
      confirmLabel: 'Save',
      initialValue: identity.displayName,
      labelText: 'Display name',
      maxLength: InputValidator.displayNameMaxLength,
      textCapitalization: TextCapitalization.words,
    );

    if (newName != null &&
        newName.isNotEmpty &&
        newName != identity.displayName) {
      await ref.read(identityProvider.notifier).updateDisplayName(newName);
    }
  }

  Future<void> _confirmLogOut(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    final shouldLogOut = await showAppConfirmDialog(
      context: context,
      title: 'Log out',
      message:
          'This will sign you out and clear the local Rain session on this device.',
      confirmLabel: 'Log out',
    );

    if (shouldLogOut != true) {
      return;
    }

    try {
      await ref.read(runtimeControllerProvider.notifier).logOut();
      if (!context.mounted) {
        return;
      }
      context.goNamed(AppRoutes.home);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not log out: ${_formatSettingsError(error)}'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _showEditGender(
    BuildContext context,
    WidgetRef ref,
    RainIdentity? identity,
  ) async {
    if (identity == null) return;

    final selected = await showDialog<RainGender>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit gender'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(
                  identity.gender == RainGender.male
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: const Text('Male'),
                onTap: () => Navigator.of(context).pop(RainGender.male),
              ),
              ListTile(
                leading: Icon(
                  identity.gender == RainGender.female
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                ),
                title: const Text('Female'),
                onTap: () => Navigator.of(context).pop(RainGender.female),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (selected == null || selected == identity.gender) {
      return;
    }

    await ref.read(identityProvider.notifier).updateGender(selected);
  }

  String _genderLabel(RainGender? gender) => switch (gender) {
    RainGender.male => 'Male',
    RainGender.female => 'Female',
    null => 'Gender not set',
  };
}

enum _ProfileAction { editDisplayName, editGender }

class _BlockedUsersList extends ConsumerWidget {
  const _BlockedUsersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friends = ref.watch(friendsProvider);

    return friends.when(
      data: (List<FriendRecord> items) {
        final blocked = items
            .where((f) => f.state == FriendState.blocked)
            .toList();

        if (blocked.isEmpty) {
          return AppSectionCard(
            child: ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('No blocked users'),
              subtitle: const Text('When you block someone, they appear here'),
            ),
          );
        }

        return AppSectionCard(
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
      error: (Object error, StackTrace stackTrace) => AppSectionCard(
        child: ListTile(
          leading: Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Could not load blocked users'),
          subtitle: Text(error.toString()),
        ),
      ),
      loading: () => const AppSectionCard(
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
    final confirmed = await showAppConfirmDialog(
      context: context,
      title: 'Unblock user?',
      message:
          'Unblocking @${friend.username} will allow them to send you friend requests again.',
      confirmLabel: 'Unblock',
    );

    if (confirmed == true) {
      await ref.read(friendsProvider.notifier).unblock(friend.username);
    }
  }
}
