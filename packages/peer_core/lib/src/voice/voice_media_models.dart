import 'package:flutter_webrtc/flutter_webrtc.dart';

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
