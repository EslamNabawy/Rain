import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/connection_attempt_coordinator.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  test('network recovery is debounced and keeps the latest reason', () async {
    final coordinator = ConnectionAttemptCoordinator(
      networkRecoveryDebounce: const Duration(milliseconds: 20),
    );
    addTearDown(coordinator.dispose);
    final recoveries = <String>[];

    await coordinator.scheduleNetworkRecovery(
      'Wi-Fi came back.',
      (String reason) async => recoveries.add(reason),
    );
    await coordinator.scheduleNetworkRecovery(
      'Mobile network came back.',
      (String reason) async => recoveries.add(reason),
    );

    expect(recoveries, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 45));

    expect(recoveries, <String>['Mobile network came back.']);
    final snapshot = coordinator.snapshot();
    expect(snapshot.networkRecoveryRequests, 2);
    expect(snapshot.networkRecoveryRuns, 1);
  });

  test('retry gate backs off failed peers and clears after success', () {
    var now = DateTime.fromMillisecondsSinceEpoch(1000);
    final coordinator = ConnectionAttemptCoordinator(
      initialRetryBackoff: const Duration(seconds: 2),
      maxRetryBackoff: const Duration(seconds: 5),
      now: () => now,
    );

    expect(coordinator.retryGate('bob').allowed, isTrue);

    coordinator.recordAttemptFailure('bob', StateError('ICE failed'));
    var gate = coordinator.retryGate('bob');
    expect(gate.allowed, isFalse);
    expect(gate.remaining, const Duration(seconds: 2));
    expect(coordinator.snapshot(peerId: 'bob').retryAttempt, 1);

    now = now.add(const Duration(seconds: 2));
    expect(coordinator.retryGate('bob').allowed, isTrue);

    coordinator.recordAttemptFailure('bob', 'still failed');
    gate = coordinator.retryGate('bob');
    expect(gate.allowed, isFalse);
    expect(gate.remaining, const Duration(seconds: 4));
    expect(coordinator.snapshot(peerId: 'bob').retryAttempt, 2);

    coordinator.recordAttemptSuccess('bob');
    expect(coordinator.retryGate('bob').allowed, isTrue);
    expect(coordinator.snapshot(peerId: 'bob').retryAttempt, 0);
  });

  test('passive listeners prefer online and recent accepted friends', () {
    final coordinator = ConnectionAttemptCoordinator(passiveListenerLimit: 2);
    final selected = coordinator.selectPassivePeerIds(
      <FriendRecord>[
        _friend('offline_old', isOnline: false, addedAt: 10, lastOnlineAt: 20),
        _friend('online_old', isOnline: true, addedAt: 1, lastOnlineAt: 5),
        _friend('online_new', isOnline: true, addedAt: 30, lastOnlineAt: 40),
        _friend(
          'pending',
          isOnline: true,
          addedAt: 100,
          state: FriendState.pendingIncoming,
        ),
        _friend('manual', isOnline: true, addedAt: 200),
      ],
      manualDisconnectedPeers: <String>{'manual'},
    );

    expect(selected, <String>['online_new', 'online_old']);
    expect(
      coordinator.canRegisterPassivePeer(
        'another',
        passivePeerIds: <String>{'online_new', 'online_old'},
      ),
      isFalse,
    );
    expect(coordinator.snapshot().passiveListenerSkips, 1);
  });

  test('inbound and rejected offer counters are exposed', () {
    final now = DateTime.fromMillisecondsSinceEpoch(5000);
    final coordinator = ConnectionAttemptCoordinator(now: () => now);

    coordinator.recordInboundOffer('bob');
    coordinator.recordIncomingOfferRejected(
      IncomingOfferRejection(
        peerId: 'bob',
        reason: 'Manual disconnect is active.',
        rejectedAt: now,
        offerTimestamp: 7,
      ),
    );

    final snapshot = coordinator.snapshot(peerId: 'bob');
    expect(snapshot.lastInboundOfferPeer, 'bob');
    expect(snapshot.lastInboundOfferAt, 5000);
    expect(snapshot.lastRejectedOfferPeer, 'bob');
    expect(snapshot.lastRejectedOfferReason, 'Manual disconnect is active.');
    expect(snapshot.lastRejectedOfferAt, 5000);
  });
}

FriendRecord _friend(
  String username, {
  required bool isOnline,
  required int addedAt,
  int? lastOnlineAt,
  FriendState state = FriendState.friend,
}) {
  return FriendRecord(
    username: username,
    displayName: username,
    state: state,
    addedAt: addedAt,
    lastOnlineAt: lastOnlineAt,
    isOnline: isOnline,
    unreadCount: 0,
    gender: null,
  );
}
