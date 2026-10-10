/// # session_retry_policy.dart — protocol_brain package
///
/// Constants and utility functions for session retry behavior including handshake timeout values for direct and relay connections, cached ICE reconnect settings, and offer-wait timeout. Part of protocol_brain_impl.dart.
///
/// **Key types:** _directHandshakeTimeout, _relayHandshakeTimeout, _waitingForOfferTimeout, _cachedIceReconnectEnabled()
///
/// **Package:** protocol_brain
///
/// **Depends on:** protocol_brain_impl.dart (part)
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
