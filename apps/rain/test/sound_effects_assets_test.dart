import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const sounds = <String, _SoundExpectation>{
    'action.wav': _SoundExpectation(minMs: 100, maxMs: 140),
    'send.wav': _SoundExpectation(minMs: 140, maxMs: 175),
    'receive.wav': _SoundExpectation(minMs: 175, maxMs: 210),
    'error.wav': _SoundExpectation(minMs: 215, maxMs: 255),
  };

  for (final entry in sounds.entries) {
    test('${entry.key} is a polished low-latency UI sound', () {
      final info = _readWaveInfo('assets/sounds/${entry.key}');

      expect(info.channels, 1);
      expect(info.sampleRate, 44100);
      expect(info.bitsPerSample, 16);
      expect(
        info.durationMs,
        inInclusiveRange(entry.value.minMs, entry.value.maxMs),
      );
      expect(info.peak, greaterThan(8000));
      expect(info.peak, lessThan(32767));
      expect(info.rms, greaterThan(800));
    });
  }
}

class _SoundExpectation {
  const _SoundExpectation({required this.minMs, required this.maxMs});

  final int minMs;
  final int maxMs;
}

class _WaveInfo {
  const _WaveInfo({
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.durationMs,
    required this.peak,
    required this.rms,
  });

  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final double durationMs;
  final int peak;
  final double rms;
}

_WaveInfo _readWaveInfo(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');

  var offset = 12;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataSize;

  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkDataOffset = offset + 8;

    if (chunkId == 'fmt ') {
      channels = data.getUint16(chunkDataOffset + 2, Endian.little);
      sampleRate = data.getUint32(chunkDataOffset + 4, Endian.little);
      bitsPerSample = data.getUint16(chunkDataOffset + 14, Endian.little);
    } else if (chunkId == 'data') {
      dataOffset = chunkDataOffset;
      dataSize = chunkSize;
    }

    offset = chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  expect(channels, isNotNull);
  expect(sampleRate, isNotNull);
  expect(bitsPerSample, isNotNull);
  expect(dataOffset, isNotNull);
  expect(dataSize, isNotNull);

  var peak = 0;
  var sumSquares = 0.0;
  var sampleCount = 0;
  final audioEnd = dataOffset! + dataSize!;
  for (var index = dataOffset; index + 1 < audioEnd; index += 2) {
    final sample = data.getInt16(index, Endian.little);
    final absolute = sample.abs();
    if (absolute > peak) {
      peak = absolute;
    }
    sumSquares += sample * sample;
    sampleCount += 1;
  }

  return _WaveInfo(
    channels: channels!,
    sampleRate: sampleRate!,
    bitsPerSample: bitsPerSample!,
    durationMs: sampleCount / sampleRate * 1000,
    peak: peak,
    rms: sampleCount == 0 ? 0 : math.sqrt(sumSquares / sampleCount),
  );
}
