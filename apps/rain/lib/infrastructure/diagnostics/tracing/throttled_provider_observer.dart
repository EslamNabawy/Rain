import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain/application/state/connection_diagnostics.dart';
import 'package:rain/application/state/peer_connectivity_snapshot.dart';
import 'package:rain/infrastructure/services/rain_debug_log_service.dart';

/// Drops noisy provider updates where value equality hasn't changed.
/// Wraps existing RainDebugProviderObserver logic with distinct + debounce.
///
/// Structural hashes are used for the two known-noisy provider types
/// ([PeerConnectivitySnapshot] and [ConnectionDiagnostics]) because their
/// `Object.hashCode` is identity-based. Without structural hashing, every
/// emit produces a new identity hash and the dedupe pass-through
/// degenerates into identity-equality (the same bug the throttle is meant
/// to fix). See [[Risk Register|R-023]] and [[Technical Debt Register|TD-024]].

final class ThrottledProviderObserver extends ProviderObserver {
  ThrottledProviderObserver(this.log);
  final RainDebugLogService log;

  final Map<String, Object?> _lastValueHash = {};
  final Map<String, DateTime> _lastEmit = {};

  static const _debounce = Duration(milliseconds: 200);
  static const _noisyProviders = {
    'Provider<ConnectionDiagnostics>',
    'NotifierProvider<PeerConnectivityController, Map<String, PeerConnectivitySnapshot>>',
  };

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    final key =
        context.provider.name ?? context.provider.runtimeType.toString();
    final hash = hashForDedupe(newValue);

    // Distinct check: if hash same as last, skip
    if (_lastValueHash[key] == hash) return;

    // Debounce noisy providers
    if (_noisyProviders.contains(key)) {
      final last = _lastEmit[key];
      if (last != null && DateTime.now().difference(last) < _debounce) return;
      _lastEmit[key] = DateTime.now();
    }

    _lastValueHash[key] = hash;

    // Delegate to original logging (copy of RainDebugProviderObserver._record)
    if (!log.enabled) return;
    log.event(
      category: 'ui_state',
      name: 'provider_updated',
      severity: RainDebugSeverity.debug,
      context: {
        'provider': key,
        'hash': hash,
        // only include diff-relevant fields, not full type churn
      },
    );
  }

  /// Compute a structural hash for a provider value so that identity-equal
  /// but content-equal updates dedupe correctly. Public for testability.
  ///
  /// For [ConnectionDiagnostics] and [PeerConnectivitySnapshot] (and maps
  /// of the latter), the hash is computed from each field value. For all
  /// other types, this falls back to [Object.hashCode], which is identity
  /// for types that do not override `==`/`hashCode`. That fallback is
  /// sufficient for providers whose values are immutable constants or
  /// are explicitly value-equal under [Object.==].
  @visibleForTesting
  static Object? hashForDedupe(Object? value) {
    if (value == null) return null;
    if (value is ConnectionDiagnostics) {
      return _hashConnectionDiagnostics(value);
    }
    if (value is PeerConnectivitySnapshot) {
      return _hashPeerConnectivitySnapshot(value);
    }
    if (value is Map<String, PeerConnectivitySnapshot>) {
      return _hashPeerConnectivityMap(value);
    }
    return value.hashCode;
  }

  static int _hashPeerConnectivitySnapshot(PeerConnectivitySnapshot s) {
    return Object.hash(
      s.peerId,
      s.sessionState,
      s.sessionId,
      s.presenceOnline,
      s.presenceFresh,
      s.backendSessionId,
      s.backendPresenceSessionId,
      s.presenceAgeMs,
      s.presenceFreshnessWindowMs,
      s.presenceObservedAtMs,
      s.presenceState,
      s.manualDisconnected,
      s.lastDataEventAt,
      _hashPeerConnectionRoute(s.connectionRoute),
      s.canSendData,
    );
  }

  static int _hashConnectionDiagnostics(ConnectionDiagnostics d) {
    return Object.hashAll(<Object?>[
      d.statusKind,
      d.label,
      d.detail,
      _hashPeerConnectionRoute(d.route),
      d.phase,
      d.roomId,
      d.isOfferOwner,
      d.retryAttempt,
      d.connectionRetryAttempt,
      d.nextRetryAt,
      d.lastError,
      d.updatedAt,
      d.passiveListenerCount,
      d.passiveListenerLimit,
      d.passiveListenerSkips,
      d.networkRecoveryRequests,
      d.networkRecoveryRuns,
      d.lastInboundOfferPeer,
      d.lastInboundOfferAt,
      d.lastRejectedOfferPeer,
      d.lastRejectedOfferReason,
      d.lastRejectedOfferAt,
      d.isBusy,
      d.isConnected,
      d.canSendData,
      d.canDisconnect,
    ]);
  }

  static int _hashPeerConnectionRoute(Object? route) {
    if (route == null) return 0;
    // PeerConnectionRoute is defined in package:peer_core. It does not
    // override == / hashCode, so fall back to its toString() as a
    // structural fingerprint. toString() includes every diagnostic field
    // (kind, candidates, RTT, etc.) so two equal routes produce equal
    // toString() values.
    return route.toString().hashCode;
  }

  static String _hashPeerConnectivityMap(
    Map<String, PeerConnectivitySnapshot> map,
  ) {
    // Map identity-equal updates with the same per-peer content should
    // hash to the same value. Compute a stable canonical form.
    final sortedKeys = map.keys.toList()..sort();
    final buf = StringBuffer('{');
    var first = true;
    for (final k in sortedKeys) {
      if (!first) buf.write(',');
      first = false;
      buf
        ..write(jsonEncode(k))
        ..write(':')
        ..write(_hashPeerConnectivitySnapshot(map[k]!));
    }
    buf.write('}');
    return buf.toString();
  }

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    // keep as-is
    if (!log.enabled) return;
    log.event(
      category: 'ui_state',
      name: 'provider_added',
      severity: RainDebugSeverity.debug,
      context: {
        'provider':
            context.provider.name ?? context.provider.runtimeType.toString(),
      },
    );
  }

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    _lastValueHash.remove(
      context.provider.name ?? context.provider.runtimeType.toString(),
    );
    _lastEmit.remove(
      context.provider.name ?? context.provider.runtimeType.toString(),
    );
    if (!log.enabled) return;
    log.event(
      category: 'ui_state',
      name: 'provider_disposed',
      severity: RainDebugSeverity.debug,
      context: {
        'provider':
            context.provider.name ?? context.provider.runtimeType.toString(),
      },
    );
  }
}
