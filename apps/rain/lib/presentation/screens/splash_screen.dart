import 'package:flutter/material.dart';

import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
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

class _SplashBody extends StatelessWidget {
  const _SplashBody({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.of(context).disableAnimations;
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
          RainRippleHaloSurface(
            enabled: true,
            borderRadius: BorderRadius.circular(56),
            color: RainColors.peerMint,
            pulseKey: 'splash-logo',
            pulseOnMount: true,
            child: RainPeerCoreAnimatedMark(
              key: const ValueKey<String>('rain-splash-peer-core-mark'),
              size: 112,
              motion: RainPeerCoreMotion.orbitalMesh,
              reducedMotion: reducedMotion,
            ),
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
