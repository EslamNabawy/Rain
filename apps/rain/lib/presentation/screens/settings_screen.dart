import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:rain/application/audio/sound_event_router.dart';
import 'package:rain/application/runtime/connection_request_state.dart';
import 'package:rain/presentation/navigation/app_routes.dart';
import 'package:rain/application/runtime/media_device_settings.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/application/state/sound_event_providers.dart';
import 'package:rain/infrastructure/services/crash_diagnostics_service.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/branding/rain_state_surfaces.dart';
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
  bool _testingMicrophone = false;
  bool _microphoneTestFailed = false;
  String? _microphoneTestMessage;

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
    final microphones = ref.watch(microphoneSelectionProvider);
    final cameras = ref.watch(videoInputCapabilityProvider);
    final audioSettings = ref.watch(voiceAudioSettingsProvider);
    final callProcessingSettings = ref.watch(callProcessingSettingsProvider);
    final audioOutputCapabilities = ref.watch(audioOutputCapabilityProvider);
    final updateStatus = ref.watch(forceUpdateProvider);
    final connectionRequests = ref.watch(connectionRequestProvider);
    final connectionRequestBackendMode = ref
        .watch(appEnvironmentProvider)
        .connectionRequestBackendMode;
    final connectionRequestSettings = ref.watch(
      connectionRequestSettingsProvider,
    );
    final outputCapabilities =
        audioOutputCapabilities.value ??
        const AudioOutputCapabilityState(devices: []);

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
          const AppSectionTitle(title: 'Call Audio'),
          AppSectionCard(
            child: Column(
              children: <Widget>[
                microphones.when(
                  data: (state) => RainMicrophoneSelector(
                    state: state,
                    isBusy: false,
                    onRefresh: () => _refreshMicrophones(ref),
                    onSelected: (String? deviceId) =>
                        _selectMicrophone(context, ref, deviceId),
                  ),
                  error: (Object error, StackTrace stackTrace) => ListTile(
                    leading: Icon(
                      Icons.mic_off,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Microphones unavailable'),
                    subtitle: Text(_formatSettingsError(error)),
                    trailing: IconButton(
                      tooltip: 'Refresh microphones',
                      onPressed: () => _refreshMicrophones(ref),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  loading: () => RainMicrophoneSelector(
                    state: const MicrophoneSelectionState(devices: []),
                    isBusy: true,
                    onRefresh: () {},
                    onSelected: (_) {},
                  ),
                ),
                const Divider(height: 1),
                _MicrophoneTestTile(
                  isTesting: _testingMicrophone,
                  failed: _microphoneTestFailed,
                  message: _microphoneTestMessage,
                  onTest: _testingMicrophone
                      ? null
                      : () => _testMicrophone(context, ref),
                ),
                const Divider(height: 1),
                callProcessingSettings.when(
                  data: (settings) => _ClearVoiceTile(
                    enabled: settings.clearVoiceEnabled,
                    isBusy: false,
                    onChanged: (bool enabled) =>
                        _setClearVoiceEnabled(context, ref, enabled),
                  ),
                  error: (Object error, StackTrace stackTrace) => ListTile(
                    leading: Icon(
                      Icons.noise_control_off,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Clear voice unavailable'),
                    subtitle: Text(_formatSettingsError(error)),
                    trailing: IconButton(
                      tooltip: 'Retry clear voice',
                      onPressed: () =>
                          ref.invalidate(callProcessingSettingsProvider),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  loading: () => _ClearVoiceTile(
                    enabled: true,
                    isBusy: true,
                    onChanged: (_) {},
                  ),
                ),
                const Divider(height: 1),
                audioSettings.when(
                  data: (settings) => _VoiceAudioSettingsControls(
                    settings: settings,
                    outputCapabilities: outputCapabilities,
                    isBusy: false,
                    onSoundEffectsEnabledChanged: (bool enabled) =>
                        _setSoundEffectsEnabled(context, ref, enabled),
                    onSoundEffectsVolumeChanged: (double volume) =>
                        _setSoundEffectsVolume(context, ref, volume),
                    onCallSoundsEnabledChanged: (bool enabled) =>
                        _setCallSoundsEnabled(context, ref, enabled),
                    onReduceSoundsDuringCallChanged: (bool enabled) =>
                        _setReduceSoundsDuringCall(context, ref, enabled),
                    onOutputPreferenceChanged:
                        (CallAudioOutputPreference preference) =>
                            _setDefaultOutputPreference(
                              context,
                              ref,
                              preference,
                            ),
                  ),
                  error: (Object error, StackTrace stackTrace) => ListTile(
                    leading: Icon(
                      Icons.volume_off,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Call audio settings unavailable'),
                    subtitle: Text(_formatSettingsError(error)),
                    trailing: IconButton(
                      tooltip: 'Retry audio settings',
                      onPressed: () =>
                          ref.invalidate(voiceAudioSettingsProvider),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  loading: () => _VoiceAudioSettingsControls(
                    settings: const AppAudioSettings(),
                    outputCapabilities: outputCapabilities,
                    isBusy: true,
                    onSoundEffectsEnabledChanged: (_) {},
                    onSoundEffectsVolumeChanged: (_) {},
                    onCallSoundsEnabledChanged: (_) {},
                    onReduceSoundsDuringCallChanged: (_) {},
                    onOutputPreferenceChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const AppSectionTitle(title: 'Call Video'),
          AppSectionCard(
            child: Column(
              children: <Widget>[
                cameras.when(
                  data: (state) => RainCameraSelector(
                    state: state,
                    isBusy: false,
                    onRefresh: () => _refreshCameras(ref),
                    onSelected: (String? deviceId) =>
                        _selectCamera(context, ref, deviceId),
                  ),
                  error: (Object error, StackTrace stackTrace) => ListTile(
                    leading: Icon(
                      Icons.videocam_off,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Cameras unavailable'),
                    subtitle: Text(_formatSettingsError(error)),
                    trailing: IconButton(
                      tooltip: 'Refresh cameras',
                      onPressed: () => _refreshCameras(ref),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  loading: () => RainCameraSelector(
                    state: const VideoInputCapabilityState(devices: []),
                    isBusy: true,
                    onRefresh: () {},
                    onSelected: (_) {},
                  ),
                ),
                const Divider(height: 1),
                callProcessingSettings.when(
                  data: (settings) => _AutoVideoOptimizeTile(
                    enabled: settings.autoVideoOptimizeEnabled,
                    isBusy: false,
                    onChanged: (bool enabled) =>
                        _setAutoVideoOptimizeEnabled(context, ref, enabled),
                  ),
                  error: (Object error, StackTrace stackTrace) => ListTile(
                    leading: Icon(
                      Icons.speed,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: const Text('Video optimization unavailable'),
                    subtitle: Text(_formatSettingsError(error)),
                    trailing: IconButton(
                      tooltip: 'Retry video optimization',
                      onPressed: () =>
                          ref.invalidate(callProcessingSettingsProvider),
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                  loading: () => _AutoVideoOptimizeTile(
                    enabled: true,
                    isBusy: true,
                    onChanged: (_) {},
                  ),
                ),
              ],
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
          const AppSectionTitle(title: 'Connection Requests'),
          _ConnectionRequestSettingsSection(
            state: connectionRequests,
            settings: connectionRequestSettings,
            audioSettings: audioSettings,
            backendMode: connectionRequestBackendMode,
            onNotificationsEnabledChanged: (bool enabled) =>
                _setConnectionRequestNotificationsEnabled(
                  context,
                  ref,
                  enabled,
                ),
            onSoundEnabledChanged: (bool enabled) =>
                _setConnectionRequestSoundsEnabled(context, ref, enabled),
            onShowMinimizedChanged: (bool enabled) =>
                _setShowConnectionRequestNotificationsWhenMinimized(
                  context,
                  ref,
                  enabled,
                ),
            onUnmute: (String peerId) =>
                _unmuteConnectionRequestSender(context, ref, peerId),
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
                if (kDebugMode) ...<Widget>[
                  const Divider(height: 1),
                  _SoundDiagnosticsTile(
                    diagnostics: ref
                        .watch(soundEventRouterProvider)
                        .diagnostics,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const AppSectionTitle(title: 'About Rain'),
          AppSectionCard(
            child: _AboutRainSection(
              updateStatus: updateStatus,
              onCheckForUpdates: () {
                _checkForUpdates(context);
              },
              onOpenReleasePage: () {
                _openReleasePage(context);
              },
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

  void _refreshMicrophones(WidgetRef ref) {
    ref.read(microphoneSelectionProvider.notifier).refresh();
  }

  void _refreshCameras(WidgetRef ref) {
    ref.read(videoInputCapabilityProvider.notifier).refresh();
  }

  Future<void> _selectMicrophone(
    BuildContext context,
    WidgetRef ref,
    String? deviceId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(microphoneSelectionProvider.notifier)
          .selectMicrophone(deviceId);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not update microphone: ${_formatSettingsError(error)}',
          ),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _selectCamera(
    BuildContext context,
    WidgetRef ref,
    String? deviceId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await ref
          .read(videoInputCapabilityProvider.notifier)
          .selectVideoInput(deviceId);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not update camera: ${_formatSettingsError(error)}',
          ),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _testMicrophone(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() {
      _testingMicrophone = true;
      _microphoneTestFailed = false;
      _microphoneTestMessage = 'Testing microphone...';
    });
    try {
      await ref
          .read(microphoneSelectionProvider.notifier)
          .testSelectedMicrophone();
      if (!mounted) {
        return;
      }
      setState(() {
        _microphoneTestFailed = false;
        _microphoneTestMessage = 'Microphone is available.';
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Microphone is available.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = _formatSettingsError(error);
      setState(() {
        _microphoneTestFailed = true;
        _microphoneTestMessage = message;
      });
      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: errorColor),
      );
    } finally {
      if (mounted) {
        setState(() => _testingMicrophone = false);
      }
    }
  }

  Future<void> _setSoundEffectsEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    return _runAudioSettingsAction(
      context,
      () => ref
          .read(voiceAudioSettingsProvider.notifier)
          .setSoundEffectsEnabled(enabled),
    );
  }

  Future<void> _setSoundEffectsVolume(
    BuildContext context,
    WidgetRef ref,
    double volume,
  ) {
    return _runAudioSettingsAction(
      context,
      () => ref
          .read(voiceAudioSettingsProvider.notifier)
          .setSoundEffectsVolume(volume),
    );
  }

  Future<void> _setCallSoundsEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    return _runAudioSettingsAction(
      context,
      () => ref
          .read(voiceAudioSettingsProvider.notifier)
          .setCallSoundsEnabled(enabled),
    );
  }

  Future<void> _setConnectionRequestSoundsEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    return _runConnectionRequestSettingsAction(
      context,
      () => ref
          .read(voiceAudioSettingsProvider.notifier)
          .setConnectionRequestSoundsEnabled(enabled),
    );
  }

  Future<void> _setConnectionRequestNotificationsEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    return _runConnectionRequestSettingsAction(
      context,
      () => ref
          .read(connectionRequestSettingsProvider.notifier)
          .setNotificationsEnabled(enabled),
    );
  }

  Future<void> _setShowConnectionRequestNotificationsWhenMinimized(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    return _runConnectionRequestSettingsAction(
      context,
      () => ref
          .read(connectionRequestSettingsProvider.notifier)
          .setShowNotificationsWhenMinimized(enabled),
    );
  }

  Future<void> _unmuteConnectionRequestSender(
    BuildContext context,
    WidgetRef ref,
    String peerId,
  ) {
    return _runConnectionRequestSettingsAction(context, () async {
      final state = ref.read(connectionRequestProvider);
      if (state.available) {
        await ref.read(connectionRequestProvider.notifier).unmute(peerId);
      }
      await ref
          .read(connectionRequestSettingsProvider.notifier)
          .removeMutedSender(peerId);
    });
  }

  Future<void> _setReduceSoundsDuringCall(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    return _runAudioSettingsAction(
      context,
      () => ref
          .read(voiceAudioSettingsProvider.notifier)
          .setReduceSoundsDuringCall(enabled),
    );
  }

  Future<void> _setDefaultOutputPreference(
    BuildContext context,
    WidgetRef ref,
    CallAudioOutputPreference preference,
  ) {
    return _runAudioSettingsAction(
      context,
      () => ref
          .read(voiceAudioSettingsProvider.notifier)
          .setDefaultOutputPreference(preference),
    );
  }

  Future<void> _setClearVoiceEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    return _runCallProcessingSettingsAction(context, () async {
      await ref
          .read(callProcessingSettingsProvider.notifier)
          .setClearVoiceEnabled(enabled);
      await ref
          .read(runtimeControllerProvider)
          .value
          ?.refreshCallMediaProcessingConfig();
    });
  }

  Future<void> _setAutoVideoOptimizeEnabled(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) {
    return _runCallProcessingSettingsAction(context, () async {
      await ref
          .read(callProcessingSettingsProvider.notifier)
          .setAutoVideoOptimizeEnabled(enabled);
      await ref
          .read(runtimeControllerProvider)
          .value
          ?.refreshCallMediaProcessingConfig();
    });
  }

  Future<void> _runAudioSettingsAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await action();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not update audio setting: ${_formatSettingsError(error)}',
          ),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _runConnectionRequestSettingsAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await action();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not update connection request setting: ${_formatSettingsError(error)}',
          ),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _runCallProcessingSettingsAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await action();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not update call processing: ${_formatSettingsError(error)}',
          ),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    await ref.read(forceUpdateProvider.notifier).refresh();
    final result = ref.read(forceUpdateProvider);
    if (!context.mounted) {
      return;
    }
    if (result.hasError) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not check for updates: ${_formatSettingsError(result.error!)}',
          ),
          backgroundColor: errorColor,
        ),
      );
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Update check done.')));
  }

  Future<void> _openReleasePage(BuildContext context) async {
    final result = ref.read(forceUpdateProvider).value;
    final fallback = ref.read(appEnvironmentProvider).forceUpdateUrl;
    final url = result?.updateUrl.trim().isNotEmpty == true
        ? result!.updateUrl
        : fallback;
    await launchUrlString(url);
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

class _ConnectionRequestSettingsSection extends StatelessWidget {
  const _ConnectionRequestSettingsSection({
    required this.state,
    required this.settings,
    required this.audioSettings,
    required this.backendMode,
    required this.onNotificationsEnabledChanged,
    required this.onSoundEnabledChanged,
    required this.onShowMinimizedChanged,
    required this.onUnmute,
  });

  final ConnectionRequestState state;
  final AsyncValue<AppConnectionRequestSettings> settings;
  final AsyncValue<AppAudioSettings> audioSettings;
  final ConnectionRequestBackendMode backendMode;
  final ValueChanged<bool> onNotificationsEnabledChanged;
  final ValueChanged<bool> onSoundEnabledChanged;
  final ValueChanged<bool> onShowMinimizedChanged;
  final ValueChanged<String> onUnmute;

  @override
  Widget build(BuildContext context) {
    final requestSettings =
        settings.value ?? const AppConnectionRequestSettings();
    final soundSettings = audioSettings.value ?? const AppAudioSettings();
    final isBusy = settings.isLoading || audioSettings.isLoading;
    final Object? error = settings.hasError
        ? settings.error
        : audioSettings.hasError
        ? audioSettings.error
        : null;
    final sparkMode = backendMode == ConnectionRequestBackendMode.rtdbOnly;
    final pendingInbound = state.incomingSurfaces
        .where((surface) => !surface.status.isTerminal)
        .length;
    final pendingOutbound = state.outgoingSurfaces
        .where((surface) => !surface.status.isTerminal)
        .length;
    final status = state.available
        ? '$pendingInbound inbound pending | $pendingOutbound outbound pending'
        : 'Connection request service is unavailable.';
    return AppSectionCard(
      child: Column(
        children: <Widget>[
          ListTile(
            leading: Icon(
              error == null
                  ? Icons.notifications_active_outlined
                  : Icons.error_outline,
              color: error == null ? null : Theme.of(context).colorScheme.error,
            ),
            title: const Text('Connection request prompts'),
            subtitle: Text(
              error == null ? status : _formatSettingsError(error),
            ),
          ),
          const Divider(height: 1),
          if (sparkMode) ...<Widget>[
            const ListTile(
              leading: Icon(Icons.bolt_outlined),
              title: Text('Spark mode'),
              subtitle: Text('Spark mode uses best-effort request limits.'),
            ),
            const Divider(height: 1),
          ],
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Connection request notifications'),
            subtitle: Text(
              requestSettings.notificationsEnabled
                  ? 'OS notifications are allowed.'
                  : 'Only in-app prompts are shown.',
            ),
            value: requestSettings.notificationsEnabled,
            onChanged: isBusy ? null : onNotificationsEnabledChanged,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.water_drop_outlined),
            title: const Text('Connection request sound'),
            subtitle: Text(
              soundSettings.connectionRequestSoundsEnabled ? 'On' : 'Off',
            ),
            value: soundSettings.connectionRequestSoundsEnabled,
            onChanged: isBusy ? null : onSoundEnabledChanged,
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.web_asset_outlined),
            title: const Text('Show notifications when minimized'),
            subtitle: Text(
              requestSettings.showNotificationsWhenMinimized
                  ? 'Rain can notify while the window is hidden.'
                  : 'Minimized windows use in-app prompts only.',
            ),
            value: requestSettings.showNotificationsWhenMinimized,
            onChanged: isBusy || !requestSettings.notificationsEnabled
                ? null
                : onShowMinimizedChanged,
          ),
          const Divider(height: 1),
          _ConnectionRequestQuotaTile(
            quota: state.quota,
            showServerEntitlements: !sparkMode,
          ),
          const Divider(height: 1),
          _MutedConnectionRequestSendersTile(
            senders: requestSettings.mutedRequestSenders,
            isBusy: isBusy,
            onUnmute: onUnmute,
          ),
        ],
      ),
    );
  }
}

class _ConnectionRequestQuotaTile extends StatelessWidget {
  const _ConnectionRequestQuotaTile({
    required this.quota,
    required this.showServerEntitlements,
  });

  final ConnectionRequestQuotaSnapshot? quota;
  final bool showServerEntitlements;

  @override
  Widget build(BuildContext context) {
    final quota = this.quota;
    if (quota == null) {
      return const ListTile(
        leading: Icon(Icons.speed_outlined),
        title: Text('Request quota'),
        subtitle: Text('Quota summary unavailable. Pull latest state first.'),
      );
    }
    final remaining = _remainingConnectionRequests(
      quota,
      includeExtraCredits: showServerEntitlements,
    );
    final details = <String>[
      '$remaining request${remaining == 1 ? '' : 's'} left today',
      '${quota.perTargetRemainingToday} per peer',
      '${quota.pendingOutboundCount} outbound pending',
      '${quota.pendingInboundCount} inbound pending',
      if (showServerEntitlements && quota.extraCreditsRemaining > 0)
        '${quota.extraCreditsRemaining} extra credit${quota.extraCreditsRemaining == 1 ? '' : 's'}',
      if (showServerEntitlements && quota.unlimitedUntil != null)
        'unlimited entitlement active',
      if (quota.disabled) 'feature disabled',
    ].join(' | ');
    return ListTile(
      leading: const Icon(Icons.speed_outlined),
      title: const Text('Request quota'),
      subtitle: Text('Read-only from Firebase. $details.'),
    );
  }
}

class _MutedConnectionRequestSendersTile extends StatelessWidget {
  const _MutedConnectionRequestSendersTile({
    required this.senders,
    required this.isBusy,
    required this.onUnmute,
  });

  final Set<String> senders;
  final bool isBusy;
  final ValueChanged<String> onUnmute;

  @override
  Widget build(BuildContext context) {
    final sorted = senders.toList(growable: false)..sort();
    if (sorted.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.notifications_active_outlined),
        title: Text('Muted request senders'),
        subtitle: Text('No muted senders.'),
      );
    }
    return Column(
      children: <Widget>[
        const ListTile(
          leading: Icon(Icons.notifications_off_outlined),
          title: Text('Muted request senders'),
          subtitle: Text('Unmute only changes the selected sender row.'),
        ),
        for (final sender in sorted) ...<Widget>[
          const Divider(height: 1),
          ListTile(
            key: ValueKey<String>('muted-connection-request-sender-$sender'),
            leading: const Icon(Icons.person_off_outlined),
            title: Text('@$sender'),
            trailing: TextButton(
              key: ValueKey<String>('unmute-connection-request-sender-$sender'),
              onPressed: isBusy ? null : () => onUnmute(sender),
              child: const Text('Unmute'),
            ),
          ),
        ],
      ],
    );
  }
}

int _remainingConnectionRequests(
  ConnectionRequestQuotaSnapshot quota, {
  required bool includeExtraCredits,
}) {
  final remaining =
      quota.dailyLimit +
      (includeExtraCredits ? quota.extraCreditsRemaining : 0) -
      quota.usedToday;
  return remaining < 0 ? 0 : remaining;
}

class _AboutRainSection extends StatelessWidget {
  const _AboutRainSection({
    required this.updateStatus,
    required this.onCheckForUpdates,
    required this.onOpenReleasePage,
  });

  final AsyncValue<VersionCheckResult> updateStatus;
  final VoidCallback onCheckForUpdates;
  final VoidCallback onOpenReleasePage;

  @override
  Widget build(BuildContext context) {
    return updateStatus.when(
      data: (result) => Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('Rain ${result.currentVersion}'),
            subtitle: Text(
              'Build ${result.displayCurrentBuild} | ${result.platform} | ${result.channel.name}',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(_updateStatusIcon(result.status)),
            title: Text(_updateStatusLabel(result)),
            subtitle: Text(_updateStatusDetail(result)),
          ),
          const Divider(height: 1),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton.icon(
                onPressed: onCheckForUpdates,
                icon: const Icon(Icons.refresh),
                label: const Text('Check for updates'),
              ),
              FilledButton.icon(
                onPressed: onOpenReleasePage,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open release page'),
              ),
            ],
          ),
        ],
      ),
      error: (Object error, StackTrace stackTrace) => ListTile(
        leading: Icon(
          Icons.system_update_alt,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Update status unavailable'),
        subtitle: Text(_formatSettingsError(error)),
        trailing: IconButton(
          tooltip: 'Check for updates',
          onPressed: onCheckForUpdates,
          icon: const Icon(Icons.refresh),
        ),
      ),
      loading: () => const ListTile(
        leading: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Checking app version'),
      ),
    );
  }

  IconData _updateStatusIcon(VersionCheckStatus status) {
    return switch (status) {
      VersionCheckStatus.current => Icons.verified_outlined,
      VersionCheckStatus.optionalUpdateAvailable => Icons.system_update_alt,
      VersionCheckStatus.updateRequired => Icons.warning_amber_outlined,
      VersionCheckStatus.checkUnavailable => Icons.cloud_off_outlined,
      VersionCheckStatus.invalidConfig => Icons.error_outline,
    };
  }

  String _updateStatusLabel(VersionCheckResult result) {
    return switch (result.status) {
      VersionCheckStatus.current => 'Rain is up to date',
      VersionCheckStatus.optionalUpdateAvailable => 'Update available',
      VersionCheckStatus.updateRequired => 'Update required',
      VersionCheckStatus.checkUnavailable => 'Update check unavailable',
      VersionCheckStatus.invalidConfig => 'Update config invalid',
    };
  }

  String _updateStatusDetail(VersionCheckResult result) {
    return switch (result.status) {
      VersionCheckStatus.current =>
        'Latest known: ${result.displayLatestVersion}',
      VersionCheckStatus.optionalUpdateAvailable =>
        'Latest: ${result.displayLatestVersion} build ${result.displayLatestBuild}',
      VersionCheckStatus.updateRequired =>
        'Minimum: ${result.minVersion} build ${result.displayMinimumBuild}',
      VersionCheckStatus.checkUnavailable =>
        result.failureReason ?? 'Could not verify update status.',
      VersionCheckStatus.invalidConfig =>
        result.failureReason ?? 'Remote update config could not be parsed.',
    };
  }
}

class _MicrophoneTestTile extends StatelessWidget {
  const _MicrophoneTestTile({
    required this.isTesting,
    required this.failed,
    required this.message,
    required this.onTest,
  });

  final bool isTesting;
  final bool failed;
  final String? message;
  final VoidCallback? onTest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        failed ? Icons.error_outline : Icons.graphic_eq,
        color: failed ? scheme.error : null,
      ),
      title: const Text('Test microphone'),
      subtitle: Text(message ?? 'Check selected input'),
      trailing: IconButton(
        tooltip: 'Test microphone',
        onPressed: onTest,
        icon: isTesting
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow),
      ),
    );
  }
}

class _ClearVoiceTile extends StatelessWidget {
  const _ClearVoiceTile({
    required this.enabled,
    required this.isBusy,
    required this.onChanged,
  });

  final bool enabled;
  final bool isBusy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.noise_control_off),
      title: const Text('Clear voice'),
      subtitle: const Text(
        'Clear voice reduces background noise during calls.',
      ),
      value: enabled,
      onChanged: isBusy ? null : onChanged,
    );
  }
}

class _AutoVideoOptimizeTile extends StatelessWidget {
  const _AutoVideoOptimizeTile({
    required this.enabled,
    required this.isBusy,
    required this.onChanged,
  });

  final bool enabled;
  final bool isBusy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.speed),
      title: const Text('Auto video optimize'),
      subtitle: const Text(
        'Auto video optimize adjusts quality when the network is weak.',
      ),
      value: enabled,
      onChanged: isBusy ? null : onChanged,
    );
  }
}

class _VoiceAudioSettingsControls extends StatelessWidget {
  const _VoiceAudioSettingsControls({
    required this.settings,
    required this.outputCapabilities,
    required this.isBusy,
    required this.onSoundEffectsEnabledChanged,
    required this.onSoundEffectsVolumeChanged,
    required this.onCallSoundsEnabledChanged,
    required this.onReduceSoundsDuringCallChanged,
    required this.onOutputPreferenceChanged,
  });

  final AppAudioSettings settings;
  final AudioOutputCapabilityState outputCapabilities;
  final bool isBusy;
  final ValueChanged<bool> onSoundEffectsEnabledChanged;
  final ValueChanged<double> onSoundEffectsVolumeChanged;
  final ValueChanged<bool> onCallSoundsEnabledChanged;
  final ValueChanged<bool> onReduceSoundsDuringCallChanged;
  final ValueChanged<CallAudioOutputPreference> onOutputPreferenceChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = !isBusy;
    final soundControlsEnabled = enabled && settings.soundEffectsEnabled;
    final outputPreferences = _outputPreferencesFor(
      outputCapabilities,
      AdaptiveDeviceProfile.resolve(
        targetPlatform: defaultTargetPlatform,
        width: MediaQuery.sizeOf(context).width,
        lowPower: false,
      ),
    );
    final effectiveOutputPreference = _effectiveOutputPreference(
      settings.defaultOutputPreference,
      outputPreferences,
    );
    final outputPreferenceUnavailable =
        settings.defaultOutputPreference != effectiveOutputPreference;
    return Column(
      children: <Widget>[
        ListTile(
          leading: Icon(_outputPreferenceIcon(effectiveOutputPreference)),
          title: const Text('Default call output'),
          subtitle: Text(
            outputPreferenceUnavailable
                ? 'Bluetooth unavailable. Using system default.'
                : _outputPreferenceLabel(effectiveOutputPreference),
          ),
          trailing: PopupMenuButton<CallAudioOutputPreference>(
            tooltip: 'Choose default call output',
            enabled: enabled,
            onSelected: onOutputPreferenceChanged,
            itemBuilder: (BuildContext context) {
              return <PopupMenuEntry<CallAudioOutputPreference>>[
                for (final preference in outputPreferences)
                  PopupMenuItem<CallAudioOutputPreference>(
                    value: preference,
                    child: _OutputPreferenceMenuRow(
                      preference: preference,
                      selected: effectiveOutputPreference == preference,
                    ),
                  ),
              ];
            },
            icon: const Icon(Icons.arrow_drop_down_circle_outlined),
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.music_note),
          title: const Text('Sound effects'),
          subtitle: Text(settings.soundEffectsEnabled ? 'On' : 'Off'),
          value: settings.soundEffectsEnabled,
          onChanged: enabled ? onSoundEffectsEnabledChanged : null,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.volume_up),
          title: const Text('Sound effects volume'),
          subtitle: Slider(
            value: settings.soundEffectsVolume,
            divisions: 10,
            label: _volumeLabel(settings.soundEffectsVolume),
            onChanged: soundControlsEnabled
                ? onSoundEffectsVolumeChanged
                : null,
          ),
          trailing: SizedBox(
            width: 48,
            child: Text(
              _volumeLabel(settings.soundEffectsVolume),
              textAlign: TextAlign.end,
            ),
          ),
          enabled: soundControlsEnabled,
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.call),
          title: const Text('Call sounds'),
          subtitle: Text(settings.callSoundsEnabled ? 'On' : 'Off'),
          value: settings.callSoundsEnabled,
          onChanged: soundControlsEnabled ? onCallSoundsEnabledChanged : null,
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.volume_down),
          title: const Text('Reduce during calls'),
          subtitle: Text(settings.reduceSoundsDuringCall ? 'On' : 'Off'),
          value: settings.reduceSoundsDuringCall,
          onChanged: soundControlsEnabled
              ? onReduceSoundsDuringCallChanged
              : null,
        ),
      ],
    );
  }
}

class _OutputPreferenceMenuRow extends StatelessWidget {
  const _OutputPreferenceMenuRow({
    required this.preference,
    required this.selected,
  });

  final CallAudioOutputPreference preference;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RainRippleHaloSurface(
      enabled: selected,
      borderRadius: BorderRadius.circular(12),
      color: scheme.primary,
      origin: Alignment.centerLeft,
      pulseKey: preference.name,
      pulseOnMount: selected,
      minSize: const Size(48, 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle : _outputPreferenceIcon(preference),
              size: 20,
              color: selected ? scheme.primary : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _outputPreferenceLabel(preference),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _outputPreferenceIcon(CallAudioOutputPreference preference) {
  return switch (preference) {
    CallAudioOutputPreference.systemDefault => Icons.volume_up,
    CallAudioOutputPreference.speaker => Icons.speaker_phone,
    CallAudioOutputPreference.bluetooth => Icons.bluetooth_audio,
  };
}

String _outputPreferenceLabel(CallAudioOutputPreference preference) {
  return switch (preference) {
    CallAudioOutputPreference.systemDefault => 'System default',
    CallAudioOutputPreference.speaker => 'Speaker',
    CallAudioOutputPreference.bluetooth => 'Bluetooth',
  };
}

List<CallAudioOutputPreference> _outputPreferencesFor(
  AudioOutputCapabilityState capabilities,
  AdaptiveDeviceProfile profile,
) {
  if (profile.isDesktop) {
    return <CallAudioOutputPreference>[
      CallAudioOutputPreference.systemDefault,
      if (capabilities.hasBluetoothOutput) CallAudioOutputPreference.bluetooth,
    ];
  }
  return <CallAudioOutputPreference>[
    CallAudioOutputPreference.systemDefault,
    CallAudioOutputPreference.speaker,
    if (capabilities.hasBluetoothOutput) CallAudioOutputPreference.bluetooth,
  ];
}

CallAudioOutputPreference _effectiveOutputPreference(
  CallAudioOutputPreference preference,
  List<CallAudioOutputPreference> available,
) {
  if (available.contains(preference)) {
    return preference;
  }
  return CallAudioOutputPreference.systemDefault;
}

String _volumeLabel(double value) {
  return '${(value * 100).round()}%';
}

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

class _SoundDiagnosticsTile extends StatelessWidget {
  const _SoundDiagnosticsTile({required this.diagnostics});

  final SoundEventRouterDiagnostics diagnostics;

  @override
  Widget build(BuildContext context) {
    final loopIds = diagnostics.activeLoopIds.toList(growable: false)..sort();
    final detail = <String>[
      'Last: ${diagnostics.lastEventKind?.name ?? 'none'}',
      'Suppressed: ${diagnostics.lastSuppressedReason ?? 'none'}',
      'Loops: ${loopIds.isEmpty ? 'none' : loopIds.join(', ')}',
      'Disabled: ${diagnostics.soundServiceDisabledReason ?? 'none'}',
    ].join(' | ');
    return ListTile(
      leading: const Icon(Icons.graphic_eq),
      title: const Text('App sound diagnostics'),
      subtitle: Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
    );
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
        padding: EdgeInsets.all(18),
        child: RainStreakSkeleton(rows: 2),
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
