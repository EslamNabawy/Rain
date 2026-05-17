import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/presentation/widgets/backend_banner.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'splash_screen.dart';

class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(appEnvironmentProvider);
    final forceUpdate = ref.watch(forceUpdateProvider);
    final identity = ref.watch(identityProvider);
    final runtime = identity.valueOrNull == null
        ? const AsyncValue<RainRuntimeController?>.data(null)
        : ref.watch(runtimeControllerProvider);

    return forceUpdate.when(
      data: (ForceUpdateResult result) {
        if (result.requiresUpdate) {
          return _ForceUpdateGate(result: result);
        }

        return identity.when(
          data: (value) {
            if (value == null) {
              return _withBanners(
                environment: environment,
                child: const OnboardingScreen(),
              );
            }

            return runtime.when(
              data: (_) => _withBanners(
                environment: environment,
                child: const HomeScreen(),
              ),
              error: (error, stackTrace) {
                if (error is SignalingSessionExpiredException) {
                  return _SessionExpiredResetView(error: error.toString());
                }
                return _ErrorView(
                  error: 'Rain could not start.\n${error.toString()}',
                );
              },
              loading: () => const _LoadingView(),
            );
          },
          error: (error, stackTrace) => _ErrorView(error: error.toString()),
          loading: () => const _LoadingView(),
        );
      },
      error: (error, stackTrace) => _ErrorView(error: error.toString()),
      loading: () => const _LoadingView(),
    );
  }

  Widget _withBanners({
    required AppEnvironment environment,
    required Widget child,
  }) {
    return Column(
      children: <Widget>[
        if (environment.shouldUseFallbackAdapter)
          BackendBanner(message: environment.fallbackReason),
        Expanded(child: child),
      ],
    );
  }
}

class _SessionExpiredResetView extends ConsumerStatefulWidget {
  const _SessionExpiredResetView({required this.error});

  final String error;

  @override
  ConsumerState<_SessionExpiredResetView> createState() =>
      _SessionExpiredResetViewState();
}

class _SessionExpiredResetViewState
    extends ConsumerState<_SessionExpiredResetView> {
  bool _resetStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resetStarted) {
      return;
    }
    _resetStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reset();
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
    return const _LoadingView();
  }
}

class _ForceUpdateGate extends StatelessWidget {
  const _ForceUpdateGate({required this.result});

  final ForceUpdateResult result;

  @override
  Widget build(BuildContext context) {
    return Center(
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
                  'Rain ${result.currentVersion} can no longer connect. Install at least ${result.minVersion} to continue.',
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => launchUrlString(result.updateUrl),
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

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const RainSplashScreen();
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(error, textAlign: TextAlign.center),
      ),
    );
  }
}
