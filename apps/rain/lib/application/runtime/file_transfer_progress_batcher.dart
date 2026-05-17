class FileTransferProgressBatcher {
  FileTransferProgressBatcher({
    required this.markProgress,
    DateTime Function()? now,
    this.minBytes = 512 * 1024,
    this.minInterval = const Duration(milliseconds: 250),
  }) : _now = now ?? DateTime.now;

  final Future<void> Function(String transferId, int bytesTransferred)
  markProgress;
  final DateTime Function() _now;
  final int minBytes;
  final Duration minInterval;
  final Map<String, _ProgressFlushState> _states =
      <String, _ProgressFlushState>{};

  Future<void> record(String transferId, int bytesTransferred) async {
    final current = _states[transferId];
    final now = _now();
    if (current == null ||
        bytesTransferred - current.bytesTransferred >= minBytes ||
        now.difference(current.flushedAt) >= minInterval) {
      await _flushAt(transferId, bytesTransferred, now);
    }
  }

  Future<void> flush(String transferId, int bytesTransferred) async {
    final current = _states[transferId];
    if (current != null && current.bytesTransferred == bytesTransferred) {
      return;
    }
    await _flushAt(transferId, bytesTransferred, _now());
  }

  void clear(String transferId) {
    _states.remove(transferId);
  }

  Future<void> _flushAt(
    String transferId,
    int bytesTransferred,
    DateTime now,
  ) async {
    await markProgress(transferId, bytesTransferred);
    _states[transferId] = _ProgressFlushState(
      bytesTransferred: bytesTransferred,
      flushedAt: now,
    );
  }
}

class _ProgressFlushState {
  const _ProgressFlushState({
    required this.bytesTransferred,
    required this.flushedAt,
  });

  final int bytesTransferred;
  final DateTime flushedAt;
}
