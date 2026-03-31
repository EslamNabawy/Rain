import 'models.dart';

class PeerStateMachine {
  PeerStateMachine([PeerState initialState = PeerState.idle])
    : _state = initialState;

  static const Map<PeerState, Set<PeerState>> _transitions = <PeerState, Set<PeerState>>{
    PeerState.idle: <PeerState>{PeerState.ready},
    PeerState.ready: <PeerState>{PeerState.offering, PeerState.answering, PeerState.idle},
    PeerState.offering: <PeerState>{PeerState.connecting, PeerState.idle},
    PeerState.answering: <PeerState>{PeerState.connecting, PeerState.idle},
    PeerState.connecting: <PeerState>{
      PeerState.connected,
      PeerState.reconnecting,
      PeerState.failed,
      PeerState.idle,
    },
    PeerState.connected: <PeerState>{PeerState.reconnecting, PeerState.idle},
    PeerState.reconnecting: <PeerState>{
      PeerState.connecting,
      PeerState.connected,
      PeerState.failed,
      PeerState.idle,
    },
    PeerState.failed: <PeerState>{PeerState.idle, PeerState.ready},
  };

  PeerState _state;

  PeerState get state => _state;

  bool canTransition(PeerState next) {
    if (next == _state) {
      return true;
    }
    return _transitions[_state]?.contains(next) ?? false;
  }

  PeerState transition(PeerState next) {
    if (!canTransition(next)) {
      throw StateError('Invalid peer state transition: $_state -> $next');
    }
    _state = next;
    return _state;
  }
}

