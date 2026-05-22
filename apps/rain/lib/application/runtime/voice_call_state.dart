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

class VoiceCallState {
  const VoiceCallState({
    required this.phase,
    this.peerId,
    this.callId,
    this.isOutgoing = false,
    this.isMuted = false,
    this.isRemoteMuted = false,
    this.startedAt,
    this.updatedAt,
    this.detail,
    this.error,
  });

  const VoiceCallState.idle()
    : phase = VoiceCallPhase.idle,
      peerId = null,
      callId = null,
      isOutgoing = false,
      isMuted = false,
      isRemoteMuted = false,
      startedAt = null,
      updatedAt = null,
      detail = null,
      error = null;

  final VoiceCallPhase phase;
  final String? peerId;
  final String? callId;
  final bool isOutgoing;
  final bool isMuted;
  final bool isRemoteMuted;
  final int? startedAt;
  final int? updatedAt;
  final String? detail;
  final Object? error;

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
    bool? isRemoteMuted,
    int? startedAt,
    int? updatedAt,
    String? detail,
    Object? error,
    bool clearError = false,
  }) {
    return VoiceCallState(
      phase: phase ?? this.phase,
      peerId: peerId ?? this.peerId,
      callId: callId ?? this.callId,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      isMuted: isMuted ?? this.isMuted,
      isRemoteMuted: isRemoteMuted ?? this.isRemoteMuted,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      detail: detail ?? this.detail,
      error: clearError ? null : error ?? this.error,
    );
  }
}
