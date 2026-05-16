import 'package:flutter/material.dart';

import '../theme/rain_theme.dart';

class RainSplashScreen extends StatelessWidget {
  const RainSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SplashScaffold(
      child: _SplashBody(
        title: 'Rain',
        subtitle: 'Peer command link',
        showProgress: true,
      ),
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
        showProgress: false,
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
      backgroundColor: const Color(0xFF061017),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF061017), Color(0xFF0B1F28)],
          ),
        ),
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
  const _SplashBody({
    required this.title,
    required this.subtitle,
    required this.showProgress,
  });

  final String title;
  final String subtitle;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.92, end: 1),
      duration: RainMotion.slow,
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF2DD4A3).withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/branding/rain_app_icon_1024.png',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const Icon(
                Icons.hub_outlined,
                size: 54,
                color: Color(0xFF2DD4A3),
              ),
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
          if (showProgress) ...<Widget>[
            const SizedBox(height: 26),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(
                minHeight: 3,
                color: Color(0xFF2DD4A3),
                backgroundColor: Color(0x2237E8FF),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
