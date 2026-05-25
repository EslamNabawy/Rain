import 'dart:math' as math;

import 'package:flutter/widgets.dart';

final class CallSurfaceBounds {
  const CallSurfaceBounds({
    required this.viewportSize,
    required this.safePadding,
    required this.panelSize,
    this.margin = 12,
  });

  final Size viewportSize;
  final EdgeInsets safePadding;
  final Size panelSize;
  final double margin;

  double get minX => safePadding.left + margin;

  double get minY => safePadding.top + margin;

  double get maxX => math.max(
    minX,
    viewportSize.width - safePadding.right - margin - panelSize.width,
  );

  double get maxY => math.max(
    minY,
    viewportSize.height - safePadding.bottom - margin - panelSize.height,
  );
}

Offset centeredCallSurfaceOffset(CallSurfaceBounds bounds) {
  final availableWidth =
      bounds.viewportSize.width -
      bounds.safePadding.left -
      bounds.safePadding.right -
      (bounds.margin * 2);
  final availableHeight =
      bounds.viewportSize.height -
      bounds.safePadding.top -
      bounds.safePadding.bottom -
      (bounds.margin * 2);
  return clampCallSurfaceOffset(
    bounds,
    Offset(
      bounds.minX + ((availableWidth - bounds.panelSize.width) / 2),
      bounds.minY + ((availableHeight - bounds.panelSize.height) / 2),
    ),
  );
}

Offset clampCallSurfaceOffset(CallSurfaceBounds bounds, Offset offset) {
  return Offset(
    _clampFinite(offset.dx, bounds.minX, bounds.maxX),
    _clampFinite(offset.dy, bounds.minY, bounds.maxY),
  );
}

double _clampFinite(double value, double min, double max) {
  if (!value.isFinite) {
    return min;
  }
  return value.clamp(min, max).toDouble();
}
