import 'connection_command_models.dart';

class ConnectionRunCanceledException implements Exception {
  const ConnectionRunCanceledException(this.reason);

  final ConnectionCancelReason reason;

  @override
  String toString() => 'Connection run canceled: $reason';
}

class ConnectionRunToken {
  ConnectionRunToken({
    required this.peerId,
    required this.runId,
    required this.generation,
    required this.startedAt,
  });

  final String peerId;
  final String runId;
  final int generation;
  final int startedAt;

  bool _isCanceled = false;
  ConnectionCancelReason? _cancelReason;

  bool get isCanceled => _isCanceled;

  ConnectionCancelReason? get cancelReason => _cancelReason;

  void cancel(ConnectionCancelReason reason) {
    if (_isCanceled) {
      return;
    }
    _isCanceled = true;
    _cancelReason = reason;
  }

  bool isActiveFor(String peerId, String runId, int generation) {
    return !_isCanceled &&
        this.peerId == peerId &&
        this.runId == runId &&
        this.generation == generation;
  }

  void throwIfCanceled() {
    if (_isCanceled) {
      throw ConnectionRunCanceledException(
        _cancelReason ?? ConnectionCancelReason.userCanceled,
      );
    }
  }
}
