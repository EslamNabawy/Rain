import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

final class DataChannelBackpressure {
  const DataChannelBackpressure({
    this.highWatermarkBytes = 1024 * 1024,
    this.lowWatermarkBytes = 256 * 1024,
    this.pollInterval = const Duration(milliseconds: 20),
    this.timeout = const Duration(seconds: 10),
  }) : assert(highWatermarkBytes > 0),
       assert(lowWatermarkBytes >= 0),
       assert(lowWatermarkBytes <= highWatermarkBytes);

  final int highWatermarkBytes;
  final int lowWatermarkBytes;
  final Duration pollInterval;
  final Duration timeout;

  bool isAboveHighWatermark(RTCDataChannel channel) {
    return (channel.bufferedAmount ?? 0) >= highWatermarkBytes;
  }

  Future<void> waitForDrain(RTCDataChannel channel) async {
    if (!isAboveHighWatermark(channel)) {
      return;
    }
    final deadline = DateTime.now().add(timeout);
    while ((channel.bufferedAmount ?? 0) > lowWatermarkBytes) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'RTCDataChannel bufferedAmount did not drain below '
          '$lowWatermarkBytes bytes.',
          timeout,
        );
      }
      await Future<void>.delayed(pollInterval);
    }
  }
}
