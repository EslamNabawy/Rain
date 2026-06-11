/// # splash_screen
///
/// Splash and startup failure screens for Rain. Displays the animated
/// peer-core mark with configurable motion, plus dedicated screens for
/// startup errors and account deletion progress.
///
/// **Key types:** RainSplashScreen, RainStartupFailureScreen, RainAccountDeletionScreen
///
/// **Depends on:** RainPeerCoreAnimatedMark, RainBackdrop, RainTheme
import 'package:flutter/material.dart';

import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/rain_backdrop.dart';

class RainSplashScreen extends StatelessWidget {
  const RainSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SplashScaffold(
      child: _SplashBody(title: 'Rain', subtitle: 'Private peer link'),
    );
  }
}

class RainStartupFailureScreen extends StatelessWidget {
  const RainStartupFailureScreen({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return _SplashScaffold(
      child: _SplashBody(
        title: 'Rain could not start.',
        subtitle: error.toString(),
      ),
    );
  }
}

class RainAccountDeletionScreen extends StatelessWidget {
  const RainAccountDeletionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SplashScaffold(child: _DeletionProgressBody());
  }
}

class _SplashScaffold extends StatelessWidget {
  const _SplashScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RainColors.backgroundDark,
      body: RainBackdrop.splash(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DeletionProgressBody extends StatelessWidget {
  const _DeletionProgressBody();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Deleting account',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: 24),
          const Text(
            'Deleting account',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Removing backend account data and closing this session.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final lowPower = RainPerformanceScope.of(context).isLowPower;
    final reducedMotion = MediaQuery.of(context).disableAnimations || lowPower;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.92, end: 1),
      duration: reducedMotion ? Duration.zero : RainMotion.splashIntro,
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: reducedMotion ? 1 : scale, child: child);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RainPeerCoreAnimatedMark(
            key: const ValueKey<String>('rain-splash-peer-core-mark'),
            size: 112,
            motion: RainPeerCoreMotion.orbitalMesh,
            reducedMotion: reducedMotion,
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 14,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
