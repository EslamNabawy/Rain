import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/presentation/navigation/app_routes.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/infrastructure/services/crash_diagnostics_service.dart';
import 'package:rain/presentation/screens/splash_screen.dart';
import 'package:rain/presentation/widgets/app_components.dart';
import 'package:rain/presentation/widgets/app_dialogs.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';

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

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loggingOut = false;
  bool _exportingDiagnostics = false;

  @override
  Widget build(BuildContext context) {
    if (_loggingOut) {
      return const RainSplashScreen();
    }

    final identity = ref.watch(identityProvider).value;
    final runtime = ref.watch(runtimeControllerProvider).value;
    final themeMode = ref.watch(themeModeProvider);
    final themeController = ref.read(themeModeProvider.notifier);
    final lastCrash = ref.watch(lastCrashDiagnosticsProvider);

    return AppPageFrame(
      title: 'Settings',
      icon: Icons.tune,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const AppSectionTitle(title: 'Profile'),
          AppSectionCard(
            child: ListTile(
              leading: RainAvatar(
                name: identity?.displayName ?? '',
                size: 44,
                gender: identity?.gender?.name,
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
              onTap: runtime == null ? null : () => _confirmLogOut(context),
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
          const AppSectionTitle(title: 'Diagnostics'),
          AppSectionCard(
            child: Column(
              children: <Widget>[
                lastCrash.when(
                  data: (record) => _LastCrashTile(record: record),
                  error: (Object error, StackTrace stackTrace) => ListTile(
                    leading: Icon(
                      Icons.error_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Diagnostics unavailable'),
                    subtitle: Text(_formatSettingsError(error)),
                  ),
                  loading: () => const ListTile(
                    leading: SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    title: Text('Checking diagnostics'),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Export diagnostics'),
                  subtitle: const Text('Save the latest crash and app log'),
                  enabled: !_exportingDiagnostics,
                  trailing: _exportingDiagnostics
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _exportingDiagnostics
                      ? null
                      : () => _exportDiagnostics(context),
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

  Future<void> _confirmLogOut(BuildContext context) async {
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

    setState(() => _loggingOut = true);
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
      setState(() => _loggingOut = false);
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

  Future<void> _exportDiagnostics(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _exportingDiagnostics = true);
    try {
      final result = await ref
          .read(crashDiagnosticsServiceProvider)
          .exportDiagnostics();
      if (!context.mounted) {
        return;
      }
      if (result.saved) {
        messenger.showSnackBar(
          SnackBar(content: Text('Diagnostics exported to ${result.path}')),
        );
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not export diagnostics: ${_formatSettingsError(error)}',
          ),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingDiagnostics = false);
      }
    }
  }
}

enum _ProfileAction { editDisplayName, editGender }

class _LastCrashTile extends StatelessWidget {
  const _LastCrashTile({required this.record});

  final CrashDiagnosticsRecord? record;

  @override
  Widget build(BuildContext context) {
    final crash = record;
    if (crash == null) {
      return const ListTile(
        leading: Icon(Icons.check_circle_outline),
        title: Text('No crash recorded'),
        subtitle: Text('Diagnostics will capture the next app error'),
      );
    }

    return ListTile(
      leading: Icon(
        crash.fatal ? Icons.report_gmailerrorred : Icons.bug_report_outlined,
        color: crash.fatal ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text(crash.fatal ? 'Last fatal error' : 'Last Flutter error'),
      subtitle: Text(
        '${_formatCrashTime(crash.recordedAt)} | ${crash.source} | '
        '${_compactCrashError(crash.error)}',
      ),
    );
  }

  static String _formatCrashTime(DateTime value) {
    final local = value.toLocal();
    String two(int input) => input.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _compactCrashError(String error) {
    final normalized = error.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 96) {
      return normalized;
    }
    return '${normalized.substring(0, 93)}...';
  }
}

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
          child: Column(
            children: <Widget>[
              for (var index = 0; index < blocked.length; index++) ...<Widget>[
                if (index > 0) const Divider(height: 1),
                _BlockedUserTile(friend: blocked[index]),
              ],
            ],
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
}

class _BlockedUserTile extends ConsumerWidget {
  const _BlockedUserTile({required this.friend});

  final FriendRecord friend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: RainAvatar(
        name: friend.displayName,
        size: 40,
        gender: friend.gender?.name,
      ),
      title: Text(friend.displayName),
      subtitle: Text('@${friend.username}'),
      trailing: TextButton(
        onPressed: () => _confirmUnblock(context, ref),
        child: const Text('Unblock'),
      ),
    );
  }

  Future<void> _confirmUnblock(BuildContext context, WidgetRef ref) async {
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
