/// # session_reconnect_manager.dart — protocol_brain package
///
/// Manages automatic reconnection logic for active sessions, including exponential backoff, relay fallback, cached ICE reconnect, and disconnect scheduling. Abstracts reconnect operations behind a ReconnectSessionOps interface for testability.
///
/// **Key types:** SessionReconnectManager, SessionReconnectPeerConfigProvider (typedef), ReconnectSessionOps (interface)
///
/// **Package:** protocol_brain
///
/// **Depends on:** dart:async, peer_core, signaling_adapter, connection_memory, protocol_error_classifier, session_manager
library;

import 'dart:async';

import 'package:peer_core/peer_core.dart';

import '../adapters/signaling_adapter.dart';
import 'connection_memory.dart';
import 'protocol_error_classifier.dart';
import 'session_manager.dart';

/// Provider that returns a [PeerConfig] for a given ICE transport policy.
typedef SessionReconnectPeerConfigProvider =
    Future<PeerConfig> Function(PeerIceTransportPolicy policy);

/// Operations that [SessionReconnectManager] needs to perform on an active session.
///
/// This interface abstracts over the private `_ActiveSession` class so that
/// the reconnect manager can be tested independently.
abstract class ReconnectSessionOps {
  String get peerId;
  Session get snapshot;
  set snapshot(Session value);
  bool get shouldReconnect;
  set shouldReconnect(bool value);
  bool get reconnectInProgress;
  set reconnectInProgress(bool value);
  int get retryAttempt;
  set retryAttempt(int value);
  bool get relayFallbackTried;
  set relayFallbackTried(bool value);
  String? get directAttemptFailure;
  set directAttemptFailure(String? value);
  PeerIceTransportPolicy get icePolicy;
  set icePolicy(PeerIceTransportPolicy value);
  bool get usedCachedReconnect;
  set usedCachedReconnect(bool value);
  int get peerGeneration;
  int get reconnectGeneration;
  PeerCore get peer;

  /// Cancels any pending reconnect timer.
  void cancelPendingReconnect();

  /// Cancels the handshake timeout timer.
  void cancelHandshakeTimeout();

  /// Stops all reconnect activity.
  void stopReconnecting();

  /// Returns the next reconnect generation counter.
  int nextReconnectGeneration();

  /// Runs an action serialized behind the peer operation queue.
  Future<T> runPeerOperation<T>(Future<T> Function() action);

  /// Disposes peer bindings (subscriptions, etc.).
  Future<void> disposePeerBindings();

  /// Destroys the current peer and creates a new one with the given policy.
  Future<bool> recreatePeer({
    bool Function()? shouldContinue,
    IceRole? restoreRole,
    PeerIceTransportPolicy? policy,
  });
}

/// Manages reconnection scheduling, handshake timeouts, and relay fallback.
///
/// Extracted from [ProtocolBrainImpl] to make the reconnect logic testable
/// in isolation. All mutable state lives in the session ops object; this class
/// contains only the orchestration logic.
class SessionReconnectManager {
  SessionReconnectManager({
    required this.selfUsername,
    required this.adapter,
    required this.peerConfig,
    required this.peerFactory,
    required this.connectionMemoryStore,
    required this.peerConfigProvider,
    required this.reconnectGrace,
    required this.maxRetries,
    required this.retryDelays,
    required this.cachedIceAttempts,
    required this.cachedIceReconnectEnabled,
    required this.directHandshakeTimeout,
    required this.relayHandshakeTimeout,
    required this.updateSession,
    required this.markPhase,
    required this.deleteRoomSilently,
    required this.startOffer,
    required this.waitForOffer,
    required this.scheduleReconnect,
    required this.errorClassifier,
  });

  final String selfUsername;
  final SignalingAdapter adapter;
  final PeerConfig peerConfig;
  final PeerCoreFactory peerFactory;
  final ConnectionMemoryStore connectionMemoryStore;
  final SessionReconnectPeerConfigProvider? peerConfigProvider;
  final Duration reconnectGrace;

  final int maxRetries;
  final List<int> retryDelays;
  final int cachedIceAttempts;
  final bool cachedIceReconnectEnabled;
  final Duration directHandshakeTimeout;
  final Duration relayHandshakeTimeout;

  /// Updates the session snapshot for a peer.
  final void Function(String peerId, Session session) updateSession;

  /// Marks a phase change on the session.
  final void Function(
    ReconnectSessionOps active,
    SessionPhase phase,
    String detail, {
    SessionState? state,
    String? error,
  })
  markPhase;

  /// Best-effort deletes the signaling room.
  final Future<void> Function(ReconnectSessionOps active) deleteRoomSilently;

  /// Starts an offer for the given session.
  final Future<void> Function(
    ReconnectSessionOps active, {
    required bool isRetry,
    bool isRestart,
  })
  startOffer;

  /// Waits for an offer for the given session.
  final Future<void> Function(
    ReconnectSessionOps active, {
    required bool isRetry,
  })
  waitForOffer;

  /// Schedules a reconnect (used by handshake timeout to reschedule).
  final void Function(String peerId, {Duration minimumDelay}) scheduleReconnect;

  /// Error classifier for building failure messages.
  final ProtocolErrorClassifier errorClassifier;

  /// Returns the handshake timeout duration for the given session.
  Duration handshakeTimeoutFor(ReconnectSessionOps active) {
    return active.icePolicy == PeerIceTransportPolicy.relayOnly
        ? relayHandshakeTimeout
        : directHandshakeTimeout;
  }

  /// Restarts a session after a network change.
  Future<void> restartForNetworkChange(
    ReconnectSessionOps active, {
    required String reason,
    required bool Function(String peerId) isOfferOwner,
  }) async {
    final peerId = active.peerId;
    if (!active.shouldReconnect || active.reconnectInProgress) {
      return;
    }
    if (active.snapshot.state == SessionState.failed) {
      return;
    }
    if (active.snapshot.state == SessionState.connected &&
        active.peer.state == PeerState.connected) {
      active.cancelPendingReconnect();
      return;
    }

    active.cancelPendingReconnect();
    active.cancelHandshakeTimeout();
    active.reconnectInProgress = true;
    active.relayFallbackTried = false;
    active.directAttemptFailure = null;
    active.usedCachedReconnect = false;
    active.retryAttempt = 0;
    final generation = active.nextReconnectGeneration();

    markPhase(
      active,
      SessionPhase.reconnecting,
      reason,
      state: SessionState.reconnecting,
    );

    try {
      final recreated = await active.recreatePeer(
        shouldContinue: () => _canContinueNetworkRestart(active, generation),
        restoreRole: isOfferOwner(peerId) ? IceRole.caller : IceRole.callee,
        policy: PeerIceTransportPolicy.all,
      );
      if (!recreated || !_canContinueNetworkRestart(active, generation)) {
        return;
      }
      if (isOfferOwner(active.peerId)) {
        await startOffer(active, isRetry: true, isRestart: true);
      } else {
        await waitForOffer(active, isRetry: true);
      }
    } catch (error) {
      updateSession(
        active.peerId,
        errorClassifier.sessionForNetworkRecoveryFailed(
          currentSnapshot: active.snapshot,
          errorMessage: errorClassifier.classifyConnectSetupFailure(error),
        ),
      );
    } finally {
      if (active.reconnectGeneration == generation) {
        active.reconnectInProgress = false;
      }
    }
  }

  /// Handles handshake timeout for the given peer.
  Future<void> handleHandshakeTimeout(
    String peerId, {
    required ReconnectSessionOps? Function(String peerId) getSession,
    required bool Function(String peerId) isOfferOwner,
  }) async {
    final active = getSession(peerId);
    if (active == null) {
      return;
    }
    if (active.snapshot.state == SessionState.connected) {
      return;
    }

    await active.disposePeerBindings();
    await active.peer.destroy();
    await deleteRoomSilently(active);

    if (await tryRelayFallback(
      active,
      'Direct path timed out.',
      isOfferOwner: isOfferOwner,
    )) {
      return;
    }
    if (!active.shouldReconnect) {
      active.stopReconnecting();
      updateSession(
        peerId,
        errorClassifier.sessionForHandshakeTimeout(
          currentSnapshot: active.snapshot,
        ),
      );
      return;
    }

    if (active.retryAttempt >= maxRetries) {
      active.stopReconnecting();
      await deleteRoomSilently(active);
      updateSession(
        peerId,
        errorClassifier.sessionForRetriesExhausted(
          currentSnapshot: active.snapshot,
        ),
      );
      return;
    }

    scheduleReconnect(peerId);
  }

  /// Attempts relay fallback after a direct path failure.
  Future<bool> tryRelayFallback(
    ReconnectSessionOps active,
    String directFailure, {
    required bool Function(String peerId) isOfferOwner,
  }) async {
    if (!active.shouldReconnect ||
        active.icePolicy != PeerIceTransportPolicy.all ||
        active.relayFallbackTried) {
      return false;
    }

    active.relayFallbackTried = true;
    active.directAttemptFailure = directFailure;

    final hasRelay = await _hasRelayFallbackConfig();
    if (!hasRelay) {
      updateSession(
        active.peerId,
        errorClassifier.sessionForRelayUnavailable(
          currentSnapshot: active.snapshot,
          directFailure: directFailure,
        ),
      );
      return false;
    }

    active.cancelPendingReconnect();
    active.cancelHandshakeTimeout();
    active.retryAttempt = 0;
    markPhase(
      active,
      SessionPhase.reconnecting,
      'Direct path blocked. Trying TURN relay fallback.',
      state: SessionState.reconnecting,
      error: directFailure,
    );
    final recreated = await active.recreatePeer(
      policy: PeerIceTransportPolicy.relayOnly,
    );
    if (!recreated) {
      return false;
    }
    try {
      if (isOfferOwner(active.peerId)) {
        await startOffer(active, isRetry: true);
      } else {
        await waitForOffer(active, isRetry: true);
      }
      return true;
    } catch (error) {
      updateSession(
        active.peerId,
        errorClassifier.sessionForRelayFallbackFailed(
          currentSnapshot: active.snapshot,
          errorMessage: errorClassifier.classifyConnectSetupFailure(error),
        ),
      );
      return false;
    }
  }

  bool _canContinueNetworkRestart(ReconnectSessionOps active, int generation) {
    return active.shouldReconnect &&
        active.reconnectGeneration == generation &&
        active.snapshot.state != SessionState.failed;
  }

  Future<bool> _hasRelayFallbackConfig() async {
    try {
      final config = peerConfigProvider == null
          ? peerConfig.copyWith(
              iceTransportPolicy: PeerIceTransportPolicy.relayOnly,
            )
          : await peerConfigProvider!(PeerIceTransportPolicy.relayOnly);
      return config.hasRelayServer;
    } catch (_) {
      return false;
    }
  }
}

// Re-export maxCacheFailures for use in connection failure recording
const maxCacheFailures = 3;
