import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/src/data_channel_backpressure.dart';

class _Channel extends Fake implements RTCDataChannel {
  _Channel({required this.buffered, required this.channelState});

  int buffered;
  RTCDataChannelState channelState;

  @override
  int? get bufferedAmount => buffered;

  @override
  RTCDataChannelState? get state => channelState;
}

void main() {
  const backpressure = DataChannelBackpressure(
    highWatermarkBytes: 100,
    lowWatermarkBytes: 10,
    pollInterval: Duration(milliseconds: 1),
    timeout: Duration(seconds: 5),
  );

  test('returns immediately below the high watermark', () async {
    final channel = _Channel(
      buffered: 50,
      channelState: RTCDataChannelState.RTCDataChannelOpen,
    );
    await backpressure.waitForDrain(channel);
  });

  test('returns once the buffer drains below the low watermark', () async {
    final channel = _Channel(
      buffered: 500,
      channelState: RTCDataChannelState.RTCDataChannelOpen,
    );
    Future<void>.delayed(
      const Duration(milliseconds: 20),
      () => channel.buffered = 0,
    );
    await backpressure.waitForDrain(channel);
  });

  test(
    'throws StateError promptly when the channel closes while waiting',
    () async {
      final channel = _Channel(
        buffered: 500,
        channelState: RTCDataChannelState.RTCDataChannelOpen,
      );
      Future<void>.delayed(
        const Duration(milliseconds: 20),
        () => channel.channelState = RTCDataChannelState.RTCDataChannelClosed,
      );
      final stopwatch = Stopwatch()..start();
      await expectLater(backpressure.waitForDrain(channel), throwsStateError);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    },
  );
}
