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
    targetPeak: 9000,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 96, frequency: 940, amplitude: 0.34),
      _Droplet(startMs: 44, lengthMs: 82, frequency: 1280, amplitude: 0.22),
    ],
    shimmer: const _Shimmer(amplitude: 0.0030, frequency: 2600),
  ),
  _SoundSpec(
    name: 'receive.wav',
    durationMs: 190,
    targetPeak: 9200,
    droplets: const <_Droplet>[
      _Droplet(startMs: 6, lengthMs: 132, frequency: 540, amplitude: 0.38),
      _Droplet(startMs: 76, lengthMs: 96, frequency: 760, amplitude: 0.22),
    ],
    shimmer: const _Shimmer(amplitude: 0.0026, frequency: 1900),
  ),
  _SoundSpec(
    name: 'action.wav',
    durationMs: 120,
    targetPeak: 8600,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 74, frequency: 720, amplitude: 0.30),
      _Droplet(startMs: 30, lengthMs: 54, frequency: 1080, amplitude: 0.14),
    ],
    shimmer: const _Shimmer(amplitude: 0.0024, frequency: 2400),
  ),
  _SoundSpec(
    name: 'error.wav',
    durationMs: 236,
    targetPeak: 10400,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 162,
        frequency: 220,
        amplitude: 0.56,
        sweep: -0.24,
      ),
      _Droplet(
        startMs: 86,
        lengthMs: 126,
        frequency: 165,
        amplitude: 0.34,
        sweep: -0.18,
      ),
    ],
    shimmer: const _Shimmer(amplitude: 0.0018, frequency: 720),
  ),
  _SoundSpec(
    name: 'call_incoming.wav',
    durationMs: 320,
    targetPeak: 9600,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 158, frequency: 440, amplitude: 0.28),
      _Droplet(startMs: 92, lengthMs: 152, frequency: 660, amplitude: 0.30),
      _Droplet(startMs: 182, lengthMs: 100, frequency: 880, amplitude: 0.16),
    ],
    shimmer: const _Shimmer(amplitude: 0.0026, frequency: 2100),
  ),
  _SoundSpec(
    name: 'call_outgoing.wav',
    durationMs: 240,
    targetPeak: 8800,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 134, frequency: 360, amplitude: 0.34),
      _Droplet(startMs: 78, lengthMs: 108, frequency: 540, amplitude: 0.22),
      _Droplet(startMs: 140, lengthMs: 70, frequency: 720, amplitude: 0.12),
    ],
    shimmer: const _Shimmer(amplitude: 0.0020, frequency: 1450),
  ),
  _SoundSpec(
    name: 'call_connected.wav',
    durationMs: 180,
    targetPeak: 9200,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 96, frequency: 620, amplitude: 0.30),
      _Droplet(startMs: 54, lengthMs: 94, frequency: 980, amplitude: 0.22),
      _Droplet(startMs: 96, lengthMs: 54, frequency: 1240, amplitude: 0.10),
    ],
    shimmer: const _Shimmer(amplitude: 0.0026, frequency: 2600),
  ),
  _SoundSpec(
    name: 'call_ended.wav',
    durationMs: 160,
    targetPeak: 8400,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 124,
        frequency: 430,
        amplitude: 0.34,
        sweep: -0.22,
      ),
    ],
    shimmer: const _Shimmer(amplitude: 0.0016, frequency: 980),
  ),
  _SoundSpec(
    name: 'call_failed.wav',
    durationMs: 250,
    targetPeak: 10400,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 155,
        frequency: 240,
        amplitude: 0.52,
        sweep: -0.24,
      ),
      _Droplet(
        startMs: 92,
        lengthMs: 145,
        frequency: 185,
        amplitude: 0.34,
        sweep: -0.20,
      ),
    ],
    shimmer: const _Shimmer(amplitude: 0.0016, frequency: 680),
  ),
  _SoundSpec(
    name: 'mute.wav',
    durationMs: 110,
    targetPeak: 8200,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 90,
        frequency: 390,
        amplitude: 0.30,
        sweep: -0.22,
      ),
    ],
    shimmer: const _Shimmer(amplitude: 0.0012, frequency: 780),
  ),
  _SoundSpec(
    name: 'unmute.wav',
    durationMs: 120,
    targetPeak: 8400,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 86, frequency: 520, amplitude: 0.28),
      _Droplet(startMs: 42, lengthMs: 58, frequency: 760, amplitude: 0.14),
    ],
    shimmer: const _Shimmer(amplitude: 0.0014, frequency: 1500),
  ),
  _SoundSpec(
    name: 'deafen.wav',
    durationMs: 130,
    targetPeak: 8400,
    droplets: const <_Droplet>[
      _Droplet(
        startMs: 0,
        lengthMs: 110,
        frequency: 260,
        amplitude: 0.38,
        sweep: -0.22,
      ),
      _Droplet(startMs: 24, lengthMs: 60, frequency: 190, amplitude: 0.16),
    ],
    shimmer: const _Shimmer(amplitude: 0.0012, frequency: 620),
  ),
  _SoundSpec(
    name: 'undeafen.wav',
    durationMs: 130,
    targetPeak: 8600,
    droplets: const <_Droplet>[
      _Droplet(startMs: 0, lengthMs: 100, frequency: 430, amplitude: 0.30),
      _Droplet(startMs: 48, lengthMs: 66, frequency: 710, amplitude: 0.16),
    ],
    shimmer: const _Shimmer(amplitude: 0.0014, frequency: 1320),
  ),
  _SoundSpec(
    name: 'call_incoming_loop.wav',
    durationMs: 1600,
    targetPeak: 9200,
    droplets: const <_Droplet>[
      _Droplet(startMs: 140, lengthMs: 280, frequency: 392, amplitude: 0.28),
      _Droplet(startMs: 245, lengthMs: 230, frequency: 523, amplitude: 0.18),
      _Droplet(startMs: 690, lengthMs: 270, frequency: 440, amplitude: 0.24),
      _Droplet(startMs: 1000, lengthMs: 240, frequency: 660, amplitude: 0.18),
      _Droplet(startMs: 1210, lengthMs: 210, frequency: 523, amplitude: 0.12),
    ],
    shimmer: const _Shimmer(amplitude: 0.0012, frequency: 1500),
    bedFrequency: 98,
    bedAmplitude: 0.004,
    loopSafe: true,
  ),
  _SoundSpec(
    name: 'call_outgoing_loop.wav',
    durationMs: 1500,
    targetPeak: 8400,
    droplets: const <_Droplet>[
      _Droplet(startMs: 170, lengthMs: 230, frequency: 330, amplitude: 0.24),
      _Droplet(startMs: 640, lengthMs: 220, frequency: 392, amplitude: 0.20),
      _Droplet(startMs: 1080, lengthMs: 220, frequency: 330, amplitude: 0.16),
    ],
    shimmer: const _Shimmer(amplitude: 0.0010, frequency: 1080),
    bedFrequency: 82,
    bedAmplitude: 0.003,
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
    sample +=
        spec.bedAmplitude *
        math.sin(_tau * spec.bedFrequency * t) *
        (0.72 + 0.28 * math.sin(_tau * spec.bedFrequency * 0.25 * t));
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
    final attack = (progress / 0.12).clamp(0.0, 1.0);
    final decay =
        math.exp(-5.2 * progress) * math.pow(1.0 - progress, 0.86).toDouble();
    final frequencyNow = frequency * (1 + sweep * (1 - progress));
    final phase = _tau * frequencyNow * local;
    final attackGain = math.sin(attack * math.pi / 2);
    final fundamental = math.sin(phase);
    final bellPartial = 0.052 * math.sin(_tau * frequencyNow * 1.618 * local);
    final glassPartial = 0.026 * math.sin(_tau * frequencyNow * 2.414 * local);
    return amplitude *
        (fundamental + bellPartial + glassPartial) *
        attackGain *
        decay;
  }
}

final class _Shimmer {
  const _Shimmer({required this.amplitude, required this.frequency});

  final double amplitude;
  final double frequency;

  double sample(double timeSeconds, int index, double progress) {
    final grainIndex = index ~/ 20;
    final grainProgress = (index % 20) / 20;
    final smoothNoise = _lerp(
      _noise(grainIndex),
      _noise(grainIndex + 1),
      grainProgress,
    );
    final noise = smoothNoise * amplitude * math.pow(1 - progress, 2.8);
    final ripple =
        math.sin(_tau * frequency * timeSeconds) *
        amplitude *
        0.12 *
        math.sin(math.pi * progress);
    return noise + ripple;
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _noise(int index) {
  var value = (index + 1) * 1103515245 + 12345;
  value = (value ^ (value >> 11)) & 0x7fffffff;
  return value / 0x3fffffff - 1.0;
}
