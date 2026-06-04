import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

/// Authoritative snapshot of a peer's connectivity state.
///
/// This combines data-session state, presence freshness, and manual
/// disconnect intent into a single source of truth for UI gates.
/// It is derived from the runtime and consumed by providers, not
/// independently owned by widgets.
class PeerConnectivitySnapshot {
  const PeerConnectivitySnapshot({
    required this.peerId,
    this.sessionState,
    this.sessionId,
    this.presenceOnline,
    required this.presenceFresh,
    this.backendSessionId,
    this.presenceAgeMs,
    this.manualDisconnected = false,
    this.lastDataEventAt,
    this.connectionRoute,
    this.canSendData = false,
  });

  final String peerId;
  final SessionState? sessionState;
  final String? sessionId;
  final bool? presenceOnline;
  final bool presenceFresh;
  final String? backendSessionId;
  final int? presenceAgeMs;
  final bool manualDisconnected;
  final int? lastDataEventAt;
  final PeerConnectionRoute? connectionRoute;
  final bool canSendData;

  /// Whether the peer has an active data session (connecting, connected, or reconnecting).
  bool get hasActiveSession =>
      sessionState == SessionState.connected ||
      sessionState == SessionState.connecting ||
      sessionState == SessionState.reconnecting;

  /// Whether the peer is reachable for messaging.
  ///
  /// Returns true when there is an active data session AND the peer
  /// has not been manually disconnected. This is the authoritative
  /// "can I send messages to this peer?" check.
  bool get isReachable =>
      hasActiveSession && !manualDisconnected;

  /// Whether the UI should show a "connected" indicator.
  ///
  /// Connected requires a confirmed data session AND fresh presence.
  bool get isConnected =>
      hasActiveSession && (presenceOnline == true || presenceFresh);

  /// Whether the connection state is ambiguous (data works but presence is stale).
  bool get isConnectedWithStalePresence =>
      hasActiveSession && presenceOnline == false && !presenceFresh;

  /// Whether the peer's session has been superseded by a newer session ID.
  bool get sessionSuperseded =>
      backendSessionId != null &&
      sessionId != null &&
      sessionId != backendSessionId;

  PeerConnectivitySnapshot copyWith({
    String? peerId,
    SessionState? sessionState,
    String? sessionIdValue,
    bool? presenceOnline,
    bool? presenceFresh,
    String? backendSessionId,
    int? presenceAgeMs,
    bool? manualDisconnected,
    int? lastDataEventAt,
    PeerConnectionRoute? connectionRoute,
    bool? canSendData,
  }) {
    return PeerConnectivitySnapshot(
      peerId: peerId ?? this.peerId,
      sessionState: sessionState ?? this.sessionState,
      sessionId: sessionIdValue ?? sessionId,
      presenceOnline: presenceOnline ?? this.presenceOnline,
      presenceFresh: presenceFresh ?? this.presenceFresh,
      backendSessionId: backendSessionId ?? this.backendSessionId,
      presenceAgeMs: presenceAgeMs ?? this.presenceAgeMs,
      manualDisconnected: manualDisconnected ?? this.manualDisconnected,
      lastDataEventAt: lastDataEventAt ?? this.lastDataEventAt,
      connectionRoute: connectionRoute ?? this.connectionRoute,
      canSendData: canSendData ?? this.canSendData,
    );
  }
}
