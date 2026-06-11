/// # connection_diagnostics_test
///
/// Tests connection diagnostics computation including route detection, manual disconnect handling, call status priority, and presence freshness.
///
/// **Key types:** ConnectionDiagnostics, PeerConnectionView, PeerConnectivitySnapshot, VoiceCallState.
///
/// **Depends on:** Session state, peer connectivity snapshots, and voice call state.

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/app_state.dart';
import 'package:rain/application/state/connection_diagnostics.dart';
import 'package:rain/application/state/peer_connectivity_snapshot.dart';

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
    expect(diagnostics.isConnected, isFalse);
    expect(diagnostics.canSendData, isTrue);
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

  test('manual disconnect beats stale data lane and call recovery', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: true,
      connection: const PeerConnectionView(
        peerId: 'bob',
        manualIntent: ManualConnectionIntent.manualDisconnected,
      ),
      snapshot: const PeerConnectivitySnapshot(
        peerId: 'bob',
        sessionState: SessionState.connected,
        presenceOnline: false,
        presenceFresh: false,
        canSendData: true,
      ),
      voiceCall: const VoiceCallState(
        phase: VoiceCallPhase.active,
        peerId: 'bob',
        mediaReconnecting: true,
      ),
    );

    expect(
      diagnostics.statusKind,
      PeerConnectionUiStatusKind.manuallyDisconnected,
    );
    expect(diagnostics.label, 'Disconnected');
    expect(diagnostics.canSendData, isFalse);
    expect(diagnostics.isConnected, isFalse);
  });

  test('recovering call status beats superseded data session', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: true,
      connection: const PeerConnectionView(peerId: 'bob'),
      snapshot: const PeerConnectivitySnapshot(
        peerId: 'bob',
        sessionState: SessionState.connected,
        sessionId: 'local-session',
        presenceOnline: true,
        presenceFresh: true,
        backendSessionId: 'backend-session',
        canSendData: true,
      ),
      voiceCall: const VoiceCallState(
        phase: VoiceCallPhase.active,
        peerId: 'bob',
        mediaReconnecting: true,
      ),
    );

    expect(diagnostics.statusKind, PeerConnectionUiStatusKind.recovering);
    expect(diagnostics.label, 'Recovering');
    expect(diagnostics.isBusy, isTrue);
    expect(diagnostics.canSendData, isTrue);
  });

  test('connected snapshot overrides offline presence', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: false,
      connection: const PeerConnectionView(peerId: 'bob'),
      snapshot: const PeerConnectivitySnapshot(
        peerId: 'bob',
        sessionState: SessionState.connected,
        presenceOnline: true,
        presenceFresh: true,
        canSendData: true,
      ),
    );

    expect(diagnostics.label, 'Connected');
    expect(diagnostics.statusKind, PeerConnectionUiStatusKind.connected);
    expect(diagnostics.isConnected, isTrue);
    expect(diagnostics.canSendData, isTrue);
    expect(diagnostics.canDisconnect, isTrue);
  });

  test('stale presence with open data lane is not visually connected', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: false,
      connection: const PeerConnectionView(peerId: 'bob'),
      snapshot: const PeerConnectivitySnapshot(
        peerId: 'bob',
        sessionState: SessionState.connected,
        presenceOnline: false,
        presenceFresh: false,
        canSendData: true,
      ),
    );

    expect(diagnostics.statusKind, PeerConnectionUiStatusKind.dataLaneOnly);
    expect(diagnostics.label, 'Data lane only');
    expect(diagnostics.isConnected, isFalse);
    expect(diagnostics.canSendData, isTrue);
    expect(diagnostics.canDisconnect, isTrue);
  });

  test('superseded snapshot shows reconnecting', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: true,
      connection: const PeerConnectionView(peerId: 'bob'),
      snapshot: const PeerConnectivitySnapshot(
        peerId: 'bob',
        sessionState: SessionState.connected,
        sessionId: 'local-session',
        presenceOnline: true,
        presenceFresh: true,
        backendSessionId: 'backend-session',
      ),
    );

    expect(diagnostics.statusKind, PeerConnectionUiStatusKind.outOfSync);
    expect(diagnostics.label, 'Out of sync');
    expect(diagnostics.isBusy, isTrue);
    expect(diagnostics.canDisconnect, isTrue);
  });

  test('failed call status beats connected data lane', () {
    final diagnostics = ConnectionDiagnostics.fromConnection(
      canChat: true,
      isPeerOnline: true,
      connection: const PeerConnectionView(peerId: 'bob'),
      snapshot: const PeerConnectivitySnapshot(
        peerId: 'bob',
        sessionState: SessionState.connected,
        presenceOnline: true,
        presenceFresh: true,
        canSendData: true,
      ),
      voiceCall: const VoiceCallState(
        phase: VoiceCallPhase.failed,
        peerId: 'bob',
        detail: 'Video renderer failed.',
        failureReason: VoiceCallFailureReason.videoRendererFailed,
      ),
    );

    expect(diagnostics.statusKind, PeerConnectionUiStatusKind.failed);
    expect(diagnostics.label, 'Failed');
    expect(diagnostics.isConnected, isFalse);
    expect(diagnostics.canSendData, isTrue);
    expect(diagnostics.detail, 'Video renderer failed.');
  });
}
