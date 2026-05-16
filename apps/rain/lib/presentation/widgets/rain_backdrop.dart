import 'package:flutter/material.dart';

import 'package:rain/presentation/theme/rain_theme.dart';

class RainBackdrop extends StatelessWidget {
  const RainBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const <Color>[
                  RainColors.backgroundDark,
                  RainColors.backgroundMid,
                  RainColors.backgroundDeep,
                ]
              : const <Color>[
                  RainColors.backgroundLight,
                  RainColors.surfaceLight,
                  RainColors.backgroundLightCool,
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _RainAtmosphere(isDark: isDark),
          child,
        ],
      ),
    );
  }
}

class _RainAtmosphere extends StatelessWidget {
  const _RainAtmosphere({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: isDark ? 0.08 : 0.055,
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -40,
              left: -20,
              child: _GlowBlob(
                color: isDark ? RainColors.primary : RainColors.primaryLight,
              ),
            ),
            Positioned(
              top: 160,
              right: -30,
              child: _GlowBlob(
                color: isDark
                    ? RainColors.secondary
                    : RainColors.secondaryLight,
              ),
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
