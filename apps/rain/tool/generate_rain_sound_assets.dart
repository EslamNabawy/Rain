import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int _sampleRate = 44100;
const int _bitsPerSample = 16;
const int _channels = 1;

void main() {
  final scriptFile = File.fromUri(Platform.script);
  final appDir = scriptFile.parent.parent;
  final soundsDir = Directory(_join(appDir.path, 'assets', 'sounds'));
  if (!soundsDir.existsSync()) {
    soundsDir.createSync(recursive: true);
  }

  for (final spec in _assetSpecs) {
    final file = File(_join(soundsDir.path, spec.name));
    file.writeAsBytesSync(_buildWave(spec), flush: true);
    stdout.writeln('wrote ${file.path}');
  }
}

final List<_SoundSpec> _assetSpecs = <_SoundSpec>[
  _SoundSpec(
    name: 'send.wav',
    durationMs: 156,
    targetPeak: 10400,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 104, frequency: 690, amplitude: 0.52),
      _Droplet(startMs: 48, lengthMs: 74, frequency: 920, amplitude: 0.24),
    ],
    shimmer: const _Shimmer(amplitude: 0.010, frequency: 1700),
  ),
  _SoundSpec(
    name: 'receive.wav',
    durationMs: 190,
    targetPeak: 11000,
    droplets: const <_Droplet>[
      _Droplet(startMs: 6, lengthMs: 124, frequency: 470, amplitude: 0.54),
      _Droplet(startMs: 80, lengthMs: 92, frequency: 720, amplitude: 0.30),
    ],
    shimmer: const _Shimmer(amplitude: 0.009, frequency: 1450),
  ),
  _SoundSpec(
    name: 'action.wav',
    durationMs: 120,
    targetPeak: 9600,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 88, frequency: 610, amplitude: 0.44),
      _Droplet(startMs: 36, lengthMs: 58, frequency: 840, amplitude: 0.20),
    ],
    shimmer: const _Shimmer(amplitude: 0.008, frequency: 1650),
  ),
  _SoundSpec(
    name: 'error.wav',
    durationMs: 236,
    targetPeak: 11200,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 158,
        frequency: 330,
        amplitude: 0.62,
        sweep: -0.20,
      ),
      _Droplet(
        startMs: 92,
        lengthMs: 116,
        frequency: 250,
        amplitude: 0.44,
        sweep: -0.16,
      ),
    ],
    shimmer: const _Shimmer(amplitude: 0.008, frequency: 860),
  ),
  _SoundSpec(
    name: 'call_incoming.wav',
    durationMs: 320,
    targetPeak: 12200,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 164, frequency: 520, amplitude: 0.44),
      _Droplet(startMs: 96, lengthMs: 156, frequency: 760, amplitude: 0.44),
      _Droplet(startMs: 188, lengthMs: 104, frequency: 610, amplitude: 0.28),
    ],
    shimmer: const _Shimmer(amplitude: 0.010, frequency: 1800),
  ),
  _SoundSpec(
    name: 'call_outgoing.wav',
    durationMs: 240,
    targetPeak: 10600,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 134, frequency: 390, amplitude: 0.44),
      _Droplet(startMs: 76, lengthMs: 108, frequency: 560, amplitude: 0.34),
      _Droplet(startMs: 140, lengthMs: 72, frequency: 760, amplitude: 0.20),
    ],
    shimmer: const _Shimmer(amplitude: 0.008, frequency: 1300),
  ),
  _SoundSpec(
    name: 'call_connected.wav',
    durationMs: 180,
    targetPeak: 10800,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 102, frequency: 640, amplitude: 0.42),
      _Droplet(startMs: 58, lengthMs: 94, frequency: 920, amplitude: 0.30),
    ],
    shimmer: const _Shimmer(amplitude: 0.010, frequency: 1950),
  ),
  _SoundSpec(
    name: 'call_ended.wav',
    durationMs: 160,
    targetPeak: 9400,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 124,
        frequency: 520,
        amplitude: 0.44,
        sweep: -0.20,
      ),
    ],
    shimmer: const _Shimmer(amplitude: 0.006, frequency: 1100),
  ),
  _SoundSpec(
    name: 'call_failed.wav',
    durationMs: 250,
    targetPeak: 11000,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 155,
        frequency: 310,
        amplitude: 0.56,
        sweep: -0.20,
      ),
      _Droplet(
        startMs: 92,
        lengthMs: 145,
        frequency: 235,
        amplitude: 0.42,
        sweep: -0.18,
      ),
    ],
    shimmer: const _Shimmer(amplitude: 0.007, frequency: 820),
  ),
  _SoundSpec(
    name: 'mute.wav',
    durationMs: 110,
    targetPeak: 8800,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 90,
        frequency: 440,
        amplitude: 0.38,
        sweep: -0.18,
      ),
    ],
    shimmer: const _Shimmer(amplitude: 0.004, frequency: 900),
  ),
  _SoundSpec(
    name: 'unmute.wav',
    durationMs: 120,
    targetPeak: 9000,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 88, frequency: 520, amplitude: 0.34),
      _Droplet(startMs: 44, lengthMs: 58, frequency: 780, amplitude: 0.18),
    ],
    shimmer: const _Shimmer(amplitude: 0.005, frequency: 1400),
  ),
  _SoundSpec(
    name: 'deafen.wav',
    durationMs: 130,
    targetPeak: 9000,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 110,
        frequency: 300,
        amplitude: 0.46,
        sweep: -0.20,
      ),
      _Droplet(startMs: 24, lengthMs: 60, frequency: 220, amplitude: 0.24),
    ],
    shimmer: const _Shimmer(amplitude: 0.004, frequency: 760),
  ),
  _SoundSpec(
    name: 'undeafen.wav',
    durationMs: 130,
    targetPeak: 9400,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 100, frequency: 430, amplitude: 0.38),
      _Droplet(startMs: 48, lengthMs: 66, frequency: 710, amplitude: 0.24),
    ],
    shimmer: const _Shimmer(amplitude: 0.005, frequency: 1250),
  ),
  _SoundSpec(
    name: 'call_incoming_loop.wav',
    durationMs: 1600,
    targetPeak: 10600,
    droplets: const <_Droplet>[
      _Droplet(startMs: 130, lengthMs: 260, frequency: 520, amplitude: 0.36),
      _Droplet(startMs: 470, lengthMs: 250, frequency: 760, amplitude: 0.34),
      _Droplet(startMs: 850, lengthMs: 260, frequency: 560, amplitude: 0.30),
      _Droplet(startMs: 1190, lengthMs: 240, frequency: 820, amplitude: 0.28),
    ],
    shimmer: const _Shimmer(amplitude: 0.004, frequency: 1550),
    bedFrequency: 142,
    bedAmplitude: 0.020,
    loopSafe: true,
  ),
  _SoundSpec(
    name: 'call_outgoing_loop.wav',
    durationMs: 1500,
    targetPeak: 9400,
    droplets: const <_Droplet>[
      _Droplet(startMs: 150, lengthMs: 230, frequency: 390, amplitude: 0.30),
      _Droplet(startMs: 570, lengthMs: 220, frequency: 560, amplitude: 0.28),
      _Droplet(startMs: 1020, lengthMs: 230, frequency: 440, amplitude: 0.24),
    ],
    shimmer: const _Shimmer(amplitude: 0.004, frequency: 1100),
    bedFrequency: 118,
    bedAmplitude: 0.018,
    loopSafe: true,
  ),
];

Uint8List _buildWave(_SoundSpec spec) {
  final sampleCount = (_sampleRate * spec.durationMs / 1000).round();
  final raw = Float64List(sampleCount);
  var peak = 0.0;
  for (var i = 0; i < sampleCount; i += 1) {
    final t = i / _sampleRate;
    final progress = i / math.max(1, sampleCount - 1);
    var sample = 0.0;
    for (final droplet in spec.droplets) {
      sample += droplet.sample(t);
    }
    sample += spec.shimmer.sample(t, i, progress);
    sample += spec.bedAmplitude * math.sin(_tau * spec.bedFrequency * t);
    sample *= spec.loopSafe
        ? math.sin(math.pi * progress)
        : _envelope(progress, attack: 0.04, release: 0.18);
    raw[i] = sample;
    peak = math.max(peak, sample.abs());
  }

  final scale = peak == 0 ? 0.0 : spec.targetPeak / peak;
  final dataSize = sampleCount * 2;
  final bytes = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(bytes);
  _writeAscii(bytes, 0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  _writeAscii(bytes, 8, 'WAVE');
  _writeAscii(bytes, 12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, _channels, Endian.little);
  data.setUint32(24, _sampleRate, Endian.little);
  data.setUint32(
    28,
    _sampleRate * _channels * _bitsPerSample ~/ 8,
    Endian.little,
  );
  data.setUint16(32, _channels * _bitsPerSample ~/ 8, Endian.little);
  data.setUint16(34, _bitsPerSample, Endian.little);
  _writeAscii(bytes, 36, 'data');
  data.setUint32(40, dataSize, Endian.little);

  var offset = 44;
  for (final sample in raw) {
    final pcm = (sample * scale).round().clamp(-32767, 32767);
    data.setInt16(offset, pcm, Endian.little);
    offset += 2;
  }
  return bytes;
}

double _envelope(
  double progress, {
  required double attack,
  required double release,
}) {
  final attackGain = attack <= 0 ? 1.0 : (progress / attack).clamp(0.0, 1.0);
  final releaseGain = release <= 0
      ? 1.0
      : ((1.0 - progress) / release).clamp(0.0, 1.0);
  return math.sin(attackGain * math.pi / 2) *
      math.sin(releaseGain * math.pi / 2);
}

void _writeAscii(Uint8List bytes, int offset, String value) {
  for (var i = 0; i < value.length; i += 1) {
    bytes[offset + i] = value.codeUnitAt(i);
  }
}

String _join(String part1, String part2, [String? part3, String? part4]) {
  return <String?>[
    part1,
    part2,
    part3,
    part4,
  ].whereType<String>().join(Platform.pathSeparator);
}

const double _tau = math.pi * 2;

final class _SoundSpec {
  const _SoundSpec({
    required this.name,
    required this.durationMs,
    required this.targetPeak,
    required this.droplets,
    required this.shimmer,
    this.bedFrequency = 0,
    this.bedAmplitude = 0,
    this.loopSafe = false,
  });

  final String name;
  final int durationMs;
  final int targetPeak;
  final List<_Droplet> droplets;
  final _Shimmer shimmer;
  final double bedFrequency;
  final double bedAmplitude;
  final bool loopSafe;
}

final class _Droplet {
  const _Droplet({
    required this.startMs,
    required this.lengthMs,
    required this.frequency,
    required this.amplitude,
    this.sweep = 0.12,
  });

  final double startMs;
  final double lengthMs;
  final double frequency;
  final double amplitude;
  final double sweep;

  double sample(double timeSeconds) {
    final local = timeSeconds - startMs / 1000;
    final lengthSeconds = lengthMs / 1000;
    if (local < 0 || local > lengthSeconds) {
      return 0;
    }
    final progress = local / lengthSeconds;
    final attack = (progress / 0.11).clamp(0.0, 1.0);
    final decay =
        math.exp(-4.4 * progress) * math.pow(1.0 - progress, 0.72).toDouble();
    final frequencyNow = frequency * (1 + sweep * (1 - progress));
    final phase = _tau * frequencyNow * local;
    final secondPartial = 0.10 * math.sin(_tau * frequencyNow * 1.72 * local);
    return amplitude *
            math.sin(phase) *
            math.sin(attack * math.pi / 2) *
            decay +
        amplitude * secondPartial * decay;
  }
}

final class _Shimmer {
  const _Shimmer({required this.amplitude, required this.frequency});

  final double amplitude;
  final double frequency;

  double sample(double timeSeconds, int index, double progress) {
    final noise = _noise(index) * amplitude * math.pow(1 - progress, 2.4);
    final ripple =
        math.sin(_tau * frequency * timeSeconds) *
        amplitude *
        0.18 *
        math.sin(math.pi * progress);
    return noise + ripple;
  }
}

double _noise(int index) {
  var value = (index + 1) * 1103515245 + 12345;
  value = (value ^ (value >> 11)) & 0x7fffffff;
  return value / 0x3fffffff - 1.0;
}
