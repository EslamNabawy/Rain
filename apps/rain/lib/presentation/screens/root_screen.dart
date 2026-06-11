/// # root_screen
///
/// Root screen router that switches between onboarding, home, and startup
/// surfaces based on app startup phase. Overlays backend environment banners
/// and optional update prompts on top of the main content.
///
/// **Key types:** RootScreen
///
/// **Depends on:** app_providers, onboarding_screen, home_screen, startup_surface
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:rain/core/config/app_environment.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/presentation/widgets/backend_banner.dart';
import 'package:rain/presentation/widgets/update/rain_update_prompt_banner.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';
import 'startup_surface.dart';

class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final environment = ref.watch(appEnvironmentProvider);
    final startup = ref.watch(appStartupStateProvider);

    return switch (startup.phase) {
      AppStartupPhase.signedOut => _withBanners(
        ref: ref,
        environment: environment,
        updateResult: startup.updateResult!,
        child: const OnboardingScreen(),
      ),
      AppStartupPhase.ready => _withBanners(
        ref: ref,
        environment: environment,
        updateResult: startup.updateResult!,
        child: const HomeScreen(),
      ),
      _ => RainStartupSurface(state: startup),
    };
  }

  Widget _withBanners({
    required WidgetRef ref,
    required AppEnvironment environment,
    required ForceUpdateResult updateResult,
    required Widget child,
  }) {
    final dismissedUpdateKey = updateResult.hasOptionalUpdate
        ? ref.watch(optionalUpdateDismissalProvider).value
        : null;
    final showOptionalUpdateBanner =
        updateResult.hasOptionalUpdate &&
        dismissedUpdateKey != updateResult.optionalUpdateDismissalKey;

    return Column(
      children: <Widget>[
        if (environment.shouldUseFallbackAdapter)
          BackendBanner(message: environment.fallbackReason),
        if (showOptionalUpdateBanner)
          RainUpdatePromptBanner(
            result: updateResult,
            onUpdate: () => unawaited(launchUrlString(updateResult.updateUrl)),
            onDismiss: () => unawaited(
              ref
                  .read(optionalUpdateDismissalProvider.notifier)
                  .dismiss(updateResult),
            ),
          ),
        Expanded(child: child),
      ],
    );
  }
}
