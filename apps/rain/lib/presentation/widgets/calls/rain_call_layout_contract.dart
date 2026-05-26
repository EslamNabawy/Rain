import 'package:rain/application/state/call_surface_providers.dart';

enum RainCallSurfaceMode { minimized, popup, fullscreen, pip }

enum RainVideoRole { remotePrimary, localPrimary }

final class RainCallLayoutContract {
  const RainCallLayoutContract({
    required this.surfaceMode,
    required this.videoRole,
    required this.showTopManagerBar,
    required this.showMediaSurface,
    required this.showExpandedControls,
    required this.showDesktopSidePanel,
  });

  final RainCallSurfaceMode surfaceMode;
  final RainVideoRole videoRole;
  final bool showTopManagerBar;
  final bool showMediaSurface;
  final bool showExpandedControls;
  final bool showDesktopSidePanel;

  bool get isFullscreen => surfaceMode == RainCallSurfaceMode.fullscreen;

  bool get isPictureInPicture => surfaceMode == RainCallSurfaceMode.pip;

  factory RainCallLayoutContract.forMode({
    required RainCallSurfaceMode mode,
    required RainVideoRole videoRole,
    required bool isDesktop,
  }) {
    return RainCallLayoutContract(
      surfaceMode: mode,
      videoRole: videoRole,
      showTopManagerBar:
          mode == RainCallSurfaceMode.minimized ||
          mode == RainCallSurfaceMode.pip,
      showMediaSurface: mode != RainCallSurfaceMode.minimized,
      showExpandedControls:
          mode == RainCallSurfaceMode.popup ||
          mode == RainCallSurfaceMode.fullscreen,
      showDesktopSidePanel: mode == RainCallSurfaceMode.fullscreen && isDesktop,
    );
  }

  factory RainCallLayoutContract.fromSurface(
    CallSurfaceState surface, {
    required bool isDesktop,
  }) {
    return RainCallLayoutContract.forMode(
      mode: _surfaceModeFor(surface.mode),
      videoRole: _videoRoleFor(surface.videoPrimaryRole),
      isDesktop: isDesktop,
    );
  }
}

RainCallSurfaceMode _surfaceModeFor(CallSurfaceMode mode) {
  return switch (mode) {
    CallSurfaceMode.managerOnly => RainCallSurfaceMode.minimized,
    CallSurfaceMode.expanded => RainCallSurfaceMode.popup,
    CallSurfaceMode.fullscreen => RainCallSurfaceMode.fullscreen,
    CallSurfaceMode.pip => RainCallSurfaceMode.pip,
  };
}

RainVideoRole _videoRoleFor(VideoPrimaryRole role) {
  return switch (role) {
    VideoPrimaryRole.remote => RainVideoRole.remotePrimary,
    VideoPrimaryRole.local => RainVideoRole.localPrimary,
  };
}
