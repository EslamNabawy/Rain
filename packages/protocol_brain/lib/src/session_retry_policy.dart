part of 'protocol_brain_impl.dart';

const Duration _directHandshakeTimeout = Duration(seconds: 20);
const Duration _relayHandshakeTimeout = Duration(seconds: 60);
const Duration _waitingForOfferTimeout = Duration(seconds: 60);

Duration _maxDuration(Duration a, Duration b) {
  return a.compareTo(b) >= 0 ? a : b;
}

bool _cachedIceReconnectEnabled() {
  return false;
}
