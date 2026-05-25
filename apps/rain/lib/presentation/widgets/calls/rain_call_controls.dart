import 'dart:async';

import 'package:flutter/material.dart';

import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/theme/rain_theme.dart';

class RainCallControls extends StatelessWidget {
  const RainCallControls({
    super.key,
    required this.state,
    required this.onAccept,
    required this.onReject,
    required this.onHangUp,
    required this.onRetry,
    required this.onToggleMute,
    this.onToggleDeafen,
    this.onToggleCamera,
    this.onSwitchCamera,
    this.onSelectOutputRoute,
    this.controlCapabilities,
    this.outputRouteOptions,
  });

  final VoiceCallState state;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<VoiceCallOutputRoute>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;

  @override
  Widget build(BuildContext context) {
    if (state.phase == VoiceCallPhase.incomingRinging) {
      return _IncomingCallActions(onAccept: onAccept, onReject: onReject);
    }

    if (state.phase == VoiceCallPhase.failed) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: <Widget>[
          if (rainVoiceCallCanRetry(state))
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          TextButton.icon(
            onPressed: onHangUp,
            icon: const Icon(Icons.close),
            label: const Text('Dismiss'),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: <Widget>[
        for (final capability
            in controlCapabilities ?? state.controlCapabilities)
          _buildActiveControl(context, capability),
      ],
    );
  }

  Widget _buildActiveControl(
    BuildContext context,
    CallControlCapability capability,
  ) {
    final visual = rainVoiceCallControlVisual(state, capability);
    final control = switch (capability) {
      CallControlCapability.microphone => IconButton(
        tooltip: visual.tooltip,
        onPressed: state.isActive ? onToggleMute : null,
        icon: Icon(visual.icon),
      ),
      CallControlCapability.camera => IconButton(
        tooltip: visual.tooltip,
        onPressed: state.isActive ? onToggleCamera : null,
        icon: Icon(visual.icon),
      ),
      CallControlCapability.switchCamera => IconButton(
        tooltip: visual.tooltip,
        onPressed: state.isActive ? onSwitchCamera : null,
        icon: Icon(visual.icon),
      ),
      CallControlCapability.deafen => IconButton(
        tooltip: visual.tooltip,
        onPressed: state.isActive ? onToggleDeafen : null,
        icon: Icon(visual.icon),
      ),
      CallControlCapability.outputRoute => _buildOutputRouteControl(
        visual: visual,
      ),
      CallControlCapability.hangUp => IconButton.filled(
        tooltip: visual.tooltip,
        onPressed: onHangUp,
        icon: Icon(visual.icon),
      ),
    };

    return RainRippleHaloSurface(
      enabled: state.isActive,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      color: rainVoiceCallHaloColor(context, state),
      pulseKey: '${state.callId}:${state.phase}:${capability.name}',
      minSize: const Size.square(48),
      child: control,
    );
  }

  Widget _buildOutputRouteControl({required RainCallControlVisual visual}) {
    final options = _effectiveOutputRouteOptions(outputRouteOptions);
    final enabled =
        state.isActive && onSelectOutputRoute != null && options.length > 1;
    final selected = _selectedOutputRouteOption(options, state.outputRoute);
    if (options.length <= 2) {
      return IconButton(
        tooltip: visual.tooltip,
        onPressed: enabled
            ? () => onSelectOutputRoute!(
                _nextOutputRoute(options, state.outputRoute),
              )
            : null,
        icon: Icon(selected.icon),
      );
    }
    return PopupMenuButton<VoiceCallOutputRoute>(
      tooltip: visual.tooltip,
      enabled: enabled,
      onSelected: onSelectOutputRoute,
      itemBuilder: (BuildContext context) {
        return <PopupMenuEntry<VoiceCallOutputRoute>>[
          for (final option in options)
            _outputRouteMenuItem(option: option, current: state.outputRoute),
        ];
      },
      icon: Icon(selected.icon),
    );
  }
}

class _IncomingCallActions extends StatelessWidget {
  const _IncomingCallActions({required this.onAccept, required this.onReject});

  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final stackActions =
            constraints.hasBoundedWidth && constraints.maxWidth < 340;
        final reject = _CallActionButton(
          key: const ValueKey<String>('rain-call-reject-button'),
          semanticsLabel: 'Decline call',
          onPressed: onReject,
          icon: Icons.call_end,
          label: 'Decline',
          filled: false,
        );
        final accept = _CallActionButton(
          key: const ValueKey<String>('rain-call-accept-button'),
          semanticsLabel: 'Answer call',
          onPressed: onAccept,
          icon: Icons.call,
          label: 'Answer',
          filled: true,
        );

        if (stackActions) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[reject, const SizedBox(height: 8), accept],
          );
        }

        if (!constraints.hasBoundedWidth) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[reject, const SizedBox(width: 10), accept],
          );
        }

        return SizedBox(
          width: constraints.maxWidth,
          child: Row(
            children: <Widget>[
              Expanded(child: reject),
              const SizedBox(width: 10),
              Expanded(child: accept),
            ],
          ),
        );
      },
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    super.key,
    required this.semanticsLabel,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.filled,
  });

  final String semanticsLabel;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          );
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: SizedBox(height: 52, child: child),
    );
  }
}

class RainCallControlVisual {
  const RainCallControlVisual({
    required this.tooltip,
    required this.icon,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final bool danger;
}

RainCallControlVisual rainVoiceCallControlVisual(
  VoiceCallState state,
  CallControlCapability capability,
) {
  return switch (capability) {
    CallControlCapability.microphone => RainCallControlVisual(
      tooltip: state.isMuted ? 'Unmute microphone' : 'Mute microphone',
      icon: state.isMuted ? Icons.mic_off : Icons.mic,
    ),
    CallControlCapability.camera => RainCallControlVisual(
      tooltip: state.isCameraMuted ? 'Turn camera on' : 'Turn camera off',
      icon: state.isCameraMuted ? Icons.videocam_off : Icons.videocam,
    ),
    CallControlCapability.switchCamera => const RainCallControlVisual(
      tooltip: 'Switch camera',
      icon: Icons.cameraswitch,
    ),
    CallControlCapability.deafen => RainCallControlVisual(
      tooltip: state.isDeafened ? 'Undeafen audio' : 'Deafen audio',
      icon: state.isDeafened ? Icons.volume_off : Icons.volume_up,
    ),
    CallControlCapability.outputRoute => RainCallControlVisual(
      tooltip: 'Choose audio output',
      icon: _outputRouteIcon(state.outputRoute),
    ),
    CallControlCapability.hangUp => rainVoiceCallTerminalActionVisual(state),
  };
}

RainCallControlVisual rainVoiceCallTerminalActionVisual(VoiceCallState state) {
  final isFailed = state.phase == VoiceCallPhase.failed;
  final isIncoming = state.phase == VoiceCallPhase.incomingRinging;
  return RainCallControlVisual(
    tooltip: isFailed
        ? 'Dismiss call'
        : isIncoming
        ? 'Reject call'
        : 'Hang up',
    icon: isFailed ? Icons.close : Icons.call_end,
    danger: !isFailed,
  );
}

typedef RainCallTickerBuilder =
    Widget Function(BuildContext context, int nowMs);

class RainCallTicker extends StatefulWidget {
  const RainCallTicker({super.key, required this.state, required this.builder});

  final VoiceCallState state;
  final RainCallTickerBuilder builder;

  @override
  State<RainCallTicker> createState() => _RainCallTickerState();
}

class _RainCallTickerState extends State<RainCallTicker> {
  Timer? _timer;
  String? _activeTickerKey;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant RainCallTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _nowMs());
  }

  void _syncTicker() {
    final tickerKey = _tickerKey(widget.state);
    if (tickerKey == null) {
      _stopTicker();
      return;
    }
    if (_activeTickerKey == tickerKey && _timer != null) {
      return;
    }
    _stopTicker();
    _activeTickerKey = tickerKey;
    _elapsedMs = _elapsedSinceStart();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(_advanceElapsed);
      }
    });
  }

  void _stopTicker() {
    _timer?.cancel();
    _timer = null;
    _activeTickerKey = null;
    _elapsedMs = 0;
  }

  int _nowMs() {
    final startedAt = widget.state.startedAt;
    if (_activeTickerKey != null && startedAt != null) {
      return startedAt + _elapsedMs;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  void _advanceElapsed() {
    final timerElapsed = _elapsedMs + const Duration(seconds: 1).inMilliseconds;
    final wallElapsed = _elapsedSinceStart();
    _elapsedMs = wallElapsed > timerElapsed ? wallElapsed : timerElapsed;
  }

  int _elapsedSinceStart() {
    final startedAt = widget.state.startedAt;
    if (startedAt == null) {
      return 0;
    }
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - startedAt;
    return elapsedMs < 0 ? 0 : elapsedMs;
  }

  String? _tickerKey(VoiceCallState state) {
    if (!state.isActive || state.startedAt == null) {
      return null;
    }
    return '${state.callId}:${state.sessionEpoch}:${state.startedAt}';
  }
}

List<VoiceCallOutputRouteOption> rainVoiceCallOutputRouteOptions({
  bool hasBluetoothOutput = true,
}) {
  return <VoiceCallOutputRouteOption>[
    const VoiceCallOutputRouteOption(
      route: VoiceCallOutputRoute.systemDefault,
      label: 'Default',
      icon: Icons.volume_up,
    ),
    const VoiceCallOutputRouteOption(
      route: VoiceCallOutputRoute.speaker,
      label: 'Speaker',
      icon: Icons.speaker_phone,
    ),
    if (hasBluetoothOutput)
      const VoiceCallOutputRouteOption(
        route: VoiceCallOutputRoute.bluetooth,
        label: 'Bluetooth',
        icon: Icons.bluetooth_audio,
      ),
  ];
}

PopupMenuItem<VoiceCallOutputRoute> _outputRouteMenuItem({
  required VoiceCallOutputRouteOption option,
  required VoiceCallOutputRoute current,
}) {
  final selected = option.route == current;
  return PopupMenuItem<VoiceCallOutputRoute>(
    value: option.route,
    child: Row(
      children: <Widget>[
        Icon(selected ? Icons.check_circle : option.icon, size: 20),
        const SizedBox(width: 10),
        Text(option.label),
      ],
    ),
  );
}

List<VoiceCallOutputRouteOption> _effectiveOutputRouteOptions(
  List<VoiceCallOutputRouteOption>? options,
) {
  final filtered = (options ?? rainVoiceCallOutputRouteOptions())
      .where(
        (VoiceCallOutputRouteOption option) =>
            !_containsOutputRoute(options, option.route, before: option),
      )
      .toList(growable: false);
  return filtered.isEmpty
      ? rainVoiceCallOutputRouteOptions(hasBluetoothOutput: false)
      : filtered;
}

bool _containsOutputRoute(
  List<VoiceCallOutputRouteOption>? options,
  VoiceCallOutputRoute route, {
  required VoiceCallOutputRouteOption before,
}) {
  if (options == null) {
    return false;
  }
  for (final option in options) {
    if (identical(option, before)) {
      return false;
    }
    if (option.route == route) {
      return true;
    }
  }
  return false;
}

VoiceCallOutputRouteOption _selectedOutputRouteOption(
  List<VoiceCallOutputRouteOption> options,
  VoiceCallOutputRoute route,
) {
  for (final option in options) {
    if (option.route == route) {
      return option;
    }
  }
  return options.first;
}

VoiceCallOutputRoute _nextOutputRoute(
  List<VoiceCallOutputRouteOption> options,
  VoiceCallOutputRoute current,
) {
  final currentIndex = options.indexWhere(
    (VoiceCallOutputRouteOption option) => option.route == current,
  );
  if (currentIndex < 0) {
    return options.first.route;
  }
  return options[(currentIndex + 1) % options.length].route;
}

IconData _outputRouteIcon(VoiceCallOutputRoute route) {
  return switch (route) {
    VoiceCallOutputRoute.systemDefault => Icons.volume_up,
    VoiceCallOutputRoute.speaker => Icons.speaker_phone,
    VoiceCallOutputRoute.bluetooth => Icons.bluetooth_audio,
  };
}

IconData rainVoiceCallIcon(VoiceCallState state) {
  return switch (state.phase) {
    VoiceCallPhase.failed => Icons.error_outline,
    VoiceCallPhase.incomingRinging => Icons.call_received,
    VoiceCallPhase.outgoingRinging => Icons.call_made,
    VoiceCallPhase.active => _activeCallIcon(state),
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia ||
    VoiceCallPhase.ending ||
    VoiceCallPhase.idle => Icons.call_outlined,
  };
}

IconData _activeCallIcon(VoiceCallState state) {
  if (state.isVideo) {
    return state.isCameraMuted ? Icons.videocam_off : Icons.videocam;
  }
  if (state.isDeafened) {
    return Icons.volume_off;
  }
  if (state.isMuted) {
    return Icons.mic_off;
  }
  return Icons.call;
}

Color rainVoiceCallAccent(BuildContext context, VoiceCallState state) {
  final scheme = Theme.of(context).colorScheme;
  return switch (state.phase) {
    VoiceCallPhase.failed => scheme.error,
    VoiceCallPhase.active => const Color(0xFF2DD4A3),
    VoiceCallPhase.incomingRinging ||
    VoiceCallPhase.outgoingRinging => scheme.tertiary,
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia ||
    VoiceCallPhase.ending ||
    VoiceCallPhase.idle => scheme.primary,
  };
}

Color rainVoiceCallHaloColor(BuildContext context, VoiceCallState state) {
  final scheme = Theme.of(context).colorScheme;
  return switch (state.phase) {
    VoiceCallPhase.active => RainColors.peerMint,
    VoiceCallPhase.incomingRinging ||
    VoiceCallPhase.outgoingRinging ||
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia => RainColors.mistCyan,
    VoiceCallPhase.failed => scheme.error,
    VoiceCallPhase.ending || VoiceCallPhase.idle => scheme.primary,
  };
}

bool rainVoiceCallShowsSignalHalo(VoiceCallState state) {
  return switch (state.phase) {
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia ||
    VoiceCallPhase.incomingRinging ||
    VoiceCallPhase.outgoingRinging ||
    VoiceCallPhase.active => true,
    VoiceCallPhase.failed ||
    VoiceCallPhase.ending ||
    VoiceCallPhase.idle => false,
  };
}

String rainVoiceCallTitle(VoiceCallState state, String displayName) {
  final callKind = state.isVideo ? 'video call' : 'voice call';
  return switch (state.phase) {
    VoiceCallPhase.incomingRinging => '$displayName is calling',
    VoiceCallPhase.outgoingRinging => 'Calling $displayName',
    VoiceCallPhase.active => '${_capitalize(callKind)} with $displayName',
    VoiceCallPhase.failed => '${_capitalize(callKind)} failed',
    VoiceCallPhase.ending => 'Ending $callKind',
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia => 'Connecting $callKind',
    VoiceCallPhase.idle => _capitalize(callKind),
  };
}

String rainVoiceCallDetail(VoiceCallState state, int nowMs) {
  if (state.phase == VoiceCallPhase.active && state.startedAt != null) {
    final elapsed = Duration(milliseconds: nowMs - state.startedAt!);
    final labels = <String>[rainFormatVoiceElapsed(elapsed)];
    if (state.isMuted) {
      labels.add('Muted');
    }
    if (state.isDeafened) {
      labels.add('Deafened');
    }
    if (state.isRemoteMuted) {
      labels.add('Peer muted');
    }
    if (state.isVideo && state.isCameraMuted) {
      labels.add('Camera off');
    }
    if (state.isVideo && state.isRemoteCameraMuted) {
      labels.add('Peer camera off');
    }
    if (state.outputRoute != VoiceCallOutputRoute.systemDefault) {
      labels.add(_outputRouteLabel(state.outputRoute));
    }
    final warning = state.outputRouteWarning?.trim();
    if (warning != null && warning.isNotEmpty) {
      labels.add(warning);
    }
    return labels.join(' / ');
  }
  return switch (state.phase) {
    VoiceCallPhase.connectingPeer => 'Connecting peer link.',
    VoiceCallPhase.outgoingRinging => 'Ringing.',
    VoiceCallPhase.incomingRinging =>
      state.isVideo ? 'Incoming video call.' : 'Incoming voice call.',
    VoiceCallPhase.connectingMedia =>
      state.isVideo
          ? 'Connecting camera and microphone.'
          : 'Connecting microphone audio.',
    VoiceCallPhase.ending =>
      state.isVideo
          ? 'Closing camera and microphone.'
          : 'Closing microphone audio.',
    VoiceCallPhase.failed => rainVoiceCallFailureDetail(state),
    VoiceCallPhase.idle => '',
    VoiceCallPhase.active => 'Connected.',
  };
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  return value[0].toUpperCase() + value.substring(1);
}

String _outputRouteLabel(VoiceCallOutputRoute route) {
  return switch (route) {
    VoiceCallOutputRoute.systemDefault => 'Default audio',
    VoiceCallOutputRoute.speaker => 'Speaker',
    VoiceCallOutputRoute.bluetooth => 'Bluetooth',
  };
}

String rainVoiceCallFailureDetail(VoiceCallState state) {
  return switch (state.failureReason) {
    VoiceCallFailureReason.microphoneDenied =>
      'Microphone permission required.',
    VoiceCallFailureReason.remoteMicrophoneDenied =>
      'Peer microphone permission required.',
    VoiceCallFailureReason.cameraDenied => 'Camera permission required.',
    VoiceCallFailureReason.remoteCameraDenied =>
      'Peer camera permission required.',
    VoiceCallFailureReason.peerBusy => 'Peer is busy.',
    VoiceCallFailureReason.fileTransferActive =>
      'Finish the active file transfer first.',
    VoiceCallFailureReason.rejected => 'Call declined.',
    VoiceCallFailureReason.networkLost =>
      'Network connection lost. Call ended.',
    VoiceCallFailureReason.signalingFailed => 'Call setup failed. Try again.',
    VoiceCallFailureReason.expired ||
    VoiceCallFailureReason.ringingTimeout => 'Call timed out.',
    VoiceCallFailureReason.mediaIceTimeout ||
    VoiceCallFailureReason.mediaNoRemoteAudio ||
    VoiceCallFailureReason.mediaConnectionFailed =>
      'Call media could not connect. Try again.',
    VoiceCallFailureReason.videoRendererFailed ||
    VoiceCallFailureReason.videoFirstFrameTimeout =>
      'Video could not connect. Try again.',
    null => rainSanitizeVoiceCallFailureDetail(state.detail),
  };
}

bool rainVoiceCallCanRetry(VoiceCallState state) {
  if (!state.isOutgoing) {
    return false;
  }
  return switch (state.failureReason) {
    VoiceCallFailureReason.microphoneDenied ||
    VoiceCallFailureReason.cameraDenied ||
    VoiceCallFailureReason.peerBusy ||
    VoiceCallFailureReason.signalingFailed ||
    VoiceCallFailureReason.expired ||
    VoiceCallFailureReason.ringingTimeout ||
    VoiceCallFailureReason.mediaConnectionFailed ||
    VoiceCallFailureReason.mediaIceTimeout ||
    VoiceCallFailureReason.mediaNoRemoteAudio ||
    VoiceCallFailureReason.videoRendererFailed ||
    VoiceCallFailureReason.videoFirstFrameTimeout => true,
    VoiceCallFailureReason.remoteMicrophoneDenied ||
    VoiceCallFailureReason.remoteCameraDenied ||
    VoiceCallFailureReason.fileTransferActive ||
    VoiceCallFailureReason.rejected ||
    VoiceCallFailureReason.networkLost ||
    null => false,
  };
}

String rainSanitizeVoiceCallFailureDetail(String? detail) {
  final raw = detail?.trim();
  if (raw == null || raw.isEmpty) {
    return 'Call failed.';
  }
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  var message = raw;
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      message = raw.substring(prefix.length).trim();
      break;
    }
  }
  final normalized = message.toLowerCase();
  if (normalized.contains('microphone') &&
      (normalized.contains('permission') || normalized.contains('denied'))) {
    return 'Microphone permission required.';
  }
  if (normalized.contains('camera') &&
      (normalized.contains('permission') ||
          normalized.contains('denied') ||
          normalized.contains('notallowed'))) {
    return 'Camera permission required.';
  }
  if (normalized.contains('cameraaccess') ||
      normalized.contains('camera_error') ||
      normalized.contains('failed to open camera') ||
      normalized.contains('could not start camera')) {
    return 'Camera could not start. Try again.';
  }
  if (normalized.contains('peer is busy') ||
      normalized == 'busy.' ||
      normalized.contains('active voice call already exists') ||
      normalized.contains('activevoicepairs') ||
      normalized.contains('active voice pair')) {
    return 'Peer is busy.';
  }
  if (normalized.contains('active file transfer')) {
    return 'Finish the active file transfer first.';
  }
  if (normalized.contains('finish the call before') ||
      normalized == 'finish the call first.') {
    return 'Finish the call before sending files.';
  }
  if (normalized == 'rejected.' ||
      normalized.contains('call declined') ||
      normalized.contains('call rejected')) {
    return 'Call declined.';
  }
  if (normalized.contains('network connection lost') ||
      normalized.contains('network lost') ||
      normalized.contains('internet connection') ||
      normalized.contains('network is unavailable') ||
      normalized.contains('network unavailable')) {
    return 'Network connection lost. Call ended.';
  }
  if (normalized.contains('timed out') ||
      normalized.contains('voice call expired') ||
      normalized.contains('call room expired')) {
    return 'Call timed out.';
  }
  if (normalized.contains('voice signaling') ||
      normalized.contains('firebase') ||
      normalized.contains('unknown voice call') ||
      normalized.contains('voice call already exists') ||
      normalized.contains('already ended') ||
      normalized.contains('permission-denied') ||
      normalized.contains('database')) {
    return 'Call setup failed. Try again.';
  }
  if (normalized.contains('ice timeout')) {
    return 'Call media could not connect. Try again.';
  }
  if (normalized.contains('no remote audio')) {
    return 'Call media could not connect. Try again.';
  }
  if (normalized.contains('rtcrtptransceiver') ||
      normalized.contains('setdirection') ||
      normalized.contains('setremotedescription') ||
      normalized.contains('peerconnectionsetremotedescription') ||
      normalized.contains('m-line') ||
      normalized.contains('peer connection changed while')) {
    return 'Call media could not connect. Try again.';
  }
  return message;
}

String rainFormatVoiceElapsed(Duration elapsed) {
  final seconds = elapsed.inSeconds.clamp(0, 86400).toInt();
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final remainingSeconds = seconds % 60;
  final secondsLabel = remainingSeconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$secondsLabel';
  }
  return '$minutes:$secondsLabel';
}
