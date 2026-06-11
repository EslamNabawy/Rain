/// # connection_diagnostics.dart
///
/// [ConnectionDiagnostics] aggregates peer connection status into a single
/// UI-facing model: status kind (offline/ready/connecting/connected/etc.),
/// retry attempt counts, room metadata, passive listener stats, and
/// network-recovery counters for display in the connection diagnostics panel.
///
/// **Key types:** [ConnectionDiagnostics], [PeerConnectionUiStatusKind]
///
/// **Depends on:** protocol_brain, connection attempt coordinator, voice call state

import 'package:protocol_brain/protocol_brain.dart';

import '../runtime/connection_attempt_coordinator.dart';
import '../runtime/voice_call_state.dart';
import 'app_state.dart';
import 'peer_connectivity_snapshot.dart';

enum PeerConnectionUiStatusKind {
  unavailable,
  offline,
  ready,
  connecting,
  connected,
  dataLaneOnly,
  recovering,
  failed,
  disconnecting,
  manuallyDisconnected,
  outOfSync,
}

class ConnectionDiagnostics {
  const ConnectionDiagnostics({
    required this.statusKind,
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
    this.canSendData = false,
    this.canDisconnect = false,
  });

  final PeerConnectionUiStatusKind statusKind;
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
  final bool canSendData;
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
    PeerConnectivitySnapshot? snapshot,
    VoiceCallState? voiceCall,
  }) {
    final session = connection.session;
    final baseRoute =
        session?.route ??
        snapshot?.connectionRoute ??
        const PeerConnectionRoute.unknown();
    final effectiveSessionState = session?.state ?? snapshot?.sessionState;
    final safeRoute = effectiveSessionState == SessionState.connected
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
      required PeerConnectionUiStatusKind statusKind,
      required String label,
      required String detail,
      required PeerConnectionRoute route,
      bool isBusy = false,
      bool isConnected = false,
      bool canSendData = false,
      bool canDisconnect = false,
    }) {
      return ConnectionDiagnostics(
        statusKind: statusKind,
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
        canSendData: canSendData,
        canDisconnect: canDisconnect,
      );
    }

    if (!canChat) {
      return build(
        statusKind: PeerConnectionUiStatusKind.unavailable,
        label: 'Unavailable',
        detail: 'Only accepted friends can chat.',
        route: const PeerConnectionRoute.unknown(),
      );
    }

    final callStatus = _statusFromCallOverlay(voiceCall, connection.peerId);
    if (callStatus?.statusKind == PeerConnectionUiStatusKind.failed) {
      return build(
        statusKind: callStatus!.statusKind,
        label: callStatus.label,
        detail: callStatus.detail,
        route: safeRoute,
        isBusy: callStatus.isBusy,
        canSendData:
            snapshot?.canSendData ?? session?.state == SessionState.connected,
        canDisconnect:
            snapshot?.hasActiveSession ??
            session?.state == SessionState.connected,
      );
    }

    if (session?.state == SessionState.failed) {
      return build(
        statusKind: PeerConnectionUiStatusKind.failed,
        label: 'Failed',
        detail: lastError ?? connection.localDetail ?? session!.detail,
        route: safeRoute,
      );
    }

    if (connection.manualIntent == ManualConnectionIntent.manualDisconnected ||
        snapshot?.manualDisconnected == true) {
      return build(
        statusKind: PeerConnectionUiStatusKind.manuallyDisconnected,
        label: 'Disconnected',
        detail: 'Manual disconnect. Press Connect to open the peer lane again.',
        route: const PeerConnectionRoute.unknown(),
      );
    }

    if (callStatus != null) {
      return build(
        statusKind: callStatus.statusKind,
        label: callStatus.label,
        detail: callStatus.detail,
        route: safeRoute,
        isBusy: callStatus.isBusy,
        canSendData:
            snapshot?.canSendData ?? session?.state == SessionState.connected,
        canDisconnect:
            snapshot?.hasActiveSession ??
            session?.state == SessionState.connected,
      );
    }

    if (session?.state == SessionState.reconnecting) {
      return build(
        statusKind: PeerConnectionUiStatusKind.recovering,
        label: 'Recovering',
        detail: connection.localDetail ?? session!.detail,
        route: safeRoute,
        isBusy: true,
        canDisconnect: true,
      );
    }

    if (snapshot != null) {
      if (snapshot.sessionSuperseded) {
        return build(
          statusKind: PeerConnectionUiStatusKind.outOfSync,
          label: 'Out of sync',
          detail: 'Peer session changed. Reopening data lane.',
          route: safeRoute,
          isBusy: true,
          canDisconnect: true,
        );
      }
      if (snapshot.hasActiveSession && !snapshot.isReachable) {
        return build(
          statusKind: PeerConnectionUiStatusKind.disconnecting,
          label: 'Disconnecting',
          detail: 'Closing peer session.',
          route: safeRoute,
          isBusy: true,
          canDisconnect: true,
        );
      }
      if (snapshot.isConnectedWithStalePresence) {
        return build(
          statusKind: PeerConnectionUiStatusKind.dataLaneOnly,
          label: 'Data lane only',
          detail: 'Messages can send, but peer presence is stale.',
          route: baseRoute,
          canSendData: snapshot.canSendData,
          canDisconnect: true,
        );
      }
      if (snapshot.isConnected) {
        return build(
          statusKind: PeerConnectionUiStatusKind.connected,
          label: 'Connected',
          detail:
              connection.localDetail ??
              session?.detail ??
              'Encrypted peer lane is open.',
          route: baseRoute,
          isConnected: true,
          canSendData: snapshot.canSendData,
          canDisconnect: true,
        );
      }
    }

    if (connection.disconnecting) {
      return build(
        statusKind: PeerConnectionUiStatusKind.disconnecting,
        label: 'Disconnecting',
        detail: 'Closing peer session.',
        route: safeRoute,
        isBusy: true,
        canDisconnect: true,
      );
    }

    switch (session?.state) {
      case SessionState.connected:
        if (snapshot != null && !snapshot.hasFreshOnlinePresence) {
          return build(
            statusKind: PeerConnectionUiStatusKind.dataLaneOnly,
            label: 'Data lane only',
            detail: 'Messages can send, but peer presence is stale.',
            route: baseRoute,
            canSendData: snapshot.canSendData,
            canDisconnect: true,
          );
        }
        return switch (baseRoute.kind) {
          PeerRouteKind.direct => build(
            statusKind: PeerConnectionUiStatusKind.connected,
            label: 'Direct',
            detail: connection.localDetail ?? session!.detail,
            route: baseRoute,
            isConnected: true,
            canSendData: snapshot?.canSendData ?? true,
            canDisconnect: true,
          ),
          PeerRouteKind.relay => build(
            statusKind: PeerConnectionUiStatusKind.connected,
            label: 'Relay',
            detail: connection.localDetail ?? session!.detail,
            route: baseRoute,
            isConnected: true,
            canSendData: snapshot?.canSendData ?? true,
            canDisconnect: true,
          ),
          PeerRouteKind.unknown => build(
            statusKind: PeerConnectionUiStatusKind.connecting,
            label: 'Connecting',
            detail: 'Detecting route...',
            route: baseRoute,
            isBusy: true,
            canSendData: snapshot?.canSendData ?? true,
            canDisconnect: true,
          ),
        };
      case SessionState.failed:
        return build(
          statusKind: PeerConnectionUiStatusKind.failed,
          label: 'Failed',
          detail: lastError ?? connection.localDetail ?? session!.detail,
          route: safeRoute,
        );
      case SessionState.reconnecting:
        return build(
          statusKind: PeerConnectionUiStatusKind.recovering,
          label: 'Recovering',
          detail: connection.localDetail ?? session!.detail,
          route: safeRoute,
          isBusy: true,
          canDisconnect: true,
        );
      case SessionState.connecting:
        return build(
          statusKind: PeerConnectionUiStatusKind.connecting,
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
        statusKind: PeerConnectionUiStatusKind.connecting,
        label: 'Connecting',
        detail: connection.localDetail ?? 'Starting peer connection.',
        route: safeRoute,
        isBusy: true,
      );
    }
    if (lastError != null ||
        connection.manualIntent == ManualConnectionIntent.failed) {
      return build(
        statusKind: PeerConnectionUiStatusKind.failed,
        label: 'Failed',
        detail: lastError ?? 'Peer connection failed.',
        route: safeRoute,
      );
    }
    if (connection.localDetail == 'Disconnected.') {
      return build(
        statusKind: isPeerOnline
            ? PeerConnectionUiStatusKind.ready
            : PeerConnectionUiStatusKind.offline,
        label: isPeerOnline ? 'Ready' : 'Offline',
        detail: isPeerOnline
            ? 'Peer link closed. Press Connect to open it again.'
            : 'Peer went offline or closed Rain. Connect is available when they are online again.',
        route: const PeerConnectionRoute.unknown(),
      );
    }
    if (!isPeerOnline) {
      return build(
        statusKind: PeerConnectionUiStatusKind.offline,
        label: 'Offline',
        detail:
            'Presence says this peer is offline. Keep both apps open, then try again.',
        route: const PeerConnectionRoute.unknown(),
      );
    }
    return build(
      statusKind: PeerConnectionUiStatusKind.ready,
      label: 'Ready',
      detail: 'Peer is online. Open the peer lane.',
      route: const PeerConnectionRoute.unknown(),
    );
  }
}

class _CallConnectionProjection {
  const _CallConnectionProjection({
    required this.statusKind,
    required this.label,
    required this.detail,
    this.isBusy = false,
  });

  final PeerConnectionUiStatusKind statusKind;
  final String label;
  final String detail;
  final bool isBusy;
}

_CallConnectionProjection? _statusFromCallOverlay(
  VoiceCallState? call,
  String peerId,
) {
  if (call == null || !call.hasCall || call.peerId != peerId) {
    return null;
  }
  if (call.phase == VoiceCallPhase.failed) {
    return _CallConnectionProjection(
      statusKind: PeerConnectionUiStatusKind.failed,
      label: 'Failed',
      detail: call.detail ?? 'Call failed.',
    );
  }
  if (call.mediaReconnecting) {
    return _CallConnectionProjection(
      statusKind: PeerConnectionUiStatusKind.recovering,
      label: 'Recovering',
      detail: call.detail ?? 'Call media is recovering.',
      isBusy: true,
    );
  }
  if (call.phase == VoiceCallPhase.ending) {
    return _CallConnectionProjection(
      statusKind: PeerConnectionUiStatusKind.disconnecting,
      label: 'Disconnecting',
      detail: call.detail ?? 'Ending call.',
      isBusy: true,
    );
  }
  return null;
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
