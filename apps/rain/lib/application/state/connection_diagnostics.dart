import 'package:protocol_brain/protocol_brain.dart';

import 'app_state.dart';

class ConnectionDiagnostics {
  const ConnectionDiagnostics({
    required this.label,
    required this.detail,
    required this.route,
    required this.transportLabel,
    this.transportDetail,
    this.roomId,
    this.isOfferOwner,
    this.retryAttempt = 0,
    this.lastError,
    this.updatedAt,
    this.isBusy = false,
    this.isConnected = false,
    this.canDisconnect = false,
    this.iceStage,
    this.providerTier,
    this.providerId,
    this.connectAttemptId,
    this.attemptIndex = 0,
  });

  final String label;
  final String detail;
  final PeerConnectionRoute route;
  final String transportLabel;
  final String? transportDetail;
  final String? roomId;
  final bool? isOfferOwner;
  final int retryAttempt;
  final String? lastError;
  final int? updatedAt;
  final bool isBusy;
  final bool isConnected;
  final bool canDisconnect;
  final IceAttemptStage? iceStage;
  final IceProviderTier? providerTier;
  final String? providerId;
  final String? connectAttemptId;
  final int attemptIndex;

  PeerRouteKind get routeKind => route.kind;
  String? get selectedCandidatePairId => route.selectedCandidatePairId;
  String? get localCandidateType => route.localCandidateType;
  String? get remoteCandidateType => route.remoteCandidateType;
  String? get protocol => route.protocol;
  String? get relayProtocol => route.relayProtocol;
  double? get rtt => route.rtt;
  double? get bitrate => route.bitrate;

  factory ConnectionDiagnostics.fromConnection({
    required bool canChat,
    required bool isPeerOnline,
    required PeerConnectionView connection,
  }) {
    final session = connection.session;
    final baseRoute = session?.route ?? const PeerConnectionRoute.unknown();
    final safeRoute = session?.state == SessionState.connected
        ? baseRoute
        : PeerConnectionRoute.unknown(
            updatedAt: baseRoute.updatedAt ?? session?.updatedAt,
          );
    final updatedAt =
        safeRoute.updatedAt ?? session?.updatedAt ?? connection.updatedAt;
    final transportLabel = _transportLabel(session?.connectionType);
    final transportDetail = _transportDetail(session?.connectionType);
    final sessionError = session?.error?.trim();
    final lastError =
        _formatConnectionError(connection.error) ??
        (sessionError == null || sessionError.isEmpty ? null : sessionError);

    ConnectionDiagnostics build({
      required String label,
      required String detail,
      required PeerConnectionRoute route,
      bool isBusy = false,
      bool isConnected = false,
      bool canDisconnect = false,
    }) {
      return ConnectionDiagnostics(
        label: label,
        detail: detail,
        route: route,
        transportLabel: transportLabel,
        transportDetail: transportDetail,
        roomId: session?.roomId,
        isOfferOwner: session?.isOfferOwner,
        retryAttempt: session?.retryAttempt ?? 0,
        lastError: lastError,
        updatedAt: updatedAt,
        isBusy: isBusy,
        isConnected: isConnected,
        canDisconnect: canDisconnect,
        iceStage: session?.iceStage,
        providerTier: session?.providerTier,
        providerId: session?.providerId,
        connectAttemptId: session?.connectAttemptId,
        attemptIndex: session?.attemptIndex ?? 0,
      );
    }

    if (!canChat) {
      return build(
        label: 'Unavailable',
        detail: 'Only accepted friends can chat.',
        route: const PeerConnectionRoute.unknown(),
      );
    }

    if (connection.disconnecting) {
      return build(
        label: 'Disconnecting',
        detail: 'Closing peer session.',
        route: safeRoute,
        isBusy: true,
        canDisconnect: true,
      );
    }

    if (connection.manualIntent == ManualConnectionIntent.manualDisconnected) {
      return build(
        label: 'Disconnected',
        detail: 'Manual disconnect. Press Connect to open the peer lane again.',
        route: const PeerConnectionRoute.unknown(),
      );
    }

    switch (session?.state) {
      case SessionState.connected:
        return switch (baseRoute.kind) {
          PeerRouteKind.direct => build(
            label: 'Direct',
            detail: connection.localDetail ?? session!.detail,
            route: baseRoute,
            isConnected: true,
            canDisconnect: true,
          ),
          PeerRouteKind.relay => build(
            label: 'Relay',
            detail: connection.localDetail ?? session!.detail,
            route: baseRoute,
            isConnected: true,
            canDisconnect: true,
          ),
          PeerRouteKind.unknown => build(
            label: 'Connecting',
            detail: 'Detecting route...',
            route: baseRoute,
            isBusy: true,
            isConnected: true,
            canDisconnect: true,
          ),
        };
      case SessionState.failed:
        return build(
          label: 'Failed',
          detail: lastError ?? connection.localDetail ?? session!.detail,
          route: safeRoute,
        );
      case SessionState.reconnecting:
        return build(
          label: 'Recovering',
          detail: connection.localDetail ?? session!.detail,
          route: safeRoute,
          isBusy: true,
          canDisconnect: true,
        );
      case SessionState.connecting:
        return build(
          label: 'Connecting',
          detail: connection.localDetail ?? session!.detail,
          route: safeRoute,
          isBusy: true,
          canDisconnect: true,
        );
      case null:
        break;
    }

    if (connection.actionBusy) {
      return build(
        label: 'Connecting',
        detail: connection.localDetail ?? 'Starting peer connection.',
        route: safeRoute,
        isBusy: true,
      );
    }
    if (lastError != null ||
        connection.manualIntent == ManualConnectionIntent.failed) {
      return build(
        label: 'Failed',
        detail: lastError ?? 'Peer connection failed.',
        route: safeRoute,
      );
    }
    if (!isPeerOnline) {
      return build(
        label: 'Offline',
        detail: 'Peer is offline. Keep both apps open.',
        route: const PeerConnectionRoute.unknown(),
      );
    }
    return build(
      label: 'Ready',
      detail: 'Peer is online. Open the peer lane.',
      route: const PeerConnectionRoute.unknown(),
    );
  }
}

String? _formatConnectionError(Object? error) {
  final raw = error?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }
  }
  return raw;
}

String _transportLabel(ConnectionType? connectionType) {
  return switch (connectionType) {
    ConnectionType.signaling => 'WebRTC',
    ConnectionType.iroh => 'Iroh',
    null => 'None',
  };
}

String? _transportDetail(ConnectionType? connectionType) {
  return switch (connectionType) {
    ConnectionType.signaling => 'WebRTC data channels',
    ConnectionType.iroh => 'Iroh QUIC fallback',
    null => null,
  };
}
