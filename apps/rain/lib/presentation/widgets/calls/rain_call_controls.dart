import 'dart:async';

import 'package:flutter/material.dart';

import 'package:rain/application/runtime/media_device_settings.dart';
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
    this.trailingControls = const <Widget>[],
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
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;
  final List<Widget> trailingControls;

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

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 420.0;
        final compact = maxWidth < 390;
        final effectiveCapabilities =
            controlCapabilities ?? state.controlCapabilities;
        final visibleCapabilities = _visibleCapabilitiesForWidth(
          effectiveCapabilities,
          compact: compact,
        );
        final overflowCapabilities = effectiveCapabilities
            .where(
              (CallControlCapability capability) =>
                  !visibleCapabilities.contains(capability),
            )
            .toList(growable: false);
        return Wrap(
          spacing: compact ? 6 : 8,
          runSpacing: compact ? 6 : 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            for (final capability in visibleCapabilities)
              _buildActiveControl(context, capability, compact: compact),
            if (overflowCapabilities.isNotEmpty)
              _buildOverflowControl(
                context,
                overflowCapabilities,
                compact: compact,
              ),
            ...trailingControls,
          ],
        );
      },
    );
  }

  Widget _buildActiveControl(
    BuildContext context,
    CallControlCapability capability, {
    required bool compact,
  }) {
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
      minSize: Size.square(compact ? 42 : 46),
      callSurface: true,
      child: control,
    );
  }

  List<CallControlCapability> _visibleCapabilitiesForWidth(
    List<CallControlCapability> capabilities, {
    required bool compact,
  }) {
    if (!compact || capabilities.length <= 4) {
      return capabilities;
    }
    final visible = <CallControlCapability>[
      if (capabilities.contains(CallControlCapability.microphone))
        CallControlCapability.microphone,
      if (capabilities.contains(CallControlCapability.camera))
        CallControlCapability.camera,
      if (capabilities.contains(CallControlCapability.hangUp))
        CallControlCapability.hangUp,
    ];
    return visible.isEmpty
        ? capabilities.take(3).toList(growable: false)
        : visible;
  }

  Widget _buildOverflowControl(
    BuildContext context,
    List<CallControlCapability> capabilities, {
    required bool compact,
  }) {
    final enabled = state.isActive;
    return RainRippleHaloSurface(
      enabled: enabled,
      borderRadius: const BorderRadius.all(Radius.circular(18)),
      color: rainVoiceCallHaloColor(context, state),
      pulseKey: '${state.callId}:${state.phase}:overflow',
      minSize: Size.square(compact ? 42 : 46),
      callSurface: true,
      child: PopupMenuButton<String>(
        tooltip: 'More call controls',
        enabled: enabled,
        onSelected: _handleOverflowSelection,
        itemBuilder: (BuildContext context) {
          return <PopupMenuEntry<String>>[
            for (final capability in capabilities)
              ..._overflowEntriesForCapability(capability),
          ];
        },
        icon: const Icon(Icons.more_horiz),
      ),
    );
  }

  Iterable<PopupMenuEntry<String>> _overflowEntriesForCapability(
    CallControlCapability capability,
  ) sync* {
    if (capability == CallControlCapability.outputRoute) {
      final options = _effectiveOutputRouteOptions(outputRouteOptions);
      if (options.length < 2 || onSelectOutputRoute == null) {
        return;
      }
      if (options.length <= 2) {
        final selected = _selectedOutputRouteOption(options, state);
        yield PopupMenuItem<String>(
          value: 'output:next',
          child: Row(
            children: <Widget>[
              Icon(selected.icon, size: 20),
              const SizedBox(width: 10),
              const Text('Switch audio output'),
            ],
          ),
        );
        return;
      }
      for (final option in options) {
        final selected = option.target.matches(state);
        yield PopupMenuItem<String>(
          value: 'output:${option.target.key}',
          child: Row(
            children: <Widget>[
              Icon(selected ? Icons.check_circle : option.icon, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(option.label)),
            ],
          ),
        );
      }
      return;
    }
    final visual = rainVoiceCallControlVisual(state, capability);
    yield PopupMenuItem<String>(
      value: capability.name,
      child: Row(
        children: <Widget>[
          Icon(visual.icon, size: 20),
          const SizedBox(width: 10),
          Text(visual.tooltip),
        ],
      ),
    );
  }

  void _handleOverflowSelection(String value) {
    if (value == CallControlCapability.switchCamera.name) {
      onSwitchCamera?.call();
      return;
    }
    if (value == CallControlCapability.deafen.name) {
      onToggleDeafen?.call();
      return;
    }
    if (value == CallControlCapability.camera.name) {
      onToggleCamera?.call();
      return;
    }
    if (value == CallControlCapability.microphone.name) {
      onToggleMute();
      return;
    }
    if (value == CallControlCapability.hangUp.name) {
      onHangUp();
      return;
    }
    if (!value.startsWith('output:') || onSelectOutputRoute == null) {
      return;
    }
    final options = _effectiveOutputRouteOptions(outputRouteOptions);
    if (value == 'output:next') {
      onSelectOutputRoute!(_nextOutputTarget(options, state));
      return;
    }
    final targetKey = value.substring('output:'.length);
    for (final option in options) {
      if (option.target.key == targetKey) {
        onSelectOutputRoute!(option.target);
        return;
      }
    }
  }

  Widget _buildOutputRouteControl({required RainCallControlVisual visual}) {
    final options = _effectiveOutputRouteOptions(outputRouteOptions);
    if (options.length < 2) {
      return const SizedBox.shrink();
    }
    final enabled = state.isActive && onSelectOutputRoute != null;
    final selected = _selectedOutputRouteOption(options, state);
    if (options.length <= 2) {
      return IconButton(
        tooltip: visual.tooltip,
        onPressed: enabled
            ? () => onSelectOutputRoute!(_nextOutputTarget(options, state))
            : null,
        icon: Icon(selected.icon),
      );
    }
    return PopupMenuButton<CallAudioOutputTarget>(
      tooltip: visual.tooltip,
      enabled: enabled,
      onSelected: onSelectOutputRoute,
      itemBuilder: (BuildContext context) {
        return <PopupMenuEntry<CallAudioOutputTarget>>[
          for (final option in options)
            _outputRouteMenuItem(option: option, state: state),
        ];
      },
      icon: Icon(selected.icon),
    );
  }
}

class RainCallControlDock extends StatelessWidget {
  const RainCallControlDock({
    super.key,
    this.dockKey = const ValueKey<String>('rain-call-control-dock'),
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
    this.trailingControls = const <Widget>[],
  });

  final Key dockKey;
  final VoiceCallState state;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onHangUp;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback? onToggleDeafen;
  final VoidCallback? onToggleCamera;
  final VoidCallback? onSwitchCamera;
  final ValueChanged<CallAudioOutputTarget>? onSelectOutputRoute;
  final List<CallControlCapability>? controlCapabilities;
  final List<VoiceCallOutputRouteOption>? outputRouteOptions;
  final List<Widget> trailingControls;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final controls = RainCallControls(
      state: state,
      onAccept: onAccept,
      onReject: onReject,
      onHangUp: onHangUp,
      onRetry: onRetry,
      onToggleMute: onToggleMute,
      onToggleDeafen: onToggleDeafen,
      onToggleCamera: onToggleCamera,
      onSwitchCamera: onSwitchCamera,
      onSelectOutputRoute: onSelectOutputRoute,
      controlCapabilities: controlCapabilities,
      outputRouteOptions: outputRouteOptions,
      trailingControls: trailingControls,
    );
    return Container(
      key: dockKey,
      constraints: BoxConstraints(
        maxWidth: state.isVideo ? 520 : 440,
        minHeight: state.phase == VoiceCallPhase.incomingRinging ? 58 : 58,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child:
          state.phase == VoiceCallPhase.incomingRinging &&
              trailingControls.isEmpty
          ? controls
          : controls,
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
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 320.0;
        final reject = _CallActionButton(
          key: const ValueKey<String>('rain-call-decline-button'),
          semanticsLabel: 'Decline call',
          onPressed: onReject,
          icon: Icons.phone_disabled,
          label: 'Decline',
          tone: _CallActionTone.danger,
        );
        final accept = _CallActionButton(
          key: const ValueKey<String>('rain-call-accept-button'),
          semanticsLabel: 'Answer call',
          onPressed: onAccept,
          icon: Icons.call,
          label: 'Answer',
          tone: _CallActionTone.success,
        );

        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: SizedBox(
            width: width,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    key: const ValueKey<String>('rain-call-reject-button'),
                    height: 58,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: reject,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 58,
                    child: FocusTraversalOrder(
                      order: const NumericFocusOrder(2),
                      child: accept,
                    ),
                  ),
                ),
              ],
            ),
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
    required this.tone,
  });

  final String semanticsLabel;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final _CallActionTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = switch (tone) {
      _CallActionTone.danger => FilledButton.styleFrom(
        backgroundColor: scheme.errorContainer,
        foregroundColor: scheme.onErrorContainer,
      ),
      _CallActionTone.success => FilledButton.styleFrom(
        backgroundColor: RainColors.peerMint,
        foregroundColor: Colors.black,
      ),
    };
    final child = FilledButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon),
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, softWrap: false),
      ),
    );
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: SizedBox(height: 58, child: child),
    );
  }
}

enum _CallActionTone { danger, success }

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
      icon: state.isDeafened ? Icons.hearing_disabled : Icons.hearing,
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
    icon: isFailed ? Icons.close : Icons.phone_disabled,
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
  AudioOutputCapabilityState? capabilities,
  AdaptiveDeviceProfile? profile,
}) {
  if (capabilities != null && profile != null) {
    return _adaptiveOutputRouteOptions(capabilities, profile);
  }
  return <VoiceCallOutputRouteOption>[
    const VoiceCallOutputRouteOption(
      target: CallAudioOutputTarget.systemDefault(),
      label: 'Default',
      icon: Icons.speaker,
    ),
    const VoiceCallOutputRouteOption(
      target: CallAudioOutputTarget.androidSpeakerphone(),
      label: 'Speaker',
      icon: Icons.speaker_phone,
    ),
    if (hasBluetoothOutput)
      const VoiceCallOutputRouteOption(
        target: CallAudioOutputTarget.bluetooth(),
        label: 'Bluetooth',
        icon: Icons.bluetooth_audio,
      ),
  ];
}

List<VoiceCallOutputRouteOption> _adaptiveOutputRouteOptions(
  AudioOutputCapabilityState capabilities,
  AdaptiveDeviceProfile profile,
) {
  final snapshot = AdaptiveMediaCapabilitySnapshot(
    profile: profile,
    videoInput: const VideoInputCapabilityState(devices: <RainMediaDevice>[]),
    audioOutput: capabilities,
  );
  return <VoiceCallOutputRouteOption>[
    for (final target in snapshot.outputTargets)
      VoiceCallOutputRouteOption(
        target: target.target,
        label: target.label,
        icon: _adaptiveOutputTargetIcon(target),
      ),
  ];
}

PopupMenuItem<CallAudioOutputTarget> _outputRouteMenuItem({
  required VoiceCallOutputRouteOption option,
  required VoiceCallState state,
}) {
  final selected = option.target.matches(state);
  return PopupMenuItem<CallAudioOutputTarget>(
    value: option.target,
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
  final source = options ?? rainVoiceCallOutputRouteOptions();
  final filtered = source
      .where(
        (VoiceCallOutputRouteOption option) =>
            !_containsOutputTarget(source, option.target, before: option),
      )
      .toList(growable: false);
  return filtered;
}

bool _containsOutputTarget(
  List<VoiceCallOutputRouteOption> options,
  CallAudioOutputTarget target, {
  required VoiceCallOutputRouteOption before,
}) {
  for (final option in options) {
    if (identical(option, before)) {
      return false;
    }
    if (option.target.key == target.key) {
      return true;
    }
  }
  return false;
}

VoiceCallOutputRouteOption _selectedOutputRouteOption(
  List<VoiceCallOutputRouteOption> options,
  VoiceCallState state,
) {
  for (final option in options) {
    if (option.target.matches(state)) {
      return option;
    }
  }
  for (final option in options) {
    if (option.route == state.outputRoute && !option.target.isDeviceBacked) {
      return option;
    }
  }
  return options.first;
}

CallAudioOutputTarget _nextOutputTarget(
  List<VoiceCallOutputRouteOption> options,
  VoiceCallState state,
) {
  final currentIndex = options.indexWhere(
    (VoiceCallOutputRouteOption option) => option.target.matches(state),
  );
  if (currentIndex < 0) {
    return options.first.target;
  }
  return options[(currentIndex + 1) % options.length].target;
}

IconData _outputRouteIcon(VoiceCallOutputRoute route) {
  return switch (route) {
    VoiceCallOutputRoute.systemDefault => Icons.speaker,
    VoiceCallOutputRoute.speaker => Icons.speaker_phone,
    VoiceCallOutputRoute.bluetooth => Icons.bluetooth_audio,
  };
}

IconData _adaptiveOutputTargetIcon(AdaptiveAudioOutputTarget target) {
  return switch (target.target.kind) {
    CallAudioOutputTargetKind.systemDefault =>
      target.label.toLowerCase().contains('phone')
          ? Icons.phone_in_talk
          : Icons.speaker,
    CallAudioOutputTargetKind.androidSpeakerphone => Icons.speaker_phone,
    CallAudioOutputTargetKind.bluetooth => Icons.bluetooth_audio,
    CallAudioOutputTargetKind.wiredHeadset => Icons.headphones,
    CallAudioOutputTargetKind.desktopDevice =>
      target.device == null ? Icons.speaker : _deviceOutputIcon(target.device!),
  };
}

IconData _deviceOutputIcon(RainMediaDevice device) {
  if (device.isBluetoothAudioOutput) {
    return Icons.bluetooth_audio;
  }
  if (device.isWiredAudioOutput) {
    return Icons.headphones;
  }
  return Icons.speaker;
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
    final outputLabel = state.outputRouteLabel?.trim();
    if (outputLabel != null && outputLabel.isNotEmpty) {
      labels.add(outputLabel);
    } else if (state.outputRoute != VoiceCallOutputRoute.systemDefault) {
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
