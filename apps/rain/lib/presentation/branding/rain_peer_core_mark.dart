import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:rain/presentation/performance/rain_performance.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

import 'rain_brand_assets.dart';

enum RainPeerCoreMotion { wave, orbitalMesh }

class RainPeerCoreMark extends StatelessWidget {
  const RainPeerCoreMark({
    super.key,
    required this.size,
    this.useTinyVariant = false,
    this.semanticLabel = 'Rain',
  });

  final double size;
  final bool useTinyVariant;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final path = useTinyVariant || size < 40
        ? RainBrandAssets.peerCoreMarkTiny
        : size < 96
        ? RainBrandAssets.peerCoreMarkSmall
        : RainBrandAssets.peerCoreMark;

    return Image.asset(
      path,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: semanticLabel,
    );
  }
}

class RainPeerCoreAnimatedMark extends StatefulWidget {
  const RainPeerCoreAnimatedMark({
    super.key,
    required this.size,
    this.animate = true,
    this.reducedMotion = false,
    this.motion = RainPeerCoreMotion.wave,
    this.startupWave = true,
    this.semanticLabel = 'Rain',
  });

  final double size;
  final bool animate;
  final bool reducedMotion;
  final RainPeerCoreMotion motion;
  final bool startupWave;
  final String semanticLabel;

  @override
  State<RainPeerCoreAnimatedMark> createState() =>
      _RainPeerCoreAnimatedMarkState();
}

class _RainPeerCoreAnimatedMarkState extends State<RainPeerCoreAnimatedMark>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _meshController;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: RainMotion.splashIntro,
    );
    _meshController = AnimationController(
      vsync: this,
      duration: RainMotion.ambientLoop,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion(fromStart: true);
  }

  @override
  void didUpdateWidget(RainPeerCoreAnimatedMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    final motionChanged =
        oldWidget.motion != widget.motion ||
        oldWidget.startupWave != widget.startupWave;
    _syncMotion(
      fromStart: motionChanged || !oldWidget.animate || oldWidget.reducedMotion,
    );
  }

  @override
  void dispose() {
    _introController.dispose();
    _meshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldAnimate(context)) {
      return RainPeerCoreMark(
        size: widget.size,
        semanticLabel: widget.semanticLabel,
      );
    }

    return SizedBox.square(
      key: ValueKey<RainPeerCoreMotion>(widget.motion),
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[
          _introController,
          _meshController,
        ]),
        builder: (context, _) {
          return Semantics(
            image: true,
            label: widget.semanticLabel,
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: <Widget>[
                  if (widget.startupWave) ...<Widget>[
                    _WaveLayer(
                      key: const ValueKey<String>('rain_peer_core_wave_outer'),
                      asset: RainBrandAssets.layerWaveOuter,
                      progress: _delayedIntroProgress(0.18),
                    ),
                    _WaveLayer(
                      key: const ValueKey<String>('rain_peer_core_wave_middle'),
                      asset: RainBrandAssets.layerWaveMiddle,
                      progress: _delayedIntroProgress(0.10),
                    ),
                    _WaveLayer(
                      key: const ValueKey<String>('rain_peer_core_wave_inner'),
                      asset: RainBrandAssets.layerWaveInner,
                      progress: _delayedIntroProgress(0),
                    ),
                  ],
                  SvgPicture.asset(RainBrandAssets.layerRing),
                  _PeerCoreMeshLayer(
                    motion: widget.motion,
                    turns: _meshController.value,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _shouldAnimate(BuildContext context) {
    return widget.animate &&
        !widget.reducedMotion &&
        MediaQuery.maybeOf(context)?.disableAnimations != true &&
        !RainPerformanceScope.read(context).isLowPower;
  }

  void _syncMotion({required bool fromStart}) {
    if (_shouldAnimate(context)) {
      _startMotion(fromStart: fromStart);
      return;
    }
    _introController.stop();
    _meshController.stop();
    if (fromStart) {
      _introController.value = 0;
      _meshController.value = 0;
    }
  }

  void _startMotion({required bool fromStart}) {
    if (widget.startupWave && (fromStart || !_introController.isAnimating)) {
      if (fromStart || _introController.value < 1) {
        _introController.forward(from: fromStart ? 0 : _introController.value);
      }
    }
    if (widget.motion == RainPeerCoreMotion.orbitalMesh) {
      if (!_meshController.isAnimating) {
        if (fromStart) {
          _meshController.value = 0;
        }
        _meshController.repeat();
      }
    } else {
      _meshController.stop();
      if (fromStart) {
        _meshController.value = 0;
      }
    }
  }

  double _delayedIntroProgress(double delay) {
    final value = (_introController.value - delay) / (1 - delay);
    return value.clamp(0.0, 1.0).toDouble();
  }
}

class _PeerCoreMeshLayer extends StatelessWidget {
  const _PeerCoreMeshLayer({required this.motion, required this.turns});

  final RainPeerCoreMotion motion;
  final double turns;

  @override
  Widget build(BuildContext context) {
    final mesh = Stack(
      key: const ValueKey<String>('rain_peer_core_mesh'),
      fit: StackFit.expand,
      children: <Widget>[
        SvgPicture.asset(RainBrandAssets.layerLinkAB),
        SvgPicture.asset(RainBrandAssets.layerLinkBC),
        SvgPicture.asset(RainBrandAssets.layerLinkCA),
        SvgPicture.asset(RainBrandAssets.layerNodeA),
        SvgPicture.asset(RainBrandAssets.layerNodeB),
        SvgPicture.asset(RainBrandAssets.layerNodeC),
      ],
    );
    if (motion != RainPeerCoreMotion.orbitalMesh) {
      return mesh;
    }

    return Transform.rotate(
      key: const ValueKey<String>('rain_peer_core_orbital_mesh'),
      angle: turns * math.pi * 2,
      child: mesh,
    );
  }
}

class _WaveLayer extends StatelessWidget {
  const _WaveLayer({super.key, required this.asset, required this.progress});

  final String asset;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - progress).clamp(0.0, 1.0).toDouble();
    final scale = 0.88 + (progress * 0.18);
    return Opacity(
      opacity: opacity,
      child: Transform.scale(scale: scale, child: SvgPicture.asset(asset)),
    );
  }
}
