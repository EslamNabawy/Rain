import 'package:flutter_webrtc/flutter_webrtc.dart';

enum VoiceMediaAudioLevelSource { unavailable, audioLevel, totalAudioEnergy }

enum VoiceMediaOutputRoute { systemDefault, speaker, bluetooth }

enum VoiceMediaPhase {
  idle,
  startingLocalAudio,
  localAudioReady,
  creatingOffer,
  applyingOffer,
  applyingAnswer,
  connecting,
  connected,
  failed,
  disposed,
}

final class VoiceMediaState {
  const VoiceMediaState({
    required this.phase,
    this.detail,
    this.error,
    this.updatedAt,
  });

  const VoiceMediaState.idle()
    : phase = VoiceMediaPhase.idle,
      detail = null,
      error = null,
      updatedAt = null;

  final VoiceMediaPhase phase;
  final String? detail;
  final Object? error;
  final int? updatedAt;
}

final class VoiceMediaDiagnostics {
  const VoiceMediaDiagnostics({
    this.mediaStates = const <String>[],
    this.iceConnectionStates = const <String>[],
    this.peerConnectionStates = const <String>[],
    this.localCandidateCount = 0,
    this.remoteCandidateCount = 0,
    this.pendingRemoteCandidateCount = 0,
    this.localAudioTrackCount = 0,
    this.remoteAudioTrackCount = 0,
    this.localVideoTrackCount = 0,
    this.remoteVideoTrackCount = 0,
    this.remoteStreamCount = 0,
    this.hasLocalAudio = false,
    this.hasLocalVideo = false,
    this.peerConnectionClosed = false,
    this.disposed = false,
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
  final int localAudioTrackCount;
  final int remoteAudioTrackCount;
  final int localVideoTrackCount;
  final int remoteVideoTrackCount;
  final int remoteStreamCount;
  final bool hasLocalAudio;
  final bool hasLocalVideo;
  final bool peerConnectionClosed;
  final bool disposed;
  final String? lastDetail;
  final String? lastError;
  final String? lastFailureReason;
}

final class VoiceMediaAudioLevel {
  factory VoiceMediaAudioLevel({
    required double remoteLevel,
    required double localLevel,
    required int updatedAt,
    required VoiceMediaAudioLevelSource source,
  }) {
    return VoiceMediaAudioLevel._(
      remoteLevel: _clampLevel(remoteLevel),
      localLevel: _clampLevel(localLevel),
      updatedAt: updatedAt,
      source: source,
    );
  }

  const VoiceMediaAudioLevel._({
    required this.remoteLevel,
    required this.localLevel,
    required this.updatedAt,
    required this.source,
  });

  const VoiceMediaAudioLevel.unavailable({this.updatedAt})
    : remoteLevel = 0,
      localLevel = 0,
      source = VoiceMediaAudioLevelSource.unavailable;

  final double remoteLevel;
  final double localLevel;
  final int? updatedAt;
  final VoiceMediaAudioLevelSource source;

  bool get isAvailable => source != VoiceMediaAudioLevelSource.unavailable;
}

final class VoiceSessionDescription {
  const VoiceSessionDescription({required this.sdp, required this.type});

  final String sdp;
  final String type;

  RTCSessionDescription toRtc() {
    return RTCSessionDescription(sdp, type);
  }

  factory VoiceSessionDescription.fromRtc(RTCSessionDescription description) {
    return VoiceSessionDescription(
      sdp: description.sdp ?? '',
      type: description.type ?? '',
    );
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

final class VoiceIceCandidate {
  const VoiceIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  RTCIceCandidate toRtc() {
    return RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
  }

  factory VoiceIceCandidate.fromRtc(RTCIceCandidate candidate) {
    return VoiceIceCandidate(
      candidate: candidate.candidate ?? '',
      sdpMid: candidate.sdpMid,
      sdpMLineIndex: candidate.sdpMLineIndex,
    );
  }
}

final class VoiceRemoteAudioTrack {
  const VoiceRemoteAudioTrack({
    required this.track,
    required this.streams,
    required this.receivedAt,
  });

  final MediaStreamTrack track;
  final List<MediaStream> streams;
  final DateTime receivedAt;
}
