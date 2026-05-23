import 'package:protocol_brain/protocol_brain.dart' show CallMediaMode;

export 'package:protocol_brain/protocol_brain.dart' show CallMediaMode;

import 'voice_audio_level.dart';

enum VoiceCallPhase {
  idle,
  connectingPeer,
  outgoingRinging,
  incomingRinging,
  connectingMedia,
  active,
  ending,
  failed,
}

enum VoiceCallFailureReason {
  microphoneDenied,
  remoteMicrophoneDenied,
  cameraDenied,
  remoteCameraDenied,
  peerBusy,
  fileTransferActive,
  rejected,
  networkLost,
  signalingFailed,
  expired,
  ringingTimeout,
  mediaConnectionFailed,
  mediaIceTimeout,
  mediaNoRemoteAudio,
  videoFirstFrameTimeout,
}

enum VoiceCallOutputRoute { systemDefault, speaker, bluetooth }

enum CallControlCapability {
  microphone,
  camera,
  switchCamera,
  deafen,
  outputRoute,
  hangUp,
}

class VoiceCallState {
  const VoiceCallState({
    required this.phase,
    this.peerId,
    this.callId,
    this.sessionEpoch,
    this.mediaMode = CallMediaMode.audio,
    this.isOutgoing = false,
    this.isMuted = false,
    this.isCameraMuted = false,
    this.isDeafened = false,
    this.isRemoteMuted = false,
    this.isRemoteCameraMuted = false,
    this.hasLocalVideo = false,
    this.hasRemoteVideo = false,
    this.videoFirstFrameTimedOut = false,
    this.outputRoute = VoiceCallOutputRoute.systemDefault,
    this.outputRouteWarning,
    this.startedAt,
    this.updatedAt,
    this.detail,
    this.error,
    this.failureReason,
    this.audioLevel = const VoiceAudioLevel.unavailable(),
  });

  const VoiceCallState.idle()
    : phase = VoiceCallPhase.idle,
      peerId = null,
      callId = null,
      sessionEpoch = null,
      mediaMode = CallMediaMode.audio,
      isOutgoing = false,
      isMuted = false,
      isCameraMuted = false,
      isDeafened = false,
      isRemoteMuted = false,
      isRemoteCameraMuted = false,
      hasLocalVideo = false,
      hasRemoteVideo = false,
      videoFirstFrameTimedOut = false,
      outputRoute = VoiceCallOutputRoute.systemDefault,
      outputRouteWarning = null,
      startedAt = null,
      updatedAt = null,
      detail = null,
      error = null,
      failureReason = null,
      audioLevel = const VoiceAudioLevel.unavailable();

  final VoiceCallPhase phase;
  final String? peerId;
  final String? callId;
  final int? sessionEpoch;
  final CallMediaMode mediaMode;
  final bool isOutgoing;
  final bool isMuted;
  final bool isCameraMuted;
  final bool isDeafened;
  final bool isRemoteMuted;
  final bool isRemoteCameraMuted;
  final bool hasLocalVideo;
  final bool hasRemoteVideo;
  final bool videoFirstFrameTimedOut;
  final VoiceCallOutputRoute outputRoute;
  final String? outputRouteWarning;
  final int? startedAt;
  final int? updatedAt;
  final String? detail;
  final Object? error;
  final VoiceCallFailureReason? failureReason;
  final VoiceAudioLevel audioLevel;

  bool get hasCall => phase != VoiceCallPhase.idle;

  bool get isRinging =>
      phase == VoiceCallPhase.incomingRinging ||
      phase == VoiceCallPhase.outgoingRinging;

  bool get isBusy =>
      phase == VoiceCallPhase.connectingPeer ||
      phase == VoiceCallPhase.connectingMedia ||
      phase == VoiceCallPhase.ending;

  bool get isActive => phase == VoiceCallPhase.active;

  bool get isVideo => mediaMode == CallMediaMode.video;

  List<CallControlCapability> get controlCapabilities {
    return switch (mediaMode) {
      CallMediaMode.audio => const <CallControlCapability>[
        CallControlCapability.microphone,
        CallControlCapability.deafen,
        CallControlCapability.outputRoute,
        CallControlCapability.hangUp,
      ],
      CallMediaMode.video => const <CallControlCapability>[
        CallControlCapability.microphone,
        CallControlCapability.camera,
        CallControlCapability.switchCamera,
        CallControlCapability.deafen,
        CallControlCapability.outputRoute,
        CallControlCapability.hangUp,
      ],
    };
  }

  bool blocksFileTransfersFor(String peerId) {
    if (peerId.trim().isEmpty) {
      return false;
    }
    return phase != VoiceCallPhase.idle && phase != VoiceCallPhase.failed;
  }

  VoiceCallState copyWith({
    VoiceCallPhase? phase,
    String? peerId,
    String? callId,
    int? sessionEpoch,
    CallMediaMode? mediaMode,
    bool? isOutgoing,
    bool? isMuted,
    bool? isCameraMuted,
    bool? isDeafened,
    bool? isRemoteMuted,
    bool? isRemoteCameraMuted,
    bool? hasLocalVideo,
    bool? hasRemoteVideo,
    bool? videoFirstFrameTimedOut,
    VoiceCallOutputRoute? outputRoute,
    String? outputRouteWarning,
    int? startedAt,
    int? updatedAt,
    String? detail,
    Object? error,
    VoiceCallFailureReason? failureReason,
    VoiceAudioLevel? audioLevel,
    bool clearError = false,
    bool clearFailureReason = false,
    bool clearOutputRouteWarning = false,
  }) {
    return VoiceCallState(
      phase: phase ?? this.phase,
      peerId: peerId ?? this.peerId,
      callId: callId ?? this.callId,
      sessionEpoch: sessionEpoch ?? this.sessionEpoch,
      mediaMode: mediaMode ?? this.mediaMode,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isMuted: isMuted ?? this.isMuted,
      isCameraMuted: isCameraMuted ?? this.isCameraMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isRemoteMuted: isRemoteMuted ?? this.isRemoteMuted,
      isRemoteCameraMuted: isRemoteCameraMuted ?? this.isRemoteCameraMuted,
      hasLocalVideo: hasLocalVideo ?? this.hasLocalVideo,
      hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
      videoFirstFrameTimedOut:
          videoFirstFrameTimedOut ?? this.videoFirstFrameTimedOut,
      outputRoute: outputRoute ?? this.outputRoute,
      outputRouteWarning: clearOutputRouteWarning
          ? null
          : outputRouteWarning ?? this.outputRouteWarning,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      detail: detail ?? this.detail,
      error: clearError ? null : error ?? this.error,
      failureReason: clearFailureReason
          ? null
          : failureReason ?? this.failureReason,
      audioLevel: audioLevel ?? this.audioLevel,
    );
  }
}
