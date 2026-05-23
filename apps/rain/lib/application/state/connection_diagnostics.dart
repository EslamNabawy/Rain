import 'package:protocol_brain/protocol_brain.dart';

import '../runtime/connection_attempt_coordinator.dart';
import 'app_state.dart';

class ConnectionDiagnostics {
  const ConnectionDiagnostics({
    required this.label,
    required this.detail,
    required this.route,
    this.phase,
    this.roomId,
    this.isOfferOwner,
    this.retryAttempt = 0,
    this.connectionRetryAttempt = 0,
    this.nextRetryAt,
    this.lastError,
    this.updatedAt,
    this.passiveListenerCount = 0,
    this.passiveListenerLimit = 0,
    this.passiveListenerSkips = 0,
    this.networkRecoveryRequests = 0,
    this.networkRecoveryRuns = 0,
    this.lastInboundOfferPeer,
    this.lastInboundOfferAt,
    this.lastRejectedOfferPeer,
    this.lastRejectedOfferReason,
    this.lastRejectedOfferAt,
    this.isBusy = false,
    this.isConnected = false,
    this.canDisconnect = false,
  });

  final String label;
  final String detail;
  final PeerConnectionRoute route;
  final SessionPhase? phase;
  final String? roomId;
  final bool? isOfferOwner;
  final int retryAttempt;
  final int connectionRetryAttempt;
  final int? nextRetryAt;
  final String? lastError;
  final int? updatedAt;
  final int passiveListenerCount;
  final int passiveListenerLimit;
  final int passiveListenerSkips;
  final int networkRecoveryRequests;
  final int networkRecoveryRuns;
  final String? lastInboundOfferPeer;
  final int? lastInboundOfferAt;
  final String? lastRejectedOfferPeer;
  final String? lastRejectedOfferReason;
  final int? lastRejectedOfferAt;
  final bool isBusy;
  final bool isConnected;
  final bool canDisconnect;

  PeerRouteKind get routeKind => route.kind;
  String? get selectedCandidatePairId => route.selectedCandidatePairId;
  String? get localCandidateType => route.localCandidateType;
  String? get remoteCandidateType => route.remoteCandidateType;
  PeerAddressFamily get addressFamily => route.addressFamily;
  PeerAddressFamily get localAddressFamily => route.localAddressFamily;
  PeerAddressFamily get remoteAddressFamily => route.remoteAddressFamily;
  String? get protocol => route.protocol;
  String? get relayProtocol => route.relayProtocol;
  double? get rtt => route.rtt;
  double? get bitrate => route.bitrate;

  factory ConnectionDiagnostics.fromConnection({
    required bool canChat,
    required bool isPeerOnline,
    required PeerConnectionView connection,
    ConnectionCoordinatorSnapshot? coordinator,
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
        phase: session?.phase,
        roomId: session?.roomId,
        isOfferOwner: session?.isOfferOwner,
        retryAttempt: session?.retryAttempt ?? 0,
        connectionRetryAttempt: coordinator?.retryAttempt ?? 0,
        nextRetryAt: coordinator?.nextRetryAt,
        lastError: lastError,
        updatedAt: updatedAt,
        passiveListenerCount: coordinator?.passiveListenerCount ?? 0,
        passiveListenerLimit: coordinator?.passiveListenerLimit ?? 0,
        passiveListenerSkips: coordinator?.passiveListenerSkips ?? 0,
        networkRecoveryRequests: coordinator?.networkRecoveryRequests ?? 0,
        networkRecoveryRuns: coordinator?.networkRecoveryRuns ?? 0,
        lastInboundOfferPeer: coordinator?.lastInboundOfferPeer,
        lastInboundOfferAt: coordinator?.lastInboundOfferAt,
        lastRejectedOfferPeer: coordinator?.lastRejectedOfferPeer,
        lastRejectedOfferReason: coordinator?.lastRejectedOfferReason,
        lastRejectedOfferAt: coordinator?.lastRejectedOfferAt,
        isBusy: isBusy,
        isConnected: isConnected,
        canDisconnect: canDisconnect,
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
        detail:
            'Presence says this peer is offline. If both apps are open, try Connect.',
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
