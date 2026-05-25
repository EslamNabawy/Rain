import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/voice_audio_level.dart';

void main() {
  test('VoiceAudioLevel maps media audioLevel samples', () {
    final level = VoiceAudioLevel.fromMedia(
      VoiceMediaAudioLevel(
        remoteLevel: 0.35,
        localLevel: 0.12,
        updatedAt: 42,
        source: VoiceMediaAudioLevelSource.audioLevel,
      ),
    );

    expect(level.isAvailable, isTrue);
    expect(level.remoteLevel, 0.35);
    expect(level.localLevel, 0.12);
    expect(level.displayLevel, 0.35);
    expect(level.updatedAt, 42);
    expect(level.source, VoiceAudioLevelSource.audioLevel);
  });

  test('VoiceAudioLevel maps unavailable samples without fake activity', () {
    final level = VoiceAudioLevel.fromMedia(
      const VoiceMediaAudioLevel.unavailable(updatedAt: 7),
    );

    expect(level.isAvailable, isFalse);
    expect(level.remoteLevel, 0);
    expect(level.localLevel, 0);
    expect(level.displayLevel, 0);
    expect(level.updatedAt, 7);
  });

  test('VoiceAudioLevel clamps invalid values to display range', () {
    final level = VoiceAudioLevel.available(
      remoteLevel: double.nan,
      localLevel: 4,
      updatedAt: 9,
      source: VoiceAudioLevelSource.totalAudioEnergy,
    );

    expect(level.remoteLevel, 0);
    expect(level.localLevel, 1);
    expect(level.displayLevel, 1);
  });
}
