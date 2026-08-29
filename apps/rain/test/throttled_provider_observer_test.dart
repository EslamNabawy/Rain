/// # throttled_provider_observer_test.dart
///
/// Locks the structural hashing behavior added in [[ADR-011]] Phase 13:
/// `ThrottledProviderObserver.hashForDedupe` must produce equal hashes
/// for identity-distinct but content-equal `PeerConnectivitySnapshot`
/// and `ConnectionDiagnostics` values. Without structural hashing, every
/// new instance produces a different `Object.hashCode` and the dedupe
/// pass-through degenerates into identity-equality. See [[Risk
/// Register|R-023]] and [[Technical Debt Register|TD-024]].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/state/connection_diagnostics.dart';
import 'package:rain/application/state/peer_connectivity_snapshot.dart';
import 'package:rain/infrastructure/diagnostics/tracing/throttled_provider_observer.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  group('ThrottledProviderObserver.hashForDedupe', () {
    test('identical PeerConnectivitySnapshot content hashes equal', () {
      final a = _buildSnapshot(peerId: 'alice', sessionId: 's1');
      final b = _buildSnapshot(peerId: 'alice', sessionId: 's1');
      expect(
        identical(a, b),
        isFalse,
        reason: 'Two separate constructions must not be identity-equal.',
      );
      expect(
        ThrottledProviderObserver.hashForDedupe(a),
        equals(ThrottledProviderObserver.hashForDedupe(b)),
      );
    });

    test('changed PeerConnectivitySnapshot content hashes different', () {
      final a = _buildSnapshot(peerId: 'alice', sessionId: 's1');
      final b = _buildSnapshot(peerId: 'alice', sessionId: 's2');
      expect(
        ThrottledProviderObserver.hashForDedupe(a),
        isNot(equals(ThrottledProviderObserver.hashForDedupe(b))),
      );
    });

    test('changed peerId hashes different', () {
      final a = _buildSnapshot(peerId: 'alice', sessionId: 's1');
      final b = _buildSnapshot(peerId: 'bob', sessionId: 's1');
      expect(
        ThrottledProviderObserver.hashForDedupe(a),
        isNot(equals(ThrottledProviderObserver.hashForDedupe(b))),
      );
    });

    test('changed manualDisconnected hashes different', () {
      final a = _buildSnapshot(
        peerId: 'alice',
        sessionId: 's1',
        manualDisconnected: false,
      );
      final b = _buildSnapshot(
        peerId: 'alice',
        sessionId: 's1',
        manualDisconnected: true,
      );
      expect(
        ThrottledProviderObserver.hashForDedupe(a),
        isNot(equals(ThrottledProviderObserver.hashForDedupe(b))),
      );
    });

    test('identical ConnectionDiagnostics content hashes equal', () {
      final a = _buildDiagnostics(status: PeerConnectionUiStatusKind.connected);
      final b = _buildDiagnostics(status: PeerConnectionUiStatusKind.connected);
      expect(
        ThrottledProviderObserver.hashForDedupe(a),
        equals(ThrottledProviderObserver.hashForDedupe(b)),
      );
    });

    test('changed ConnectionDiagnostics status hashes different', () {
      final a = _buildDiagnostics(status: PeerConnectionUiStatusKind.connected);
      final b = _buildDiagnostics(
        status: PeerConnectionUiStatusKind.recovering,
      );
      expect(
        ThrottledProviderObserver.hashForDedupe(a),
        isNot(equals(ThrottledProviderObserver.hashForDedupe(b))),
      );
    });

    test(
      'Map<String, PeerConnectivitySnapshot> with same content hashes equal',
      () {
        final m1 = <String, PeerConnectivitySnapshot>{
          'alice': _buildSnapshot(peerId: 'alice', sessionId: 's1'),
          'bob': _buildSnapshot(peerId: 'bob', sessionId: 's2'),
        };
        final m2 = <String, PeerConnectivitySnapshot>{
          'alice': _buildSnapshot(peerId: 'alice', sessionId: 's1'),
          'bob': _buildSnapshot(peerId: 'bob', sessionId: 's2'),
        };
        expect(
          ThrottledProviderObserver.hashForDedupe(m1),
          equals(ThrottledProviderObserver.hashForDedupe(m2)),
        );
      },
    );

    test(
      'Map<String, PeerConnectivitySnapshot> with changed content hashes different',
      () {
        final m1 = <String, PeerConnectivitySnapshot>{
          'alice': _buildSnapshot(peerId: 'alice', sessionId: 's1'),
        };
        final m2 = <String, PeerConnectivitySnapshot>{
          'alice': _buildSnapshot(peerId: 'alice', sessionId: 's1'),
          'bob': _buildSnapshot(peerId: 'bob', sessionId: 's2'),
        };
        expect(
          ThrottledProviderObserver.hashForDedupe(m1),
          isNot(equals(ThrottledProviderObserver.hashForDedupe(m2))),
        );
      },
    );

    test('Map with same peers but insertion order is independent', () {
      final m1 = <String, PeerConnectivitySnapshot>{
        'alice': _buildSnapshot(peerId: 'alice', sessionId: 's1'),
        'bob': _buildSnapshot(peerId: 'bob', sessionId: 's2'),
      };
      final m2 = <String, PeerConnectivitySnapshot>{
        'bob': _buildSnapshot(peerId: 'bob', sessionId: 's2'),
        'alice': _buildSnapshot(peerId: 'alice', sessionId: 's1'),
      };
      expect(
        ThrottledProviderObserver.hashForDedupe(m1),
        equals(ThrottledProviderObserver.hashForDedupe(m2)),
        reason:
            'Map hashing must be canonical (sort keys) so two maps with '
            'the same entries in different iteration order produce the same '
            'dedupe hash.',
      );
    });

    test('null hashes to null', () {
      expect(ThrottledProviderObserver.hashForDedupe(null), isNull);
    });
  });
}

PeerConnectivitySnapshot _buildSnapshot({
  required String peerId,
  required String sessionId,
  bool manualDisconnected = false,
}) {
  return PeerConnectivitySnapshot(
    peerId: peerId,
    sessionState: SessionState.connected,
    sessionId: sessionId,
    presenceOnline: true,
    presenceFresh: true,
    backendSessionId: sessionId,
    backendPresenceSessionId: sessionId,
    presenceAgeMs: 100,
    presenceFreshnessWindowMs: 30000,
    presenceObservedAtMs: 1000,
    presenceState: 'online',
    manualDisconnected: manualDisconnected,
    lastDataEventAt: 2000,
    connectionRoute: const PeerConnectionRoute(
      kind: PeerRouteKind.direct,
      localCandidateType: 'host',
      remoteCandidateType: 'host',
      localAddressFamily: PeerAddressFamily.unknown,
      remoteAddressFamily: PeerAddressFamily.unknown,
      protocol: 'udp',
      rtt: 3.0,
      bitrate: 1000,
      selectedCandidatePairId: 'pair-1',
      updatedAt: 5000,
    ),
    canSendData: true,
  );
}

ConnectionDiagnostics _buildDiagnostics({
  required PeerConnectionUiStatusKind status,
}) {
  return ConnectionDiagnostics(
    statusKind: status,
    label: 'Connected',
    detail: 'Encrypted peer lane is open.',
    route: const PeerConnectionRoute(
      kind: PeerRouteKind.direct,
      localCandidateType: 'host',
      remoteCandidateType: 'host',
      localAddressFamily: PeerAddressFamily.unknown,
      remoteAddressFamily: PeerAddressFamily.unknown,
      protocol: 'udp',
      rtt: 3.0,
      bitrate: 1000,
      selectedCandidatePairId: 'pair-1',
      updatedAt: 5000,
    ),
  );
}
