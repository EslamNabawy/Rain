part of 'protocol_brain_impl.dart';

class _ActiveSession {
  _ActiveSession({
    required this.peerId,
    required this.roomId,
    required this.peer,
    required this.snapshot,
  });

  final String peerId;
  final String roomId;
  PeerCore peer;
  final List<StreamSubscription<dynamic>> subscriptions =
      <StreamSubscription<dynamic>>[];
  final Map<IceRole, StreamSubscription<RTCIceCandidate>> iceSubscriptions =
      <IceRole, StreamSubscription<RTCIceCandidate>>{};
  final List<RTCIceCandidate> remoteIceCache = <RTCIceCandidate>[];

  Session snapshot;
  bool bound = false;
  int retryAttempt = 0;
  bool usedCachedReconnect = false;
  bool shouldReconnect = true;
  bool reconnectInProgress = false;
  bool relayFallbackTried = false;
  String? directAttemptFailure;
  PeerIceTransportPolicy icePolicy = PeerIceTransportPolicy.all;
  int reconnectGeneration = 0;
  int? lastOfferTs;
  int? lastAnswerTs;
  StreamSubscription<SDPPayload>? answerSubscription;
  Timer? handshakeTimeoutTimer;
  Timer? reconnectTimer;
  int peerGeneration = 0;
  Future<void> _peerOperationTail = Future<void>.value();

  Future<void> dispose() async {
    shouldReconnect = false;
    stopReconnecting();
    await runPeerOperation(() async {
      await disposePeerBindings();
      peerGeneration += 1;
      await peer.destroy();
    });
  }

  Future<T> runPeerOperation<T>(Future<T> Function() action) {
    final previous = _peerOperationTail;
    final completer = Completer<void>();
    _peerOperationTail = completer.future;
    return previous.then((_) => action()).whenComplete(() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
  }

  Future<void> disposePeerBindings() async {
    cancelHandshakeTimeout();
    await answerSubscription?.cancel();
    answerSubscription = null;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    subscriptions.clear();
    for (final subscription in iceSubscriptions.values) {
      await subscription.cancel();
    }
    iceSubscriptions.clear();
  }

  void startHandshakeTimeout(
    Future<void> Function() onTimeout, {
    required Duration duration,
  }) {
    cancelHandshakeTimeout();
    handshakeTimeoutTimer = Timer(duration, () {
      unawaited(onTimeout());
    });
  }

  void cancelHandshakeTimeout() {
    handshakeTimeoutTimer?.cancel();
    handshakeTimeoutTimer = null;
  }

  int nextReconnectGeneration() {
    reconnectGeneration += 1;
    return reconnectGeneration;
  }

  void cancelPendingReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = null;
    reconnectInProgress = false;
    reconnectGeneration += 1;
  }

  void stopReconnecting() {
    shouldReconnect = false;
    cancelPendingReconnect();
  }
}
