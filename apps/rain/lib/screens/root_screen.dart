import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../providers/app_providers.dart';
import '../services/force_update_service.dart';
import '../widgets/backend_banner.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(appEnvironmentProvider);
    final forceUpdate = ref.watch(forceUpdateProvider);
    final identity = ref.watch(identityProvider);

    if (identity.valueOrNull != null) {
      ref.watch(runtimeControllerProvider);
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFE0F4F1),
            Color(0xFFF8F7F3),
            Color(0xFFFFF1E6),
          ],
        ),
      ),
      child: forceUpdate.when(
        data: (result) {
          if (result.requiresUpdate) {
            return _ForceUpdateGate(result: result);
          }

          return identity.when(
            data: (value) {
              if (value == null) {
                return Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Column(
                    children: <Widget>[
                      if (environment.shouldUseFallbackAdapter)
                        BackendBanner(message: environment.fallbackReason),
                      const Expanded(child: OnboardingScreen()),
                    ],
                  ),
                );
              }

              return Scaffold(
                backgroundColor: Colors.transparent,
                body: Column(
                  children: <Widget>[
                    if (environment.shouldUseFallbackAdapter)
                      BackendBanner(message: environment.fallbackReason),
                    const Expanded(child: HomeScreen()),
                  ],
                ),
              );
            },
            error: (error, stackTrace) => _ErrorView(error: error.toString()),
            loading: () => const _LoadingView(),
          );
        },
        error: (error, stackTrace) => _ErrorView(error: error.toString()),
        loading: () => const _LoadingView(),
      ),
    );
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
    return const Center(child: CircularProgressIndicator());
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
