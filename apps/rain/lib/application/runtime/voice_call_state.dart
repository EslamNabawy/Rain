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
}

enum VoiceCallOutputRoute { systemDefault, speaker, bluetooth }

class VoiceCallState {
  const VoiceCallState({
    required this.phase,
    this.peerId,
    this.callId,
    this.isOutgoing = false,
    this.isMuted = false,
    this.isDeafened = false,
    this.isRemoteMuted = false,
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
      isOutgoing = false,
      isMuted = false,
      isDeafened = false,
      isRemoteMuted = false,
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
  final bool isOutgoing;
  final bool isMuted;
  final bool isDeafened;
  final bool isRemoteMuted;
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
    bool? isOutgoing,
    bool? isMuted,
    bool? isDeafened,
    bool? isRemoteMuted,
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
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isRemoteMuted: isRemoteMuted ?? this.isRemoteMuted,
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
