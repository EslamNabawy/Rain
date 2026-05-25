import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

enum PeerDisconnectIntent {
  localManual,
  localShutdown,
  remoteManual,
  transportLost,
  networkLost,
}

class ConnectionRetryGate {
  const ConnectionRetryGate.allow()
    : allowed = true,
      nextRetryAt = null,
      remaining = Duration.zero,
      reason = null;

  const ConnectionRetryGate.deny({
    required this.nextRetryAt,
    required this.remaining,
    required this.reason,
  }) : allowed = false;

  final bool allowed;
  final int? nextRetryAt;
  final Duration remaining;
  final String? reason;
}

class ConnectionCoordinatorSnapshot {
  const ConnectionCoordinatorSnapshot({
    required this.passiveListenerCount,
    required this.passiveListenerLimit,
    required this.passiveListenerSkips,
    required this.networkRecoveryRequests,
    required this.networkRecoveryRuns,
    this.retryAttempt = 0,
    this.nextRetryAt,
    this.lastFailureReason,
    this.lastInboundOfferPeer,
    this.lastInboundOfferAt,
    this.lastRejectedOfferPeer,
    this.lastRejectedOfferReason,
    this.lastRejectedOfferAt,
    this.disconnectIntent,
  });

  final int passiveListenerCount;
  final int passiveListenerLimit;
  final int passiveListenerSkips;
  final int networkRecoveryRequests;
  final int networkRecoveryRuns;
  final int retryAttempt;
  final int? nextRetryAt;
  final String? lastFailureReason;
  final String? lastInboundOfferPeer;
  final int? lastInboundOfferAt;
  final String? lastRejectedOfferPeer;
  final String? lastRejectedOfferReason;
  final int? lastRejectedOfferAt;
  final PeerDisconnectIntent? disconnectIntent;

  bool get manualDisconnect =>
      disconnectIntent == PeerDisconnectIntent.localManual;
}

class ConnectionAttemptCoordinator {
  ConnectionAttemptCoordinator({
    this.passiveListenerLimit = 32,
    this.networkRecoveryDebounce = const Duration(seconds: 2),
    this.initialRetryBackoff = const Duration(seconds: 3),
    this.maxRetryBackoff = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (passiveListenerLimit < 1) {
      throw ArgumentError.value(
        passiveListenerLimit,
        'passiveListenerLimit',
        'must be at least 1',
      );
    }
  }

  final int passiveListenerLimit;
  final Duration networkRecoveryDebounce;
  final Duration initialRetryBackoff;
  final Duration maxRetryBackoff;
  final DateTime Function() _now;

  final Map<String, _PeerAttemptState> _peerAttempts =
      <String, _PeerAttemptState>{};
  final Map<String, PeerDisconnectIntent> _disconnectIntents =
      <String, PeerDisconnectIntent>{};

  Timer? _networkRecoveryTimer;
  String? _pendingNetworkRecoveryReason;
  int _networkRecoveryRequests = 0;
  int _networkRecoveryRuns = 0;
  int _passiveListenerCount = 0;
  int _passiveListenerSkips = 0;
  String? _lastInboundOfferPeer;
  int? _lastInboundOfferAt;
  String? _lastRejectedOfferPeer;
  String? _lastRejectedOfferReason;
  int? _lastRejectedOfferAt;

  List<String> selectPassivePeerIds(
    Iterable<FriendRecord> friends, {
    required Set<String> manualDisconnectedPeers,
  }) {
    final candidates =
        friends
            .where(
              (FriendRecord friend) =>
                  friend.state == FriendState.friend &&
                  !manualDisconnectedPeers.contains(friend.username),
            )
            .toList()
          ..sort(_comparePassivePriority);
    return candidates
        .take(passiveListenerLimit)
        .map((FriendRecord friend) => friend.username)
        .toList(growable: false);
  }

  bool canRegisterPassivePeer(
    String peerId, {
    required Set<String> passivePeerIds,
  }) {
    if (passivePeerIds.contains(peerId)) {
      return true;
    }
    if (passivePeerIds.length < passiveListenerLimit) {
      return true;
    }
    _passiveListenerSkips += 1;
    return false;
  }

  void updatePassiveListenerCount(int count) {
    _passiveListenerCount = count;
  }

  ConnectionRetryGate retryGate(String peerId) {
    final attempt = _peerAttempts[peerId];
    final nextRetryAt = attempt?.nextRetryAt;
    if (nextRetryAt == null) {
      return const ConnectionRetryGate.allow();
    }
    final nowMs = _now().millisecondsSinceEpoch;
    if (nowMs >= nextRetryAt) {
      return const ConnectionRetryGate.allow();
    }
    return ConnectionRetryGate.deny(
      nextRetryAt: nextRetryAt,
      remaining: Duration(milliseconds: nextRetryAt - nowMs),
      reason: attempt?.lastFailureReason,
    );
  }

  void recordAttemptFailure(String peerId, Object? error) {
    final attempt = _peerAttempts.putIfAbsent(peerId, _PeerAttemptState.new);
    attempt.retryAttempt += 1;
    attempt.lastFailureReason = _formatFailure(error);
    final delay = _retryDelay(attempt.retryAttempt);
    attempt.nextRetryAt = _now().add(delay).millisecondsSinceEpoch;
  }

  void recordAttemptSuccess(String peerId) {
    _peerAttempts.remove(peerId);
    _disconnectIntents.remove(peerId);
  }

  void clearRetry(String peerId) {
    _peerAttempts.remove(peerId);
  }

  void recordDisconnectIntent(String peerId, PeerDisconnectIntent intent) {
    _disconnectIntents[peerId] = intent;
  }

  PeerDisconnectIntent? disconnectIntentFor(String peerId) {
    return _disconnectIntents[peerId];
  }

  void clearDisconnectIntent(String peerId) {
    _disconnectIntents.remove(peerId);
  }

  void recordInboundOffer(String peerId) {
    _lastInboundOfferPeer = peerId;
    _lastInboundOfferAt = _now().millisecondsSinceEpoch;
  }

  void recordIncomingOfferRejected(IncomingOfferRejection rejection) {
    _lastRejectedOfferPeer = rejection.peerId;
    _lastRejectedOfferReason = rejection.reason;
    _lastRejectedOfferAt = rejection.rejectedAt.millisecondsSinceEpoch;
  }

  Future<void> scheduleNetworkRecovery(
    String reason,
    Future<void> Function(String reason) recover,
  ) async {
    _networkRecoveryRequests += 1;
    _pendingNetworkRecoveryReason = reason;
    _networkRecoveryTimer?.cancel();
    if (networkRecoveryDebounce <= Duration.zero) {
      await _runNetworkRecovery(recover);
      return;
    }
    _networkRecoveryTimer = Timer(networkRecoveryDebounce, () {
      unawaited(_runNetworkRecovery(recover));
    });
  }

  ConnectionCoordinatorSnapshot snapshot({String? peerId}) {
    final attempt = peerId == null ? null : _peerAttempts[peerId];
    return ConnectionCoordinatorSnapshot(
      passiveListenerCount: _passiveListenerCount,
      passiveListenerLimit: passiveListenerLimit,
      passiveListenerSkips: _passiveListenerSkips,
      networkRecoveryRequests: _networkRecoveryRequests,
      networkRecoveryRuns: _networkRecoveryRuns,
      retryAttempt: attempt?.retryAttempt ?? 0,
      nextRetryAt: attempt?.nextRetryAt,
      lastFailureReason: attempt?.lastFailureReason,
      lastInboundOfferPeer: _lastInboundOfferPeer,
      lastInboundOfferAt: _lastInboundOfferAt,
      lastRejectedOfferPeer: _lastRejectedOfferPeer,
      lastRejectedOfferReason: _lastRejectedOfferReason,
      lastRejectedOfferAt: _lastRejectedOfferAt,
      disconnectIntent: peerId == null ? null : _disconnectIntents[peerId],
    );
  }

  void dispose() {
    _networkRecoveryTimer?.cancel();
    _networkRecoveryTimer = null;
  }

  Future<void> _runNetworkRecovery(
    Future<void> Function(String reason) recover,
  ) async {
    final reason =
        _pendingNetworkRecoveryReason ??
        'Network changed. Restarting peer connection paths.';
    _pendingNetworkRecoveryReason = null;
    _networkRecoveryTimer?.cancel();
    _networkRecoveryTimer = null;
    _networkRecoveryRuns += 1;
    try {
      await recover(reason);
    } catch (_) {
      // Recovery is driven by volatile network state; session state carries
      // user-visible failures when a peer restart actually fails.
    }
  }

  Duration _retryDelay(int retryAttempt) {
    final shift = (retryAttempt - 1).clamp(0, 6);
    final multiplier = 1 << shift;
    final delay = initialRetryBackoff * multiplier;
    return delay > maxRetryBackoff ? maxRetryBackoff : delay;
  }

  int _comparePassivePriority(FriendRecord left, FriendRecord right) {
    final online = (right.isOnline ? 1 : 0).compareTo(left.isOnline ? 1 : 0);
    if (online != 0) {
      return online;
    }
    final activity = _activityTimestamp(
      right,
    ).compareTo(_activityTimestamp(left));
    if (activity != 0) {
      return activity;
    }
    return left.username.compareTo(right.username);
  }

  int _activityTimestamp(FriendRecord friend) {
    return friend.lastOnlineAt ?? friend.addedAt;
  }

  String? _formatFailure(Object? error) {
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
}

class _PeerAttemptState {
  int retryAttempt = 0;
  int? nextRetryAt;
  String? lastFailureReason;
}
