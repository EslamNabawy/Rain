/// # audio_level_sampler.dart
///
/// Samples audio levels from WebRTC StatsReports for both local and remote audio tracks. Uses direct audioLevel stats or derives levels from totalAudioEnergy deltas between samples.
///
/// **Key types:** VoiceAudioLevelStatsSampler
///
/// **Depends on:** flutter_webrtc, voice/voice_media_models, voice/webrtc_stats_parser

import 'dart:math' as math;

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'voice_media_models.dart';
import 'webrtc_stats_parser.dart';

enum _VoiceAudioLevelSide { local, remote, unknown }

/// Samples audio levels from WebRTC [StatsReport]s.
///
/// Uses either direct `audioLevel` stats or derives a level from
/// `totalAudioEnergy` / `totalSamplesDuration` deltas between samples.
final class VoiceAudioLevelStatsSampler {
  final Map<String, _VoiceAudioEnergyPoint> _previousEnergy =
      <String, _VoiceAudioEnergyPoint>{};

  VoiceMediaAudioLevel sample(
    Iterable<StatsReport> reports, {
    required int updatedAt,
  }) {
    double? remoteLevel;
    double? localLevel;
    var source = VoiceMediaAudioLevelSource.unavailable;
    final nextEnergy = <String, _VoiceAudioEnergyPoint>{};

    for (final report in reports) {
      if (!_isAudioReport(report)) {
        continue;
      }

      final side = _audioReportSide(report);
      final directLevel = _directAudioLevel(report.values);
      if (directLevel != null) {
        switch (side) {
          case _VoiceAudioLevelSide.remote:
            remoteLevel = _maxLevel(remoteLevel, directLevel);
            source = VoiceMediaAudioLevelSource.audioLevel;
            break;
          case _VoiceAudioLevelSide.local:
            localLevel = _maxLevel(localLevel, directLevel);
            source = VoiceMediaAudioLevelSource.audioLevel;
            break;
          case _VoiceAudioLevelSide.unknown:
            remoteLevel = _maxLevel(remoteLevel, directLevel);
            source = VoiceMediaAudioLevelSource.audioLevel;
            break;
        }
      }

      final energy = _VoiceAudioEnergyPoint.fromStats(report.values);
      if (energy == null) {
        continue;
      }
      if (report.id.isNotEmpty) {
        nextEnergy[report.id] = energy;
      }
      if (directLevel != null) {
        continue;
      }

      final previous = _previousEnergy[report.id];
      final energyLevel = previous == null
          ? null
          : _levelFromEnergyDelta(previous: previous, current: energy);
      if (energyLevel == null) {
        continue;
      }

      switch (side) {
        case _VoiceAudioLevelSide.remote:
          remoteLevel = _maxLevel(remoteLevel, energyLevel);
          if (source == VoiceMediaAudioLevelSource.unavailable) {
            source = VoiceMediaAudioLevelSource.totalAudioEnergy;
          }
          break;
        case _VoiceAudioLevelSide.local:
          localLevel = _maxLevel(localLevel, energyLevel);
          if (source == VoiceMediaAudioLevelSource.unavailable) {
            source = VoiceMediaAudioLevelSource.totalAudioEnergy;
          }
          break;
        case _VoiceAudioLevelSide.unknown:
          remoteLevel = _maxLevel(remoteLevel, energyLevel);
          if (source == VoiceMediaAudioLevelSource.unavailable) {
            source = VoiceMediaAudioLevelSource.totalAudioEnergy;
          }
          break;
      }
    }

    _previousEnergy
      ..clear()
      ..addAll(nextEnergy);

    if (remoteLevel == null && localLevel == null) {
      return VoiceMediaAudioLevel.unavailable(updatedAt: updatedAt);
    }

    return VoiceMediaAudioLevel(
      remoteLevel: remoteLevel ?? 0,
      localLevel: localLevel ?? 0,
      updatedAt: updatedAt,
      source: source,
    );
  }

  void reset() {
    _previousEnergy.clear();
  }
}

final class _VoiceAudioEnergyPoint {
  const _VoiceAudioEnergyPoint({
    required this.totalAudioEnergy,
    required this.totalSamplesDuration,
  });

  final double totalAudioEnergy;
  final double totalSamplesDuration;

  static _VoiceAudioEnergyPoint? fromStats(Map<dynamic, dynamic> values) {
    final energy = doubleStat(values, const <String>['totalAudioEnergy']);
    final duration = doubleStat(values, const <String>['totalSamplesDuration']);
    if (energy == null ||
        duration == null ||
        !energy.isFinite ||
        !duration.isFinite ||
        energy < 0 ||
        duration < 0) {
      return null;
    }
    return _VoiceAudioEnergyPoint(
      totalAudioEnergy: energy,
      totalSamplesDuration: duration,
    );
  }
}

bool _isAudioReport(StatsReport report) {
  final kind = stringStat(report.values, const <String>[
    'kind',
    'mediaType',
    'googTrackKind',
  ]);
  if (kind != null) {
    return kind.toLowerCase() == 'audio';
  }
  return hasAnyStat(report.values, const <String>[
    'audioLevel',
    'audioInputLevel',
    'audioOutputLevel',
    'totalAudioEnergy',
    'totalSamplesDuration',
  ]);
}

_VoiceAudioLevelSide _audioReportSide(StatsReport report) {
  final type = report.type.toLowerCase().replaceAll('_', '-');
  final remoteSource = boolStat(report.values, const <String>['remoteSource']);
  if (remoteSource == true ||
      type.contains('inbound') ||
      type.contains('receiver')) {
    return _VoiceAudioLevelSide.remote;
  }
  if (remoteSource == false ||
      type.contains('outbound') ||
      type.contains('sender') ||
      type == 'media-source') {
    return _VoiceAudioLevelSide.local;
  }
  final id = report.id.toLowerCase();
  if (id.contains('remote')) {
    return _VoiceAudioLevelSide.remote;
  }
  if (id.contains('local')) {
    return _VoiceAudioLevelSide.local;
  }
  return _VoiceAudioLevelSide.unknown;
}

double? _directAudioLevel(Map<dynamic, dynamic> values) {
  final audioLevel = doubleStat(values, const <String>['audioLevel']);
  if (audioLevel != null) {
    return _clampAudioLevel(audioLevel);
  }
  final legacyLevel = doubleStat(values, const <String>[
    'audioInputLevel',
    'audioOutputLevel',
  ]);
  if (legacyLevel == null || !legacyLevel.isFinite || legacyLevel <= 0) {
    return null;
  }
  return _clampAudioLevel(legacyLevel / 32768);
}

double? _levelFromEnergyDelta({
  required _VoiceAudioEnergyPoint previous,
  required _VoiceAudioEnergyPoint current,
}) {
  final energyDelta = current.totalAudioEnergy - previous.totalAudioEnergy;
  final durationDelta =
      current.totalSamplesDuration - previous.totalSamplesDuration;
  if (energyDelta < 0 || durationDelta <= 0) {
    return null;
  }
  return _clampAudioLevel(math.sqrt(energyDelta / durationDelta));
}

double _maxLevel(double? current, double next) {
  if (current == null || next > current) {
    return next;
  }
  return current;
}

double _clampAudioLevel(double value) {
  if (value.isNaN || !value.isFinite || value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 1;
  }
  return value;
}
