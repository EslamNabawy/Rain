import 'dart:async';

import 'package:flutter/material.dart';

import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/performance/rain_motion_policy.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/rain_backdrop.dart';

bool _splashIntroPlayed = false;

/// Test hook: forgets that the splash intro scale already played.
@visibleForTesting
void debugResetSplashIntro() => _splashIntroPlayed = false;

class RainSplashScreen extends StatelessWidget {
  const RainSplashScreen({super.key, this.caption});

  /// Short phase label shown under the subtitle after
  /// [RainMotion.splashCaptionDelay], so quick phases never flash text.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return _SplashScaffold(
      child: _SplashBody(
        title: 'Rain',
        subtitle: 'Private peer link',
        caption: caption,
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

class _SplashBody extends StatefulWidget {
  const _SplashBody({
    required this.title,
    required this.subtitle,
    this.caption,
  });

  final String title;
  final String subtitle;
  final String? caption;

  @override
  State<_SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<_SplashBody> {
  // The intro scale plays once per process so later hand-offs between the
  // startup apps do not pulse the splash again.
  late final bool _playIntro;
  Timer? _captionTimer;
  bool _captionReady = false;

  @override
  void initState() {
    super.initState();
    _playIntro = !_splashIntroPlayed;
    _splashIntroPlayed = true;
    _captionTimer = Timer(RainMotion.splashCaptionDelay, () {
      if (mounted) {
        setState(() => _captionReady = true);
      }
    });
  }

  @override
  void dispose() {
    _captionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title;
    final subtitle = widget.subtitle;
    final reducedMotion = RainMotionPolicy.of(context).reduced;
    final animateIntro = _playIntro && !reducedMotion;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.92, end: 1),
      duration: animateIntro ? RainMotion.splashIntro : Duration.zero,
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: animateIntro ? scale : 1, child: child);
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
          SizedBox(
            height: 36,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSwitcher(
                duration: RainMotionPolicy.of(context).d(RainMotion.standard),
                child: _captionReady && widget.caption != null
                    ? _SplashCaption(
                        key: ValueKey<String>(widget.caption!),
                        text: widget.caption!,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey<String>('rain-splash-no-caption'),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashCaption extends StatefulWidget {
  const _SplashCaption({super.key, required this.text});

  final String text;

  @override
  State<_SplashCaption> createState() => _SplashCaptionState();
}

class _SplashCaptionState extends State<_SplashCaption> {
  Timer? _timer;
  int _dots = 3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    _timer = null;
    if (RainMotionPolicy.read(context).reduced) {
      _dots = 3;
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (mounted) {
        setState(() => _dots = _dots % 3 + 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.6));
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(
            style: style,
            children: <InlineSpan>[
              TextSpan(text: widget.text),
              TextSpan(text: '.' * _dots),
              TextSpan(
                text: '.' * (3 - _dots),
                style: const TextStyle(color: Colors.transparent),
              ),
            ],
          ),
          key: const ValueKey<String>('rain-splash-caption'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
