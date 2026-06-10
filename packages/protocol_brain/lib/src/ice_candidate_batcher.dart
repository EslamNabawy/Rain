import 'dart:async';

typedef IceCandidateBatchFlush<T> = Future<void> Function(List<T> candidates);
typedef IceCandidateBatchErrorHandler =
    void Function(Object error, StackTrace stackTrace);

final class IceCandidateBatcher<T> {
  IceCandidateBatcher({
    required int maxBatchSize,
    required Duration flushWindow,
    required IceCandidateBatchFlush<T> onFlush,
    IceCandidateBatchErrorHandler? onError,
  }) : _maxBatchSize = maxBatchSize,
       _flushWindow = flushWindow,
       _onFlush = onFlush,
       _onError = onError {
    if (maxBatchSize <= 0) {
      throw ArgumentError.value(maxBatchSize, 'maxBatchSize');
    }
    if (flushWindow <= Duration.zero) {
      throw ArgumentError.value(flushWindow, 'flushWindow');
    }
  }

  final int _maxBatchSize;
  final Duration _flushWindow;
  final IceCandidateBatchFlush<T> _onFlush;
  final IceCandidateBatchErrorHandler? _onError;
  final List<T> _pending = <T>[];
  Timer? _timer;
  Future<void> _flushTail = Future<void>.value();
  bool _disposed = false;

  int get pendingCount => _pending.length;

  Future<void> add(T candidate) async {
    if (_disposed) {
      throw StateError('ICE candidate batcher is disposed.');
    }
    _pending.add(candidate);
    if (_pending.length >= _maxBatchSize) {
      await flush();
      return;
    }
    _timer ??= Timer(_flushWindow, () {
      unawaited(
        flush().catchError((Object error, StackTrace stackTrace) {
          _onError?.call(error, stackTrace);
        }),
      );
    });
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) {
      await _flushTail;
      return;
    }
    final batch = List<T>.unmodifiable(_pending);
    _pending.clear();
    await _enqueueFlush(batch);
  }

  Future<void> dispose({bool flushPending = true}) async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (flushPending && _pending.isNotEmpty) {
      final batch = List<T>.unmodifiable(_pending);
      _pending.clear();
      await _enqueueFlush(batch);
    } else {
      _pending.clear();
    }
    await _flushTail;
  }

  Future<void> _enqueueFlush(List<T> batch) {
    final flush = _flushTail
        .catchError((_) {
          // The caller that created the failed flush observes the error. Keep
          // later batches moving so one failed write does not poison the queue.
        })
        .then((_) => _onFlush(batch));
    _flushTail = flush.catchError((_) {
      // Preserve the error for this caller, but keep the tail awaitable for
      // later flushes and disposal.
    });
    return flush;
  }
}
