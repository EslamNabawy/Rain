import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'rain_brand_assets.dart';

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
  });

  final double size;
  final bool animate;
  final bool reducedMotion;

  @override
  State<RainPeerCoreAnimatedMark> createState() =>
      _RainPeerCoreAnimatedMarkState();
}

class _RainPeerCoreAnimatedMarkState extends State<RainPeerCoreAnimatedMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.animate && !widget.reducedMotion) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(RainPeerCoreAnimatedMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate &&
        !widget.reducedMotion &&
        (!oldWidget.animate || oldWidget.reducedMotion)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reducedMotion) {
      return RainPeerCoreMark(size: widget.size);
    }

    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: <Widget>[
              _WaveLayer(
                asset: RainBrandAssets.layerWaveOuter,
                progress: _delayedProgress(0.18),
              ),
              _WaveLayer(
                asset: RainBrandAssets.layerWaveMiddle,
                progress: _delayedProgress(0.10),
              ),
              _WaveLayer(
                asset: RainBrandAssets.layerWaveInner,
                progress: _delayedProgress(0),
              ),
              SvgPicture.asset(RainBrandAssets.layerRing),
              SvgPicture.asset(RainBrandAssets.layerLinkAB),
              SvgPicture.asset(RainBrandAssets.layerLinkBC),
              SvgPicture.asset(RainBrandAssets.layerLinkCA),
              SvgPicture.asset(RainBrandAssets.layerNodeA),
              SvgPicture.asset(RainBrandAssets.layerNodeB),
              SvgPicture.asset(RainBrandAssets.layerNodeC),
            ],
          );
        },
      ),
    );
  }

  double _delayedProgress(double delay) {
    final value = (_controller.value - delay) / (1 - delay);
    return value.clamp(0.0, 1.0).toDouble();
  }
}

class _WaveLayer extends StatelessWidget {
  const _WaveLayer({required this.asset, required this.progress});

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
