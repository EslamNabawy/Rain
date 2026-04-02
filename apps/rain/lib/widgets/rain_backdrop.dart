import 'package:flutter/material.dart';

import '../theme/rain_theme.dart';

class RainBackdrop extends StatelessWidget {
  const RainBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            RainColors.backgroundDark,
            RainColors.backgroundMid,
            RainColors.backgroundDeep,
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[const _RainAtmosphere(), child],
      ),
    );
  }
}

class _RainAtmosphere extends StatelessWidget {
  const _RainAtmosphere();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.08,
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -40,
              left: -20,
              child: _GlowBlob(color: RainColors.primary),
            ),
            Positioned(
              top: 160,
              right: -30,
              child: _GlowBlob(color: RainColors.secondary),
            ),
            Positioned(
              bottom: -30,
              left: 120,
              child: _GlowBlob(color: RainColors.tertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
