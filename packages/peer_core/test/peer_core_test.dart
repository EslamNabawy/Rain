import 'package:flutter_test/flutter_test.dart';
import 'package:peer_core/peer_core.dart';

void main() {
  test('peer state machine enforces happy path transitions', () {
    final machine = PeerStateMachine();

    expect(machine.state, PeerState.idle);
    machine.transition(PeerState.ready);
    machine.transition(PeerState.offering);
    machine.transition(PeerState.connecting);
    machine.transition(PeerState.connected);

    expect(machine.state, PeerState.connected);
  });

  test('peer state machine rejects invalid transitions', () {
    final machine = PeerStateMachine();

    expect(
      () => machine.transition(PeerState.connected),
      throwsStateError,
    );
  });
}

