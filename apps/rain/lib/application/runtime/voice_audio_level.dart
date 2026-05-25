import 'package:protocol_brain/protocol_brain.dart'
    show VoiceMediaAudioLevel, VoiceMediaAudioLevelSource;

enum VoiceAudioLevelSource { unavailable, audioLevel, totalAudioEnergy }

final class VoiceAudioLevel {
  factory VoiceAudioLevel.available({
    required double remoteLevel,
    required double localLevel,
    required int updatedAt,
    required VoiceAudioLevelSource source,
  }) {
    return VoiceAudioLevel._(
      remoteLevel: _clampLevel(remoteLevel),
      localLevel: _clampLevel(localLevel),
      updatedAt: updatedAt,
      source: source,
    );
  }

  const VoiceAudioLevel._({
    required this.remoteLevel,
    required this.localLevel,
    required this.updatedAt,
    required this.source,
  });

  const VoiceAudioLevel.unavailable({this.updatedAt})
    : remoteLevel = 0,
      localLevel = 0,
      source = VoiceAudioLevelSource.unavailable;

  factory VoiceAudioLevel.fromMedia(VoiceMediaAudioLevel level) {
    if (!level.isAvailable || level.updatedAt == null) {
      return VoiceAudioLevel.unavailable(updatedAt: level.updatedAt);
    }
    return VoiceAudioLevel.available(
      remoteLevel: level.remoteLevel,
      localLevel: level.localLevel,
      updatedAt: level.updatedAt!,
      source: switch (level.source) {
        VoiceMediaAudioLevelSource.unavailable =>
          VoiceAudioLevelSource.unavailable,
        VoiceMediaAudioLevelSource.audioLevel =>
          VoiceAudioLevelSource.audioLevel,
        VoiceMediaAudioLevelSource.totalAudioEnergy =>
          VoiceAudioLevelSource.totalAudioEnergy,
      },
    );
  }

  final double remoteLevel;
  final double localLevel;
  final int? updatedAt;
  final VoiceAudioLevelSource source;

  bool get isAvailable => source != VoiceAudioLevelSource.unavailable;

  double get displayLevel {
    if (!isAvailable) {
      return 0;
    }
    return remoteLevel > 0 ? remoteLevel : localLevel;
  }
}

double _clampLevel(double value) {
  if (value.isNaN || !value.isFinite || value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 1;
  }
  return value;
}
