import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../voice/voice_media_models.dart';

enum CallMediaKind { audio, video }

enum CallVideoOptimizationProfile {
  excellent(maxBitrateBps: 1200000, maxFramerate: 30, scaleResolutionDownBy: 1),
  good(maxBitrateBps: 800000, maxFramerate: 24, scaleResolutionDownBy: 1),
  fair(maxBitrateBps: 450000, maxFramerate: 20, scaleResolutionDownBy: 1.5),
  poor(maxBitrateBps: 250000, maxFramerate: 15, scaleResolutionDownBy: 2);

  const CallVideoOptimizationProfile({
    required this.maxBitrateBps,
    required this.maxFramerate,
    required this.scaleResolutionDownBy,
  });

  final int maxBitrateBps;
  final int maxFramerate;
  final double scaleResolutionDownBy;
}

final class CallMediaProcessingConfig {
  const CallMediaProcessingConfig({
    this.clearVoiceEnabled = true,
    this.autoVideoOptimizeEnabled = true,
  });

  final bool clearVoiceEnabled;
  final bool autoVideoOptimizeEnabled;
}

enum CallMediaPhase {
  idle,
  startingLocalMedia,
  localMediaReady,
  creatingOffer,
  applyingOffer,
  applyingAnswer,
  connecting,
  connected,
  reconnecting,
  failed,
  disposed,
}

enum CallMediaFailureReason {
  microphoneDenied,
  cameraDenied,
  cameraUnavailable,
  mediaCaptureFailed,
  negotiationFailed,
}

typedef CallIceCandidate = VoiceIceCandidate;
typedef CallSessionDescription = VoiceSessionDescription;
typedef CallMediaOutputRoute = VoiceMediaOutputRoute;

final class CallMediaException implements Exception {
  const CallMediaException(this.reason, this.message, [this.cause]);

  final CallMediaFailureReason reason;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final causeText = cause == null ? '' : ' $cause';
    return '$message$causeText';
  }
}

final class CallMediaState {
  const CallMediaState({
    required this.phase,
    this.detail,
    this.error,
    this.failureReason,
    this.updatedAt,
  });

  const CallMediaState.idle()
    : phase = CallMediaPhase.idle,
      detail = null,
      error = null,
      failureReason = null,
      updatedAt = null;

  final CallMediaPhase phase;
  final String? detail;
  final Object? error;
  final CallMediaFailureReason? failureReason;
  final int? updatedAt;
}

final class CallMediaDiagnostics {
  const CallMediaDiagnostics({
    this.mediaStates = const <String>[],
    this.iceConnectionStates = const <String>[],
    this.peerConnectionStates = const <String>[],
    this.localCandidateCount = 0,
    this.remoteCandidateCount = 0,
    this.pendingRemoteCandidateCount = 0,
    this.remoteAudioTrackCount = 0,
    this.remoteVideoTrackCount = 0,
    this.remoteStreamCount = 0,
    this.hasLocalAudio = false,
    this.hasLocalVideo = false,
    this.peerConnectionClosed = false,
    this.disposed = false,
    this.processingConfig = const CallMediaProcessingConfig(),
    this.activeVideoOptimizationProfile,
    this.mediaInterruptions = const <String>[],
    this.lastDetail,
    this.lastError,
    this.lastFailureReason,
  });

  final List<String> mediaStates;
  final List<String> iceConnectionStates;
  final List<String> peerConnectionStates;
  final int localCandidateCount;
  final int remoteCandidateCount;
  final int pendingRemoteCandidateCount;
  final int remoteAudioTrackCount;
  final int remoteVideoTrackCount;
  final int remoteStreamCount;
  final bool hasLocalAudio;
  final bool hasLocalVideo;
  final bool peerConnectionClosed;
  final bool disposed;
  final CallMediaProcessingConfig processingConfig;
  final CallVideoOptimizationProfile? activeVideoOptimizationProfile;
  final List<String> mediaInterruptions;
  final String? lastDetail;
  final String? lastError;
  final CallMediaFailureReason? lastFailureReason;
}

final class CallRemoteMediaTrack {
  const CallRemoteMediaTrack({
    required this.track,
    required this.streams,
    required this.receivedAt,
  });

  final MediaStreamTrack track;
  final List<MediaStream> streams;
  final DateTime receivedAt;

  bool get isAudio => track.kind == 'audio';
  bool get isVideo => track.kind == 'video';
}
