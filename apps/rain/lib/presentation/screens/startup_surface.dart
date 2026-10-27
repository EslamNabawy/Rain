/// # startup_surface
///
/// Startup phase surface router that displays appropriate UI for each
/// app startup state including splash, force update gate, session expired
/// reset, and failure screens. Handles automatic session cleanup on expiry.
///
/// **Key types:** RainStartupSurface, RainSessionExpiredResetView, RainForceUpdateGate
///
/// **Depends on:** app_providers, splash_screen, force_update_service
library;

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:rain/application/state/app_providers.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/presentation/branding/rain_state_surfaces.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/rain_backdrop.dart';
import 'splash_screen.dart';

class RainStartupSurface extends StatelessWidget {
  const RainStartupSurface({required this.state, super.key});

  final AppStartupState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.phase) {
      AppStartupPhase.checkingUpdate => const RainSplashScreen(
        caption: 'Checking for updates',
      ),
      AppStartupPhase.validatingSession => const RainSplashScreen(
        caption: 'Restoring your session',
      ),
      AppStartupPhase.startingRuntime => const RainSplashScreen(
        caption: 'Starting secure link',
      ),
      AppStartupPhase.deletingAccount => const RainAccountDeletionScreen(),
      AppStartupPhase.updateRequired => RainForceUpdateGate(
        result: state.updateResult,
      ),
      AppStartupPhase.sessionExpired => RainSessionExpiredResetView(
        error: state.error?.toString() ?? 'Session expired.',
      ),
      AppStartupPhase.failed => RainStartupFailureScreen(
        error: state.error ?? 'Unknown startup failure.',
      ),
      AppStartupPhase.signedOut ||
      AppStartupPhase.ready => const RainSplashScreen(),
    };
  }
}

class RainSessionExpiredResetView extends ConsumerStatefulWidget {
  const RainSessionExpiredResetView({required this.error, super.key});

  final String error;

  @override
  ConsumerState<RainSessionExpiredResetView> createState() =>
      _RainSessionExpiredResetViewState();
}

class _RainSessionExpiredResetViewState
    extends ConsumerState<RainSessionExpiredResetView> {
  bool _resetStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resetStarted) {
      return;
    }
    _resetStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reset());
    });
  }

  Future<void> _reset() async {
    try {
      await ref.read(identityProvider.notifier).resetExpiredSession();
    } catch (_) {
      // If cleanup fails, the next app launch will surface the original
      // backend error again.
    }
  }

  @override
  Widget build(BuildContext context) {
    return const RainSplashScreen(caption: 'Signing you out safely');
  }
}

class RainForceUpdateGate extends StatelessWidget {
  const RainForceUpdateGate({required this.result, super.key});

  final ForceUpdateResult? result;

  @override
  Widget build(BuildContext context) {
    final updateResult = result;
    if (updateResult == null) {
      return const RainStartupFailureScreen(error: 'Update policy is missing.');
    }

    return _StartupScaffold(
      child: RainMistStateCard(
        key: const ValueKey<String>('qa.update.card'),
        severity: RainStateSeverity.warning,
        icon: Icons.system_update_alt,
        maxWidth: 520,
        title: 'Update required',
        message: 'This version of Rain can no longer connect.',
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: RainSpace.sm,
              runSpacing: RainSpace.sm,
              children: <Widget>[
                _VersionChip(label: 'Installed ${updateResult.currentVersion}'),
                _VersionChip(label: 'Required ${updateResult.minVersion}'),
              ],
            ),
            const SizedBox(height: RainSpace.lg),
            FilledButton.icon(
              key: const ValueKey<String>('qa.update.open'),
              onPressed: () => launchUrlString(updateResult.updateUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Get the update'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(RainRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RainSpace.md,
          vertical: RainSpace.xs,
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium),
      ),
    );
  }
}

class _StartupScaffold extends StatelessWidget {
  const _StartupScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RainColors.backgroundDark,
      body: RainBackdrop.splash(
        child: Center(
          child: Padding(padding: const EdgeInsets.all(28), child: child),
        ),
      ),
    );
  }
}
