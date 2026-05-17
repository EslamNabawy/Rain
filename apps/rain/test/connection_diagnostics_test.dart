import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/state/app_state.dart';
import 'package:rain/application/state/connection_diagnostics.dart';

void main() {
  test('connected direct session reports direct route diagnostics', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: true,
      connection: PeerConnectionView(
        peerId: 'bob',
        session: Session(
          peerId: 'bob',
          state: SessionState.connected,
          connectionType: ConnectionType.signaling,
          sender: (_) {},
          detail: 'Data channels open.',
          roomId: 'room-bob-alice',
          isOfferOwner: true,
          retryAttempt: 2,
          route: const PeerConnectionRoute(
            kind: PeerRouteKind.direct,
            selectedCandidatePairId: 'pair-7',
            localCandidateType: 'host',
            remoteCandidateType: 'srflx',
            protocol: 'udp',
            rtt: 0.031,
            bitrate: 1200000,
            updatedAt: 42,
          ),
        ),
      ),
    );

    expect(diagnostics.label, 'Direct');
    expect(diagnostics.isConnected, isTrue);
    expect(diagnostics.routeKind, PeerRouteKind.direct);
    expect(diagnostics.selectedCandidatePairId, 'pair-7');
    expect(diagnostics.localCandidateType, 'host');
    expect(diagnostics.remoteCandidateType, 'srflx');
    expect(diagnostics.protocol, 'udp');
    expect(diagnostics.retryAttempt, 2);
    expect(diagnostics.roomId, 'room-bob-alice');
    expect(diagnostics.isOfferOwner, isTrue);
  });

  test('failed session reports failure without stale route success', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: true,
      connection: PeerConnectionView(
        peerId: 'bob',
        session: Session(
          peerId: 'bob',
          state: SessionState.failed,
          connectionType: ConnectionType.signaling,
          sender: (_) {},
          detail: 'Failed',
          error: 'ICE timeout',
          route: const PeerConnectionRoute(kind: PeerRouteKind.direct),
        ),
      ),
    );

    expect(diagnostics.label, 'Failed');
    expect(diagnostics.isConnected, isFalse);
    expect(diagnostics.routeKind, PeerRouteKind.unknown);
    expect(diagnostics.lastError, 'ICE timeout');
  });

  test('connected unknown route stays connecting while stats settle', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: true,
      connection: PeerConnectionView(
        peerId: 'bob',
        session: Session(
          peerId: 'bob',
          state: SessionState.connected,
          connectionType: ConnectionType.signaling,
          sender: (_) {},
          detail: 'Connected',
          route: const PeerConnectionRoute.unknown(),
        ),
      ),
    );

    expect(diagnostics.label, 'Connecting');
    expect(diagnostics.detail, 'Detecting route...');
    expect(diagnostics.isConnected, isTrue);
    expect(diagnostics.routeKind, PeerRouteKind.unknown);
  });
}
