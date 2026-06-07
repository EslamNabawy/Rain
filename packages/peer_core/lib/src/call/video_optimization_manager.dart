import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_media_models.dart';

typedef OptimizationDiagnosticAppender = void Function(List<String> states, String value);
typedef OptimizationErrorRecorder = void Function(String? error);
typedef OptimizationDebugEmitter = void Function(
  String name, {
  String severity,
  String? message,
  Map<String, Object?> context,
});

class VideoOptimizationManager {
  VideoOptimizationManager({
    required OptimizationDiagnosticAppender appendDiagnostic,
    required OptimizationErrorRecorder recordError,
    required OptimizationDebugEmitter emitDebugEvent,
  }) : _appendDiagnostic = appendDiagnostic,
       _recordError = recordError,
       _emitDebugEvent = emitDebugEvent;

  final OptimizationDiagnosticAppender _appendDiagnostic;
  final OptimizationErrorRecorder _recordError;
  final OptimizationDebugEmitter _emitDebugEvent;

  Timer? _videoOptimizationTimer;
  CallVideoOptimizationProfile? _activeVideoOptimizationProfile;
  int _videoPressureSampleCount = 0;
  int _videoStableSampleCount = 0;

  CallVideoOptimizationProfile? get activeVideoOptimizationProfile =>
      _activeVideoOptimizationProfile;

  Future<void> startOptimization({
    required RTCPeerConnection connection,
    required int epoch,
    required bool autoVideoOptimizeEnabled,
    required RTCRtpSender? localVideoSender,
    required MediaStreamTrack? localVideoTrack,
    required bool Function(RTCPeerConnection connection) shouldIgnoreCallback,
    required bool Function() isEpochValid,
  }) async {
    stopOptimization();
    _videoPressureSampleCount = 0;
    _videoStableSampleCount = 0;
    if (!autoVideoOptimizeEnabled) {
      _appendDiagnostic(<String>[], 'videoOptimizationDisabled');
      return;
    }
    await _applyProfile(
      CallVideoOptimizationProfile.excellent,
      reason: 'initial',
      sender: localVideoSender,
    );
    if (shouldIgnoreCallback(connection) || !isEpochValid()) {
      return;
    }
    _videoOptimizationTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_sampleOptimization(
        connection: connection,
        epoch: epoch,
        localVideoSender: localVideoSender,
        localVideoTrack: localVideoTrack,
        shouldIgnoreCallback: shouldIgnoreCallback,
        isEpochValid: isEpochValid,
      )),
    );
  }

  Future<void> _sampleOptimization({
    required RTCPeerConnection connection,
    required int epoch,
    required RTCRtpSender? localVideoSender,
    required MediaStreamTrack? localVideoTrack,
    required bool Function(RTCPeerConnection connection) shouldIgnoreCallback,
    required bool Function() isEpochValid,
  }) async {
    if (shouldIgnoreCallback(connection) ||
        !isEpochValid() ||
        localVideoSender == null) {
      return;
    }
    final reports = await _safeVideoStats(connection, localVideoTrack);
    if (reports == null || reports.isEmpty) {
      return;
    }
    final target = _targetProfile(reports);
    if (target == null) {
      return;
    }

    final current = _activeVideoOptimizationProfile ?? CallVideoOptimizationProfile.excellent;
    if (target.index > current.index) {
      _videoPressureSampleCount += 1;
      _videoStableSampleCount = 0;
      if (_videoPressureSampleCount >= 2) {
        await _applyProfile(target, reason: 'pressure', sender: localVideoSender);
        _videoPressureSampleCount = 0;
      }
      return;
    }

    if (target.index < current.index) {
      _videoStableSampleCount += 1;
      _videoPressureSampleCount = 0;
      if (_videoStableSampleCount >= 5) {
        final nextProfile = CallVideoOptimizationProfile.values[current.index - 1];
        await _applyProfile(nextProfile, reason: 'recovery', sender: localVideoSender);
        _videoStableSampleCount = 0;
      }
      return;
    }

    _videoPressureSampleCount = 0;
    _videoStableSampleCount = 0;
  }

  Future<List<StatsReport>?> _safeVideoStats(
    RTCPeerConnection connection,
    MediaStreamTrack? localVideoTrack,
  ) async {
    try {
      return await connection.getStats(localVideoTrack);
    } catch (error) {
      _appendDiagnostic(<String>[], 'videoStats failed | $error');
      _recordError(error.toString());
      _emitDebugEvent(
        'video_stats_failed',
        severity: 'warning',
        message: error.toString(),
      );
      return null;
    }
  }

  CallVideoOptimizationProfile? _targetProfile(List<StatsReport> reports) {
    final rtt = _maxStat(reports, const <String>[
      'currentRoundTripTime',
      'roundTripTime',
    ]);
    final legacyRttMs = _maxStat(reports, const <String>['googRtt']);
    final effectiveRtt = rtt ?? (legacyRttMs == null ? null : legacyRttMs / 1000);
    final outgoingBitrate = _maxStat(reports, const <String>[
      'availableOutgoingBitrate',
      'googAvailableSendBandwidth',
    ]);
    final packetsLost = _maxStat(reports, const <String>['packetsLost']);
    final framesDropped = _maxStat(reports, const <String>['framesDropped']);
    final bandwidthLimited = reports.any((StatsReport report) {
      final reason = _stringStat(report.values, const <String>[
        'qualityLimitationReason',
      ]);
      return reason == 'bandwidth' || reason == 'cpu';
    });

    if (effectiveRtt == null &&
        outgoingBitrate == null &&
        packetsLost == null &&
        framesDropped == null &&
        !bandwidthLimited) {
      return null;
    }

    if ((effectiveRtt != null && effectiveRtt >= 0.8) ||
        (outgoingBitrate != null && outgoingBitrate < 350000)) {
      return CallVideoOptimizationProfile.poor;
    }
    if ((effectiveRtt != null && effectiveRtt >= 0.45) ||
        (outgoingBitrate != null && outgoingBitrate < 600000) ||
        (packetsLost != null && packetsLost >= 40) ||
        (framesDropped != null && framesDropped >= 30)) {
      return CallVideoOptimizationProfile.fair;
    }
    if ((effectiveRtt != null && effectiveRtt >= 0.25) ||
        (outgoingBitrate != null && outgoingBitrate < 1000000) ||
        (packetsLost != null && packetsLost >= 10) ||
        (framesDropped != null && framesDropped >= 10) ||
        bandwidthLimited) {
      return CallVideoOptimizationProfile.good;
    }
    return CallVideoOptimizationProfile.excellent;
  }

  Future<void> _applyProfile(
    CallVideoOptimizationProfile profile, {
    required String reason,
    required RTCRtpSender? sender,
  }) async {
    if (sender == null) {
      return;
    }
    try {
      final parameters = sender.parameters;
      final encodings = parameters.encodings;
      if (encodings == null || encodings.isEmpty) {
        parameters.encodings = <RTCRtpEncoding>[RTCRtpEncoding()];
      }
      for (final encoding in parameters.encodings ?? <RTCRtpEncoding>[]) {
        encoding.maxBitrate = profile.maxBitrateBps;
        encoding.maxFramerate = profile.maxFramerate;
        encoding.scaleResolutionDownBy = profile.scaleResolutionDownBy;
      }
      parameters.degradationPreference = RTCDegradationPreference.BALANCED;
      await sender.setParameters(parameters);
      _activeVideoOptimizationProfile = profile;
      _appendDiagnostic(<String>[], 'videoOptimization:${profile.name}:$reason');
      _emitDebugEvent(
        'video_optimization_profile_applied',
        context: <String, Object?>{
          'profile': profile.name,
          'reason': reason,
          'maxBitrateBps': profile.maxBitrateBps,
          'maxFramerate': profile.maxFramerate,
          'scaleResolutionDownBy': profile.scaleResolutionDownBy,
        },
      );
    } catch (error) {
      _appendDiagnostic(
        <String>[],
        'videoOptimization failed:${profile.name}:$reason | $error',
      );
      _recordError(error.toString());
      _emitDebugEvent(
        'video_optimization_profile_failed',
        severity: 'warning',
        message: error.toString(),
        context: <String, Object?>{'profile': profile.name, 'reason': reason},
      );
    }
  }

  void stopOptimization() {
    _videoOptimizationTimer?.cancel();
    _videoOptimizationTimer = null;
  }

  double? _maxStat(List<StatsReport> reports, Iterable<String> keys) {
    double? max;
    for (final report in reports) {
      final value = _doubleStat(report.values, keys);
      if (value == null) {
        continue;
      }
      max = max == null || value > max ? value : max;
    }
    return max;
  }

  double? _doubleStat(Map<dynamic, dynamic>? values, Iterable<String> keys) {
    if (values == null) {
      return null;
    }
    for (final key in keys) {
      final value = values[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  String? _stringStat(Map<dynamic, dynamic>? values, Iterable<String> keys) {
    if (values == null) {
      return null;
    }
    for (final key in keys) {
      final value = values[key];
      if (value == null) {
        continue;
      }
      final normalized = value.toString().trim().toLowerCase();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }
}
