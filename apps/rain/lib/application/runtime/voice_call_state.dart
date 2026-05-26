import 'package:flutter/widgets.dart' show IconData;
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
  videoRendererFailed,
  videoFirstFrameTimeout,
}

enum VoiceCallOutputRoute { systemDefault, speaker, bluetooth }

enum CallAudioOutputTargetKind {
  systemDefault,
  androidSpeakerphone,
  bluetooth,
  wiredHeadset,
  desktopDevice,
}

final class CallAudioOutputTarget {
  const CallAudioOutputTarget._({
    required this.kind,
    required this.route,
    this.deviceId,
  });

  const CallAudioOutputTarget.systemDefault()
    : this._(
        kind: CallAudioOutputTargetKind.systemDefault,
        route: VoiceCallOutputRoute.systemDefault,
      );

  const CallAudioOutputTarget.androidSpeakerphone()
    : this._(
        kind: CallAudioOutputTargetKind.androidSpeakerphone,
        route: VoiceCallOutputRoute.speaker,
      );

  const CallAudioOutputTarget.bluetooth()
    : this._(
        kind: CallAudioOutputTargetKind.bluetooth,
        route: VoiceCallOutputRoute.bluetooth,
      );

  const CallAudioOutputTarget.wiredHeadset()
    : this._(
        kind: CallAudioOutputTargetKind.wiredHeadset,
        route: VoiceCallOutputRoute.systemDefault,
      );

  const CallAudioOutputTarget.desktopDevice(String deviceId)
    : this._(
        kind: CallAudioOutputTargetKind.desktopDevice,
        route: VoiceCallOutputRoute.systemDefault,
        deviceId: deviceId,
      );

  final CallAudioOutputTargetKind kind;
  final VoiceCallOutputRoute route;
  final String? deviceId;

  bool get isDeviceBacked =>
      kind == CallAudioOutputTargetKind.desktopDevice &&
      deviceId != null &&
      deviceId!.trim().isNotEmpty;

  String get key {
    final id = deviceId?.trim();
    if (isDeviceBacked && id != null && id.isNotEmpty) {
      return '${kind.name}:$id';
    }
    return kind.name;
  }

  bool matches(VoiceCallState state) {
    if (isDeviceBacked) {
      return state.outputRouteDeviceId == deviceId;
    }
    return state.outputRouteDeviceId == null && state.outputRoute == route;
  }
}

final class VoiceCallOutputRouteOption {
  const VoiceCallOutputRouteOption({
    required this.target,
    required this.label,
    required this.icon,
  });

  final CallAudioOutputTarget target;
  final String label;
  final IconData icon;

  VoiceCallOutputRoute get route => target.route;
}

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
    this.mediaReconnecting = false,
    this.reconnectingSince,
    this.outputRoute = VoiceCallOutputRoute.systemDefault,
    this.outputRouteDeviceId,
    this.outputRouteLabel,
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
      mediaReconnecting = false,
      reconnectingSince = null,
      outputRoute = VoiceCallOutputRoute.systemDefault,
      outputRouteDeviceId = null,
      outputRouteLabel = null,
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
  final bool mediaReconnecting;
  final int? reconnectingSince;
  final VoiceCallOutputRoute outputRoute;
  final String? outputRouteDeviceId;
  final String? outputRouteLabel;
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
    bool? mediaReconnecting,
    int? reconnectingSince,
    VoiceCallOutputRoute? outputRoute,
    String? outputRouteDeviceId,
    String? outputRouteLabel,
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
    bool clearOutputRouteTarget = false,
    bool clearReconnectingSince = false,
  }) {
    final effectiveMediaReconnecting =
        mediaReconnecting ?? this.mediaReconnecting;
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
      mediaReconnecting: effectiveMediaReconnecting,
      reconnectingSince: !effectiveMediaReconnecting || clearReconnectingSince
          ? null
          : reconnectingSince ?? this.reconnectingSince,
      outputRoute: outputRoute ?? this.outputRoute,
      outputRouteDeviceId: clearOutputRouteTarget
          ? outputRouteDeviceId
          : outputRouteDeviceId ?? this.outputRouteDeviceId,
      outputRouteLabel: clearOutputRouteTarget
          ? outputRouteLabel
          : outputRouteLabel ?? this.outputRouteLabel,
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
