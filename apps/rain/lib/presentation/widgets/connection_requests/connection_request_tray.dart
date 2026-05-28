import 'package:flutter/material.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'connection_request_status_chip.dart';

class ConnectionRequestTray extends StatelessWidget {
  const ConnectionRequestTray({
    super.key,
    required this.surfaces,
    this.onAction,
    this.compact = false,
    this.maxVisible = 3,
  });

  final List<ConnectionRequestSurfaceModel> surfaces;
  final ConnectionRequestActionCallback? onAction;
  final bool compact;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final visibleSurfaces = _collapsedInboundSurfaces(
      surfaces,
    ).take(maxVisible).toList(growable: false);
    if (visibleSurfaces.isEmpty) {
      return const SizedBox.shrink();
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: visibleSurfaces.length == 1
          ? 'Incoming connection request'
          : '${visibleSurfaces.length} incoming connection requests',
      child: DecoratedBox(
        key: const ValueKey<String>('connection-request-inbound-tray'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.02),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final surface in visibleSurfaces) ...<Widget>[
              _InboundConnectionRequestPrompt(
                surface: surface,
                compact: compact,
                onAction: onAction,
              ),
              if (surface != visibleSurfaces.last)
                SizedBox(height: compact ? 8 : 10),
            ],
          ],
        ),
      ),
    );
  }

  List<ConnectionRequestSurfaceModel> _collapsedInboundSurfaces(
    List<ConnectionRequestSurfaceModel> input,
  ) {
    final byPeer = <String, ConnectionRequestSurfaceModel>{};
    for (final surface in input) {
      if (surface.direction != ConnectionRequestDirection.inbound ||
          surface.status.isTerminal) {
        continue;
      }
      final current = byPeer[surface.peerId];
      if (current == null ||
          _surfacePriority(surface) > _surfacePriority(current)) {
        byPeer[surface.peerId] = surface;
      }
    }
    return byPeer.values.toList(growable: false);
  }

  int _surfacePriority(ConnectionRequestSurfaceModel surface) {
    return switch (surface.status) {
      ConnectionRequestStatus.pending => 2,
      ConnectionRequestStatus.seen => 1,
      ConnectionRequestStatus.accepted ||
      ConnectionRequestStatus.rejected ||
      ConnectionRequestStatus.canceled ||
      ConnectionRequestStatus.expired ||
      ConnectionRequestStatus.failed => 0,
    };
  }
}

class _InboundConnectionRequestPrompt extends StatelessWidget {
  const _InboundConnectionRequestPrompt({
    required this.surface,
    required this.compact,
    this.onAction,
  });

  final ConnectionRequestSurfaceModel surface;
  final bool compact;
  final ConnectionRequestActionCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connectAction = _action(ConnectionRequestActionKind.connect);
    final ignoreAction = _action(ConnectionRequestActionKind.ignore);
    final overflowActions = surface.actions
        .where(
          (action) =>
              action.kind == ConnectionRequestActionKind.reject ||
              action.kind == ConnectionRequestActionKind.mute,
        )
        .toList(growable: false);
    final tone = RainColors.mistCyan;

    return RainRippleHaloSurface(
      enabled: true,
      color: tone,
      borderRadius: BorderRadius.circular(22),
      pulseKey: 'inbound:${surface.requestId}:${surface.status.name}',
      pulseOnMount: true,
      child: DecoratedBox(
        key: ValueKey<String>(
          'connection-request-inbound-${surface.requestId}',
        ),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            tone.withValues(alpha: 0.07),
            scheme.surfaceContainerHighest.withValues(alpha: 0.86),
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tone.withValues(alpha: 0.34)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 20,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 14),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final stackActions = compact || constraints.maxWidth < 360;
              final header = _InboundPromptHeader(surface: surface, tone: tone);
              final actions = _InboundPromptActions(
                surface: surface,
                connectAction: connectAction,
                ignoreAction: ignoreAction,
                overflowActions: overflowActions,
                stackActions: stackActions,
                onAction: onAction,
              );
              if (stackActions) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    header,
                    const SizedBox(height: 12),
                    actions,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(child: header),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  ConnectionRequestActionModel? _action(ConnectionRequestActionKind kind) {
    for (final action in surface.actions) {
      if (action.kind == kind) {
        return action;
      }
    }
    return null;
  }
}

class _InboundPromptHeader extends StatelessWidget {
  const _InboundPromptHeader({required this.surface, required this.tone});

  final ConnectionRequestSurfaceModel surface;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox.square(
          dimension: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.hub_outlined, color: tone, size: 21),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                surface.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                surface.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InboundPromptActions extends StatelessWidget {
  const _InboundPromptActions({
    required this.surface,
    required this.connectAction,
    required this.ignoreAction,
    required this.overflowActions,
    required this.stackActions,
    this.onAction,
  });

  final ConnectionRequestSurfaceModel surface;
  final ConnectionRequestActionModel? connectAction;
  final ConnectionRequestActionModel? ignoreAction;
  final List<ConnectionRequestActionModel> overflowActions;
  final bool stackActions;
  final ConnectionRequestActionCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      if (connectAction != null)
        _PromptActionButton(
          surface: surface,
          action: connectAction!,
          primary: true,
          onAction: onAction,
        ),
      if (ignoreAction != null)
        _PromptActionButton(
          surface: surface,
          action: ignoreAction!,
          onAction: onAction,
        ),
      if (overflowActions.isNotEmpty)
        _PromptOverflowButton(
          surface: surface,
          actions: overflowActions,
          onAction: onAction,
        ),
    ];
    if (stackActions) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: children,
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _PromptActionButton extends StatelessWidget {
  const _PromptActionButton({
    required this.surface,
    required this.action,
    required this.onAction,
    this.primary = false,
  });

  final ConnectionRequestSurfaceModel surface;
  final ConnectionRequestActionModel action;
  final ConnectionRequestActionCallback? onAction;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final tooltip =
        action.tooltip ??
        (action.enabled
            ? action.semanticLabel
            : '${action.label} is unavailable for this request.');
    final child = primary
        ? FilledButton.icon(
            key: _key,
            onPressed: action.enabled && onAction != null ? _handle : null,
            icon: const Icon(Icons.hub_outlined, size: 17),
            label: Text(action.label),
            style: FilledButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(44, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          )
        : TextButton(
            key: _key,
            onPressed: action.enabled && onAction != null ? _handle : null,
            style: TextButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              minimumSize: const Size(44, 36),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(action.label),
          );
    return Semantics(
      button: true,
      enabled: action.enabled,
      label: action.enabled ? action.semanticLabel : tooltip,
      child: Tooltip(message: tooltip, child: child),
    );
  }

  ValueKey<String> get _key => ValueKey<String>(
    'connection-request-inbound-action-${surface.requestId}-${action.kind.name}',
  );

  void _handle() {
    onAction!(surface, action);
  }
}

class _PromptOverflowButton extends StatelessWidget {
  const _PromptOverflowButton({
    required this.surface,
    required this.actions,
    this.onAction,
  });

  final ConnectionRequestSurfaceModel surface;
  final List<ConnectionRequestActionModel> actions;
  final ConnectionRequestActionCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ConnectionRequestActionModel>(
      key: ValueKey<String>(
        'connection-request-inbound-overflow-${surface.requestId}',
      ),
      tooltip: 'More connection request actions',
      enabled: onAction != null,
      onSelected: (ConnectionRequestActionModel action) =>
          onAction!(surface, action),
      itemBuilder: (BuildContext context) {
        return <PopupMenuEntry<ConnectionRequestActionModel>>[
          for (final action in actions)
            PopupMenuItem<ConnectionRequestActionModel>(
              value: action,
              enabled: action.enabled,
              child: Row(
                children: <Widget>[
                  Icon(_overflowIcon(action.kind), size: 18),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      _overflowLabel(action),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      icon: const Icon(Icons.more_horiz),
    );
  }

  String _overflowLabel(ConnectionRequestActionModel action) {
    return switch (action.kind) {
      ConnectionRequestActionKind.mute =>
        'Mute requests from ${surface.peerLabel}',
      _ => action.label,
    };
  }

  IconData _overflowIcon(ConnectionRequestActionKind kind) {
    return switch (kind) {
      ConnectionRequestActionKind.reject => Icons.do_not_disturb_on_outlined,
      ConnectionRequestActionKind.mute => Icons.notifications_off_outlined,
      _ => Icons.more_horiz,
    };
  }
}
