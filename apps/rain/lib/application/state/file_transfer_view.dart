import 'package:rain_core/rain_core.dart';

class FileTransferView {
  const FileTransferView({
    required this.record,
    this.speedBytesPerSecond,
    this.eta,
  });

  final FileTransferRecord record;
  final int? speedBytesPerSecond;
  final Duration? eta;
}

class FileTransferSpeedTracker {
  FileTransferSpeedTracker({
    DateTime Function()? now,
    Duration sampleWindow = const Duration(seconds: 2),
    Duration displayUpdateInterval = const Duration(milliseconds: 750),
    Duration minimumSampleAge = const Duration(milliseconds: 500),
  }) : _now = now ?? DateTime.now,
       _sampleWindow = sampleWindow,
       _displayUpdateInterval = displayUpdateInterval,
       _minimumSampleAge = minimumSampleAge;

  final DateTime Function() _now;
  final Duration _sampleWindow;
  final Duration _displayUpdateInterval;
  final Duration _minimumSampleAge;
  final Map<String, _TransferSpeedState> _states =
      <String, _TransferSpeedState>{};

  List<FileTransferView> apply(List<FileTransferRecord> transfers) {
    final activeIds = <String>{};
    final views = <FileTransferView>[];

    for (final transfer in transfers) {
      if (!_shouldTrack(transfer)) {
        _states.remove(transfer.id);
        views.add(FileTransferView(record: transfer));
        continue;
      }

      activeIds.add(transfer.id);
      final now = _now();
      final previous = _states[transfer.id];
      final samples = _nextSamples(previous?.samples, transfer, now);
      final windowSpeed = _speedFor(samples);
      final visibleSpeed = _visibleSpeedFor(
        previous?.visibleSpeed,
        windowSpeed,
        now,
      );
      _states[transfer.id] = _TransferSpeedState(
        samples: samples,
        visibleSpeed: visibleSpeed,
      );
      final bytesPerSecond = visibleSpeed?.bytesPerSecond;

      views.add(
        FileTransferView(
          record: transfer,
          speedBytesPerSecond: bytesPerSecond,
          eta: bytesPerSecond == null
              ? null
              : _etaFor(transfer, bytesPerSecond),
        ),
      );
    }

    _states.removeWhere(
      (String transferId, _) => !activeIds.contains(transferId),
    );
    return views;
  }

  bool _shouldTrack(FileTransferRecord transfer) {
    return transfer.state == FileTransferState.sending ||
        transfer.state == FileTransferState.receiving;
  }

  List<_TransferProgressSample> _nextSamples(
    List<_TransferProgressSample>? previousSamples,
    FileTransferRecord transfer,
    DateTime now,
  ) {
    final previous = previousSamples ?? const <_TransferProgressSample>[];
    final latest = previous.lastOrNull;
    final current = _TransferProgressSample(
      bytesTransferred: transfer.bytesTransferred,
      sampledAt: now,
    );
    if (latest != null && transfer.bytesTransferred < latest.bytesTransferred) {
      return <_TransferProgressSample>[current];
    }

    final cutoff = now.subtract(_sampleWindow);
    return <_TransferProgressSample>[
      for (final sample in previous)
        if (!sample.sampledAt.isBefore(cutoff)) sample,
      current,
    ];
  }

  int? _speedFor(List<_TransferProgressSample> samples) {
    if (samples.length < 2) {
      return null;
    }
    final oldest = samples.first;
    final newest = samples.last;
    final elapsed = newest.sampledAt.difference(oldest.sampledAt);
    if (elapsed < _minimumSampleAge) {
      return null;
    }
    final deltaBytes = newest.bytesTransferred - oldest.bytesTransferred;
    if (deltaBytes <= 0) {
      return 0;
    }
    return (deltaBytes * 1000 / elapsed.inMilliseconds).round();
  }

  _VisibleSpeedSample? _visibleSpeedFor(
    _VisibleSpeedSample? previous,
    int? next,
    DateTime now,
  ) {
    if (next == null || next <= 0) {
      if (previous == null) {
        return null;
      }
      if (now.difference(previous.updatedAt) < _displayUpdateInterval) {
        return previous;
      }
      return null;
    }
    if (previous != null &&
        now.difference(previous.updatedAt) < _displayUpdateInterval) {
      return previous;
    }
    return _VisibleSpeedSample(bytesPerSecond: next, updatedAt: now);
  }

  Duration? _etaFor(FileTransferRecord transfer, int bytesPerSecond) {
    if (bytesPerSecond <= 0 || transfer.fileSize <= 0) {
      return null;
    }
    final remaining = transfer.fileSize - transfer.bytesTransferred;
    if (remaining <= 0) {
      return Duration.zero;
    }
    return Duration(seconds: (remaining / bytesPerSecond).ceil());
  }
}

String formatFileTransferSpeed(int bytesPerSecond) {
  if (bytesPerSecond < 1024) {
    return '$bytesPerSecond B/s';
  }
  final kb = bytesPerSecond / 1024;
  if (kb < 1024) {
    return '${kb.round()} KB/s';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB/s';
}

class _TransferSpeedState {
  const _TransferSpeedState({
    required this.samples,
    required this.visibleSpeed,
  });

  final List<_TransferProgressSample> samples;
  final _VisibleSpeedSample? visibleSpeed;
}

class _TransferProgressSample {
  const _TransferProgressSample({
    required this.bytesTransferred,
    required this.sampledAt,
  });

  final int bytesTransferred;
  final DateTime sampledAt;
}

class _VisibleSpeedSample {
  const _VisibleSpeedSample({
    required this.bytesPerSecond,
    required this.updatedAt,
  });

  final int bytesPerSecond;
  final DateTime updatedAt;
}
