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
          phase: SessionPhase.connected,
          detail: 'Data channels open.',
          roomId: 'room-bob-alice',
          isOfferOwner: true,
          retryAttempt: 2,
          route: const PeerConnectionRoute(
            kind: PeerRouteKind.direct,
            selectedCandidatePairId: 'pair-7',
            localCandidateType: 'host',
            remoteCandidateType: 'srflx',
            localAddressFamily: PeerAddressFamily.ipv6,
            remoteAddressFamily: PeerAddressFamily.ipv6,
            protocol: 'udp',
            rtt: 0.031,
            bitrate: 1200000,
            updatedAt: 42,
          ),
        ),
      ),
    );

    expect(diagnostics.label, 'Direct');
    expect(diagnostics.phase, SessionPhase.connected);
    expect(diagnostics.isConnected, isTrue);
    expect(diagnostics.routeKind, PeerRouteKind.direct);
    expect(diagnostics.selectedCandidatePairId, 'pair-7');
    expect(diagnostics.localCandidateType, 'host');
    expect(diagnostics.remoteCandidateType, 'srflx');
    expect(diagnostics.localAddressFamily, PeerAddressFamily.ipv6);
    expect(diagnostics.remoteAddressFamily, PeerAddressFamily.ipv6);
    expect(diagnostics.addressFamily, PeerAddressFamily.ipv6);
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
          phase: SessionPhase.failed,
          detail: 'Failed',
          error: 'ICE timeout',
          route: const PeerConnectionRoute(kind: PeerRouteKind.direct),
        ),
      ),
    );

    expect(diagnostics.label, 'Failed');
    expect(diagnostics.phase, SessionPhase.failed);
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
          phase: SessionPhase.openingDataChannels,
          detail: 'Connected',
          route: const PeerConnectionRoute.unknown(),
        ),
      ),
    );

    expect(diagnostics.label, 'Connecting');
    expect(diagnostics.phase, SessionPhase.openingDataChannels);
    expect(diagnostics.detail, 'Detecting route...');
    expect(diagnostics.isConnected, isTrue);
    expect(diagnostics.routeKind, PeerRouteKind.unknown);
  });

  test(
    'manual disconnect is reconnectable and distinct from remote offline',
    () {
      final manual = ConnectionDiagnostics.fromConnection(
        canChat: true,
        isPeerOnline: true,
        connection: const PeerConnectionView(
          peerId: 'bob',
          manualIntent: ManualConnectionIntent.manualDisconnected,
          localDetail: 'Manual disconnect.',
        ),
      );
      final remoteOffline = ConnectionDiagnostics.fromConnection(
        canChat: true,
        isPeerOnline: false,
        connection: const PeerConnectionView(
          peerId: 'bob',
          localDetail: 'Disconnected.',
        ),
      );

      expect(manual.label, 'Disconnected');
      expect(manual.detail, contains('Manual disconnect'));
      expect(manual.isBusy, isFalse);
      expect(manual.isConnected, isFalse);
      expect(manual.canDisconnect, isFalse);
      expect(remoteOffline.label, 'Offline');
      expect(remoteOffline.detail, contains('closed Rain'));
      expect(remoteOffline.detail, contains('online again'));
      expect(remoteOffline.detail, isNot(contains('Press Connect')));
      expect(remoteOffline.detail, isNot(manual.detail));
      expect(remoteOffline.isBusy, isFalse);
      expect(remoteOffline.isConnected, isFalse);
    },
  );
}
