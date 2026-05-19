import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rain/application/connection_command/connection_command_models.dart';

class ConnectionDiagnosticItem {
  const ConnectionDiagnosticItem({required this.label, required this.value});

  final String label;
  final String? value;

  String get displayValue {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? 'Unknown' : trimmed;
  }
}

class ConnectionCommandCenter extends StatefulWidget {
  const ConnectionCommandCenter({
    super.key,
    required this.statusLabel,
    required this.statusDetail,
    required this.statusColor,
    required this.statusIcon,
    required this.timeline,
    required this.initialPolicy,
    required this.diagnosticItems,
    required this.canConnect,
    required this.canRetry,
    required this.canCancel,
    required this.canDisconnect,
    required this.canRunRelayProbe,
    required this.onClose,
    required this.onConnect,
    required this.onRetry,
    required this.onCancel,
    required this.onDisconnect,
    required this.onRunRelayProbe,
  });

  final String statusLabel;
  final String statusDetail;
  final Color statusColor;
  final IconData statusIcon;
  final ConnectionTimeline? timeline;
  final ConnectionPolicy initialPolicy;
  final List<ConnectionDiagnosticItem> diagnosticItems;
  final bool canConnect;
  final bool canRetry;
  final bool canCancel;
  final bool canDisconnect;
  final bool canRunRelayProbe;
  final VoidCallback onClose;
  final ValueChanged<ConnectionPolicy> onConnect;
  final ValueChanged<ConnectionPolicy> onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDisconnect;
  final VoidCallback onRunRelayProbe;

  @override
  State<ConnectionCommandCenter> createState() =>
      _ConnectionCommandCenterState();
}

class _ConnectionCommandCenterState extends State<ConnectionCommandCenter> {
  late ConnectionMode _selectedMode = widget.initialPolicy.mode;
  late bool _rememberForSession = widget.initialPolicy.rememberForSession;

  @override
  void didUpdateWidget(covariant ConnectionCommandCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPolicy != widget.initialPolicy) {
      _selectedMode = widget.initialPolicy.mode;
      _rememberForSession = widget.initialPolicy.rememberForSession;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final panelWidth = size.width <= 340 ? size.width : size.width - 24;
    final panelHeight = math.min(size.height * 0.88, 640.0);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: Center(
        child: SizedBox(
          width: math.min(panelWidth, 540),
          height: math.max(360, panelHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.65),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                _CommandHeader(
                  label: widget.statusLabel,
                  color: widget.statusColor,
                  icon: widget.statusIcon,
                  onClose: widget.onClose,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _SectionTitle('Overview'),
                        _OverviewBlock(
                          statusLabel: widget.statusLabel,
                          statusDetail: widget.statusDetail,
                          statusColor: widget.statusColor,
                          timeline: widget.timeline,
                        ),
                        const SizedBox(height: 18),
                        _SectionTitle('Mode Selector'),
                        const SizedBox(height: 10),
                        _ModeSelector(
                          selectedMode: _selectedMode,
                          onSelected: (ConnectionMode mode) {
                            setState(() => _selectedMode = mode);
                          },
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _rememberForSession,
                          onChanged: (bool? value) {
                            setState(
                              () => _rememberForSession = value ?? false,
                            );
                          },
                          title: const Text('Remember for this session'),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 12),
                        _SectionTitle('Timeline'),
                        const SizedBox(height: 10),
                        _TimelineBlock(timeline: widget.timeline),
                        const SizedBox(height: 12),
                        _AdvancedDiagnostics(items: widget.diagnosticItems),
                      ],
                    ),
                  ),
                ),
                _ControlsFooter(
                  canConnect: widget.canConnect,
                  canRetry: widget.canRetry,
                  canCancel: widget.canCancel,
                  canDisconnect: widget.canDisconnect,
                  canRunRelayProbe: widget.canRunRelayProbe,
                  onConnect: () => widget.onConnect(_currentPolicy()),
                  onRetry: () => widget.onRetry(_currentPolicy()),
                  onCancel: widget.onCancel,
                  onDisconnect: widget.onDisconnect,
                  onRunRelayProbe: widget.onRunRelayProbe,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ConnectionPolicy _currentPolicy() {
    return ConnectionPolicy(
      mode: _selectedMode,
      rememberForSession: _rememberForSession,
    );
  }
}

class _CommandHeader extends StatelessWidget {
  const _CommandHeader({
    required this.label,
    required this.color,
    required this.icon,
    required this.onClose,
  });

  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 10, 8),
      child: Row(
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Command Center',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _OverviewBlock extends StatelessWidget {
  const _OverviewBlock({
    required this.statusLabel,
    required this.statusDetail,
    required this.statusColor,
    required this.timeline,
  });

  final String statusLabel;
  final String statusDetail;
  final Color statusColor;
  final ConnectionTimeline? timeline;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            statusLabel,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            statusDetail,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.74),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Attempt: ${timeline?.attemptId ?? 'Unknown'}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.selectedMode, required this.onSelected});

  final ConnectionMode selectedMode;
  final ValueChanged<ConnectionMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: ConnectionMode.values
          .map((ConnectionMode mode) {
            final selected = mode == selectedMode;
            return ChoiceChip(
              label: Text(_modeLabel(mode)),
              selected: selected,
              onSelected: (_) => onSelected(mode),
              showCheckmark: false,
            );
          })
          .toList(growable: false),
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({required this.timeline});

  final ConnectionTimeline? timeline;

  @override
  Widget build(BuildContext context) {
    final steps = timeline?.steps.reversed.toList(growable: false);
    if (steps == null || steps.isEmpty) {
      return const Text('No connection attempts yet.');
    }
    return Column(
      children: steps
          .map((ConnectionAttemptStep step) {
            return _TimelineRow(step: step);
          })
          .toList(growable: false),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.step});

  final ConnectionAttemptStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(_stepIcon(step.state), size: 18, color: _stepColor(step.state)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_layerLabel(step.layer)} - ${_stateLabel(step.state)}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  step.userMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.66),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedDiagnostics extends StatelessWidget {
  const _AdvancedDiagnostics({required this.items});

  final List<ConnectionDiagnosticItem> items;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const _SectionTitle('Advanced Diagnostics'),
      children: <Widget>[
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 132,
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.displayValue,
                    overflow: TextOverflow.visible,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ControlsFooter extends StatelessWidget {
  const _ControlsFooter({
    required this.canConnect,
    required this.canRetry,
    required this.canCancel,
    required this.canDisconnect,
    required this.canRunRelayProbe,
    required this.onConnect,
    required this.onRetry,
    required this.onCancel,
    required this.onDisconnect,
    required this.onRunRelayProbe,
  });

  final bool canConnect;
  final bool canRetry;
  final bool canCancel;
  final bool canDisconnect;
  final bool canRunRelayProbe;
  final VoidCallback onConnect;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDisconnect;
  final VoidCallback onRunRelayProbe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.68),
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'Controls',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: canConnect ? onConnect : null,
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  label: const Text('Connect'),
                ),
                OutlinedButton.icon(
                  onPressed: canRetry ? onRetry : null,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
                OutlinedButton.icon(
                  onPressed: canCancel ? onCancel : null,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancel'),
                ),
                OutlinedButton.icon(
                  onPressed: canDisconnect ? onDisconnect : null,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Disconnect'),
                ),
                TextButton.icon(
                  onPressed: canRunRelayProbe ? onRunRelayProbe : null,
                  icon: const Icon(Icons.science_outlined, size: 18),
                  label: const Text('Test Relay'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _modeLabel(ConnectionMode mode) {
  return switch (mode) {
    ConnectionMode.auto => 'Auto',
    ConnectionMode.webRtcAuto => 'WebRTC Auto',
    ConnectionMode.webRtcDirectOnly => 'WebRTC Direct',
    ConnectionMode.webRtcRelayOnly => 'WebRTC Relay',
    ConnectionMode.irohFallback => 'Iroh Fallback',
  };
}

String _layerLabel(ConnectionLayer layer) {
  return switch (layer) {
    ConnectionLayer.preflight => 'Preflight',
    ConnectionLayer.webRtcDirect => 'WebRTC Direct',
    ConnectionLayer.webRtcPrimaryRelay => 'Primary Relay',
    ConnectionLayer.webRtcBackupRelay => 'Backup Relay',
    ConnectionLayer.webRtcFullRestart => 'Full Restart',
    ConnectionLayer.iroh => 'Iroh Fallback',
  };
}

String _stateLabel(ConnectionStepState state) {
  return switch (state) {
    ConnectionStepState.pending => 'Pending',
    ConnectionStepState.running => 'Running',
    ConnectionStepState.retrying => 'Retrying',
    ConnectionStepState.succeeded => 'Succeeded',
    ConnectionStepState.failed => 'Failed',
    ConnectionStepState.skipped => 'Skipped',
    ConnectionStepState.canceled => 'Canceled',
  };
}

IconData _stepIcon(ConnectionStepState state) {
  return switch (state) {
    ConnectionStepState.succeeded => Icons.check_circle_outline,
    ConnectionStepState.failed => Icons.error_outline,
    ConnectionStepState.canceled => Icons.cancel_outlined,
    ConnectionStepState.retrying => Icons.refresh,
    ConnectionStepState.running => Icons.sync,
    ConnectionStepState.pending ||
    ConnectionStepState.skipped => Icons.radio_button_unchecked,
  };
}

Color _stepColor(ConnectionStepState state) {
  return switch (state) {
    ConnectionStepState.succeeded => const Color(0xFF2DD4A3),
    ConnectionStepState.failed => const Color(0xFFFF6B6B),
    ConnectionStepState.canceled => const Color(0xFF94A3B8),
    ConnectionStepState.retrying ||
    ConnectionStepState.running => const Color(0xFFFBBF24),
    ConnectionStepState.pending ||
    ConnectionStepState.skipped => const Color(0xFF7DD3FC),
  };
}
