/// # sound_effects_assets_test.dart
///
/// Validates sound effect asset files exist, are unique, have correct WAV properties (sample rate, bit depth, duration, RMS), and that the asset map covers all RainSoundEffect enum values.
///
/// **Key types:** _SoundExpectation, _WaveInfo, RainSoundEffect
///
/// **Depends on:** package:rain/infrastructure/services/sound_effects_service.dart
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';

void main() {
  const oneShotSounds = <String, _SoundExpectation>{
    'sounds/action.wav': _SoundExpectation(minMs: 100, maxMs: 140),
    'sounds/call_connected.wav': _SoundExpectation(minMs: 170, maxMs: 190),
    'sounds/call_ended.wav': _SoundExpectation(minMs: 150, maxMs: 170),
    'sounds/call_failed.wav': _SoundExpectation(minMs: 240, maxMs: 260),
    'sounds/call_incoming.wav': _SoundExpectation(minMs: 310, maxMs: 330),
    'sounds/call_outgoing.wav': _SoundExpectation(minMs: 230, maxMs: 250),
    'sounds/deafen.wav': _SoundExpectation(minMs: 120, maxMs: 140),
    'sounds/error.wav': _SoundExpectation(minMs: 215, maxMs: 255),
    'sounds/mute.wav': _SoundExpectation(minMs: 100, maxMs: 120),
    'sounds/receive.wav': _SoundExpectation(minMs: 175, maxMs: 210),
    'sounds/send.wav': _SoundExpectation(minMs: 140, maxMs: 175),
    'sounds/undeafen.wav': _SoundExpectation(minMs: 120, maxMs: 140),
    'sounds/unmute.wav': _SoundExpectation(minMs: 110, maxMs: 130),
    'sounds/camera_on.wav': _SoundExpectation(minMs: 115, maxMs: 145),
    'sounds/camera_off.wav': _SoundExpectation(minMs: 115, maxMs: 145),
    'sounds/route_change.wav': _SoundExpectation(minMs: 75, maxMs: 105),
    'sounds/request_inbound.wav': _SoundExpectation(
      minMs: 405,
      maxMs: 435,
      maxBytes: 40000,
    ),
    'sounds/request_accepted.wav': _SoundExpectation(minMs: 245, maxMs: 260),
    'sounds/transfer_complete.wav': _SoundExpectation(minMs: 245, maxMs: 275),
  };

  const loopSounds = <String, _SoundExpectation>{
    'sounds/call_incoming_loop.wav': _SoundExpectation(
      minMs: 1550,
      maxMs: 1650,
      maxBytes: 150000,
      minRms: 500,
    ),
    'sounds/call_outgoing_loop.wav': _SoundExpectation(
      minMs: 1450,
      maxMs: 1550,
      maxBytes: 140000,
      minRms: 450,
    ),
  };

  test('sound effect asset map references existing unique wav files', () {
    expect(rainSoundEffectAssetPaths.keys, containsAll(RainSoundEffect.values));
    expect(
      rainSoundEffectAssetPaths.values.toSet(),
      hasLength(RainSoundEffect.values.length),
    );

    for (final assetPath in rainSoundEffectAssetPaths.values) {
      expect(oneShotSounds, contains(assetPath));
      expect(_soundFile('assets/$assetPath').existsSync(), isTrue);
    }
  });

  test('loop asset map references existing ringtone assets', () {
    expect(
      rainSoundEffectLoopAssetPaths,
      containsPair(
        RainSoundEffect.callIncoming,
        'sounds/call_incoming_loop.wav',
      ),
    );
    expect(
      rainSoundEffectLoopAssetPaths,
      containsPair(
        RainSoundEffect.callOutgoing,
        'sounds/call_outgoing_loop.wav',
      ),
    );

    for (final assetPath in rainSoundEffectLoopAssetPaths.values) {
      expect(loopSounds, contains(assetPath));
      expect(_soundFile('assets/$assetPath').existsSync(), isTrue);
    }
  });

  for (final entry in oneShotSounds.entries) {
    test('${entry.key} is a polished low-latency UI sound', () {
      final info = _readWaveInfo('assets/${entry.key}');

      _expectPcmWave(info);
      expect(
        info.durationMs,
        inInclusiveRange(entry.value.minMs, entry.value.maxMs),
      );
      expect(info.fileSizeBytes, lessThanOrEqualTo(entry.value.maxBytes));
      expect(info.peak, greaterThan(entry.value.minPeak));
      expect(info.peak, lessThan(30000));
      expect(info.rms, greaterThan(entry.value.minRms));
      // Alert cues (calls, inbound requests) may run longer than UI feedback.
      if (!entry.key.contains('/call_') &&
          !entry.key.endsWith('/request_inbound.wav')) {
        expect(info.durationMs, lessThanOrEqualTo(260));
      }
    });
  }

  for (final entry in loopSounds.entries) {
    test('${entry.key} is a loop-safe ringtone asset', () {
      final info = _readWaveInfo('assets/${entry.key}');

      _expectPcmWave(info);
      expect(
        info.durationMs,
        inInclusiveRange(entry.value.minMs, entry.value.maxMs),
      );
      expect(info.durationMs, lessThan(6000));
      expect(info.fileSizeBytes, lessThanOrEqualTo(entry.value.maxBytes));
      expect(info.peak, greaterThan(entry.value.minPeak));
      expect(info.peak, lessThan(30000));
      expect(info.rms, greaterThan(entry.value.minRms));
      expect(info.firstSample.abs(), lessThan(512));
      expect(info.lastSample.abs(), lessThan(512));
    });
  }

  test('one-shot loudness stays within 3 dB of its group median', () {
    const groups = <String, List<String>>{
      'chat': <String>['send', 'receive'],
      'ui': <String>[
        'action',
        'route_change',
        'camera_on',
        'camera_off',
        'mute',
        'unmute',
        'deafen',
        'undeafen',
      ],
      'state': <String>[
        'call_connected',
        'call_ended',
        'request_accepted',
        'transfer_complete',
      ],
      'alert': <String>[
        'error',
        'call_failed',
        'request_inbound',
        'call_incoming',
        'call_outgoing',
      ],
    };

    for (final group in groups.entries) {
      final levels = <String, double>{
        for (final name in group.value)
          name: _rmsDb(_readWaveInfo('assets/sounds/$name.wav').rms),
      };
      final sorted = levels.values.toList()..sort();
      final mid = sorted.length ~/ 2;
      final median = sorted.length.isOdd
          ? sorted[mid]
          : (sorted[mid - 1] + sorted[mid]) / 2;
      for (final level in levels.entries) {
        expect(
          (level.value - median).abs(),
          lessThanOrEqualTo(3.0),
          reason:
              '${level.key}.wav is ${level.value.toStringAsFixed(1)} dBFS, '
              '${group.key} median ${median.toStringAsFixed(1)} dBFS',
        );
      }
    }
  });

  test('total sound asset size stays modest for APK impact', () {
    final assetPaths = <String>{
      ...rainSoundEffectAssetPaths.values,
      ...rainSoundEffectLoopAssetPaths.values,
    };
    final totalBytes = assetPaths.fold<int>(
      0,
      (total, assetPath) =>
          total + _soundFile('assets/$assetPath').lengthSync(),
    );

    // 500 KB for the original 15 files plus ~115 KB for the six distinct
    // camera, route, request and transfer cues (UI/UX program T3.2/T3.3).
    expect(totalBytes, lessThanOrEqualTo(620000));
  });
}

double _rmsDb(double rms) => 20 * math.log(rms / 32768) / math.ln10;

class _SoundExpectation {
  const _SoundExpectation({
    required this.minMs,
    required this.maxMs,
    this.minRms = 800,
    this.maxBytes = 36000,
  }) : minPeak = 8000;

  final int minMs;
  final int maxMs;
  final int minPeak;
  final int minRms;
  final int maxBytes;
}

class _WaveInfo {
  const _WaveInfo({
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.durationMs,
    required this.peak,
    required this.rms,
    required this.fileSizeBytes,
    required this.firstSample,
    required this.lastSample,
  });

  final int channels;
  final int sampleRate;
  final int bitsPerSample;
  final double durationMs;
  final int peak;
  final double rms;
  final int fileSizeBytes;
  final int firstSample;
  final int lastSample;
}

_WaveInfo _readWaveInfo(String path) {
  final bytes = _soundFile(path).readAsBytesSync();
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
  var firstSample = 0;
  var lastSample = 0;
  final audioEnd = dataOffset! + dataSize!;
  for (var index = dataOffset; index + 1 < audioEnd; index += 2) {
    final sample = data.getInt16(index, Endian.little);
    if (sampleCount == 0) {
      firstSample = sample;
    }
    lastSample = sample;
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
    fileSizeBytes: bytes.length,
    firstSample: firstSample,
    lastSample: lastSample,
  );
}

void _expectPcmWave(_WaveInfo info) {
  expect(info.channels, 1);
  expect(info.sampleRate, 44100);
  expect(info.bitsPerSample, 16);
}

File _soundFile(String path) {
  for (final candidate in <String>[path, 'apps/rain/$path']) {
    final file = File(candidate);
    if (file.existsSync()) {
      return file;
    }
  }
  fail('Could not locate $path.');
}
