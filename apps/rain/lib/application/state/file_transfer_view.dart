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
  FileTransferSpeedTracker({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, _TransferSpeedSample> _samples =
      <String, _TransferSpeedSample>{};

  List<FileTransferView> apply(List<FileTransferRecord> transfers) {
    final activeIds = <String>{};
    final views = <FileTransferView>[];

    for (final transfer in transfers) {
      if (!_shouldTrack(transfer)) {
        _samples.remove(transfer.id);
        views.add(FileTransferView(record: transfer));
        continue;
      }

      activeIds.add(transfer.id);
      final now = _now();
      final previous = _samples[transfer.id];
      final nextSpeed = _speedFor(transfer, previous, now);
      final smoothedSpeed = _smooth(previous?.bytesPerSecond, nextSpeed);
      _samples[transfer.id] = _TransferSpeedSample(
        bytesTransferred: transfer.bytesTransferred,
        sampledAt: now,
        bytesPerSecond: smoothedSpeed,
      );

      views.add(
        FileTransferView(
          record: transfer,
          speedBytesPerSecond: smoothedSpeed <= 0 ? null : smoothedSpeed,
          eta: _etaFor(transfer, smoothedSpeed),
        ),
      );
    }

    _samples.removeWhere(
      (String transferId, _) => !activeIds.contains(transferId),
    );
    return views;
  }

  bool _shouldTrack(FileTransferRecord transfer) {
    return transfer.state == FileTransferState.sending ||
        transfer.state == FileTransferState.receiving;
  }

  int _speedFor(
    FileTransferRecord transfer,
    _TransferSpeedSample? previous,
    DateTime now,
  ) {
    if (previous == null) {
      return 0;
    }
    final elapsedMs = now.difference(previous.sampledAt).inMilliseconds;
    final deltaBytes = transfer.bytesTransferred - previous.bytesTransferred;
    if (elapsedMs <= 0 || deltaBytes <= 0) {
      return previous.bytesPerSecond;
    }
    return (deltaBytes * 1000 / elapsedMs).round();
  }

  int _smooth(int? previous, int next) {
    if (next <= 0) {
      return previous ?? 0;
    }
    if (previous == null || previous <= 0) {
      return next;
    }
    return ((previous * 0.35) + (next * 0.65)).round();
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

class _TransferSpeedSample {
  const _TransferSpeedSample({
    required this.bytesTransferred,
    required this.sampledAt,
    required this.bytesPerSecond,
  });

  final int bytesTransferred;
  final DateTime sampledAt;
  final int bytesPerSecond;
}
