import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:rain/application/state/app_providers.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/rain_backdrop.dart';
import 'splash_screen.dart';

class RainStartupSurface extends StatelessWidget {
  const RainStartupSurface({required this.state, super.key});

  final AppStartupState state;

  @override
  Widget build(BuildContext context) {
    return switch (state.phase) {
      AppStartupPhase.checkingUpdate ||
      AppStartupPhase.validatingSession ||
      AppStartupPhase.startingRuntime => const RainSplashScreen(),
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
    return const RainSplashScreen();
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 18,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Update required',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Rain ${updateResult.currentVersion} can no longer connect. Install at least ${updateResult.minVersion} to continue.',
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => launchUrlString(updateResult.updateUrl),
                  icon: const Icon(Icons.system_update_alt),
                  label: const Text('Open update page'),
                ),
              ],
            ),
          ),
        ),
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
