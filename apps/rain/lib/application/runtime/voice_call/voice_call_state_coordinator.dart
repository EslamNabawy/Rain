/// # voice_call_state_coordinator.dart
///
/// [VoiceCallStateCoordinator] owns the pure state-transition and mapping
/// policy for voice calls. Stateless — the runtime owns mutable state while
/// this coordinator owns decisions like phase mapping, expired start-block
/// clearing, and failure-reason resolution.
///
/// **Key types:** [VoiceCallStateCoordinator]
///
/// **Depends on:** protocol_brain, call error classifier, voice audio level, voice call state

import 'package:protocol_brain/protocol_brain.dart';

import '../call_error_classifier.dart';
import '../voice_audio_level.dart';
import '../voice_call_state.dart';

/// Stateless voice-call state transition and mapping policy.
///
/// Runtime owns mutable state; this coordinator owns the pure decisions so
/// call-state behavior can be tested without constructing RainRuntimeController.
final class VoiceCallStateCoordinator {
  const VoiceCallStateCoordinator();

  static const VoiceCallStateCoordinator instance = VoiceCallStateCoordinator();

  VoiceCallState startPreflightState(
    VoiceCallState state, {
    required Duration expiry,
    required int nowMs,
  }) {
    if (!canClearExpiredStartBlock(state.phase)) {
      return state;
    }
    return isLocallyExpiredStartBlock(state, expiry: expiry, nowMs: nowMs)
        ? const VoiceCallState.idle()
        : state;
  }

  bool isLocallyExpiredStartBlock(
    VoiceCallState state, {
    required Duration expiry,
    required int nowMs,
  }) {
    final sessionEpoch = state.sessionEpoch;
    return sessionEpoch != null &&
        nowMs >= sessionEpoch + expiry.inMilliseconds;
  }

  bool canClearExpiredStartBlock(VoiceCallPhase phase) {
    return phase == VoiceCallPhase.connectingMedia ||
        phase == VoiceCallPhase.outgoingRinging ||
        phase == VoiceCallPhase.incomingRinging ||
        phase == VoiceCallPhase.active;
  }

  VoiceCallPhase mapSessionPhase(VoiceCallSessionPhase phase) {
    return switch (phase) {
      VoiceCallSessionPhase.idle => VoiceCallPhase.idle,
      VoiceCallSessionPhase.preflightingMic ||
      VoiceCallSessionPhase.creatingMedia ||
      VoiceCallSessionPhase.connectingMedia => VoiceCallPhase.connectingMedia,
      VoiceCallSessionPhase.outgoingRinging => VoiceCallPhase.outgoingRinging,
      VoiceCallSessionPhase.incomingRinging => VoiceCallPhase.incomingRinging,
      VoiceCallSessionPhase.active => VoiceCallPhase.active,
      VoiceCallSessionPhase.ending => VoiceCallPhase.ending,
      VoiceCallSessionPhase.failed => VoiceCallPhase.failed,
    };
  }

  VoiceCallFailureReason? failureReasonForSessionState(
    VoiceCallSessionState state, {
    required VoiceCallFailureReason? Function(Object) localMediaFailureReason,
  }) {
    final error = state.error;
    if (error != null) {
      final localFailure = localMediaFailureReason(error);
      if (localFailure != null) {
        return localFailure;
      }
    }
    if (state.reasonCode == CallErrorClassifier.microphoneDeniedReasonCode) {
      return VoiceCallFailureReason.remoteMicrophoneDenied;
    }
    if (state.reasonCode == CallErrorClassifier.cameraDeniedReasonCode) {
      return VoiceCallFailureReason.remoteCameraDenied;
    }
    if (state.reasonCode == CallErrorClassifier.busyReasonCode ||
        state.detail == 'Peer is busy.') {
      return VoiceCallFailureReason.peerBusy;
    }
    if (state.reasonCode == CallErrorClassifier.rejectedReasonCode ||
        state.detail == CallErrorClassifier.rejectedMessage ||
        state.detail == 'Rejected.') {
      return VoiceCallFailureReason.rejected;
    }
    if (state.reasonCode == CallErrorClassifier.networkLostReasonCode ||
        state.detail == CallErrorClassifier.networkLostMessage) {
      return VoiceCallFailureReason.networkLost;
    }
    if (state.reasonCode == CallErrorClassifier.signalingFailedReasonCode ||
        state.detail == CallErrorClassifier.signalingFailedMessage) {
      return VoiceCallFailureReason.signalingFailed;
    }
    if (state.reasonCode == CallErrorClassifier.expiredReasonCode ||
        state.detail == CallErrorClassifier.timedOutMessage) {
      return VoiceCallFailureReason.expired;
    }
    if (state.reasonCode == CallErrorClassifier.ringingTimeoutReasonCode ||
        state.detail == CallErrorClassifier.timedOutMessage ||
        state.detail == 'Call timed out.' ||
        state.detail == 'Call timed out while ringing.') {
      return VoiceCallFailureReason.ringingTimeout;
    }
    if (state.reasonCode == CallErrorClassifier.iceTimeoutReasonCode ||
        state.detail == CallErrorClassifier.mediaFailedMessage) {
      return VoiceCallFailureReason.mediaIceTimeout;
    }
    if (state.reasonCode == CallErrorClassifier.noRemoteAudioReasonCode ||
        state.detail == CallErrorClassifier.mediaFailedMessage) {
      return VoiceCallFailureReason.mediaNoRemoteAudio;
    }
    if (state.reasonCode == CallErrorClassifier.relayUnavailableReasonCode ||
        state.detail == CallErrorClassifier.relayUnavailableMessage) {
      return VoiceCallFailureReason.relayUnavailable;
    }
    if (state.reasonCode == CallErrorClassifier.videoRendererFailedReasonCode) {
      return VoiceCallFailureReason.videoRendererFailed;
    }
    if (state.reasonCode ==
            CallErrorClassifier.videoFirstFrameTimeoutReasonCode ||
        state.detail == CallErrorClassifier.videoFailedMessage) {
      return VoiceCallFailureReason.videoFirstFrameTimeout;
    }
    if (state.reasonCode == CallErrorClassifier.failedReasonCode) {
      return VoiceCallFailureReason.mediaConnectionFailed;
    }
    if (error != null) {
      return localMediaFailureReason(error);
    }
    return null;
  }

  String? detailForSessionState(
    VoiceCallSessionState state, {
    required String? Function(Object) localMediaFailureDetail,
    required String Function(Object) errorMessage,
  }) {
    if (state.phase != VoiceCallSessionPhase.failed) {
      return state.detail;
    }
    final error = state.error;
    if (error != null) {
      final localDetail = localMediaFailureDetail(error);
      if (localDetail != null) {
        return localDetail;
      }
    }
    if (state.reasonCode == CallErrorClassifier.microphoneDeniedReasonCode) {
      return CallErrorClassifier.remoteMicrophonePermissionRequired;
    }
    if (state.reasonCode == CallErrorClassifier.cameraDeniedReasonCode) {
      return CallErrorClassifier.remoteCameraPermissionRequired;
    }
    if (state.reasonCode == CallErrorClassifier.busyReasonCode ||
        state.detail == 'Peer is busy.') {
      return 'Peer is already in a call.';
    }
    if (state.reasonCode == CallErrorClassifier.rejectedReasonCode ||
        state.detail == 'Rejected.') {
      return CallErrorClassifier.rejectedMessage;
    }
    if (state.reasonCode == CallErrorClassifier.networkLostReasonCode ||
        state.detail == CallErrorClassifier.networkLostMessage) {
      return CallErrorClassifier.networkLostMessage;
    }
    if (state.reasonCode == CallErrorClassifier.signalingFailedReasonCode ||
        state.detail == CallErrorClassifier.signalingFailedMessage) {
      return CallErrorClassifier.signalingFailedMessage;
    }
    if (state.reasonCode == CallErrorClassifier.expiredReasonCode ||
        state.detail == CallErrorClassifier.timedOutMessage) {
      return CallErrorClassifier.timedOutMessage;
    }
    if (state.reasonCode == CallErrorClassifier.ringingTimeoutReasonCode ||
        state.detail == 'Call timed out.' ||
        state.detail == 'Call timed out while ringing.') {
      return CallErrorClassifier.timedOutMessage;
    }
    if (state.reasonCode == CallErrorClassifier.iceTimeoutReasonCode) {
      return CallErrorClassifier.mediaFailedMessage;
    }
    if (state.reasonCode == CallErrorClassifier.noRemoteAudioReasonCode) {
      return CallErrorClassifier.mediaFailedMessage;
    }
    if (state.reasonCode == CallErrorClassifier.relayUnavailableReasonCode) {
      return CallErrorClassifier.relayUnavailableMessage;
    }
    if (state.reasonCode == CallErrorClassifier.videoRendererFailedReasonCode) {
      return CallErrorClassifier.videoFailedMessage;
    }
    if (state.reasonCode ==
        CallErrorClassifier.videoFirstFrameTimeoutReasonCode) {
      return CallErrorClassifier.videoFailedMessage;
    }
    if (state.reasonCode == CallErrorClassifier.failedReasonCode) {
      return CallErrorClassifier.mediaFailedMessage;
    }
    if (error == null) {
      return state.detail;
    }
    return localMediaFailureDetail(error) ?? errorMessage(error);
  }

  String preflightDetail(CallMediaMode mediaMode) {
    return switch (mediaMode) {
      CallMediaMode.audio => 'Checking microphone permission.',
      CallMediaMode.video => 'Checking camera and microphone permission.',
    };
  }

  bool isRemoteMediaPermissionCode(String? reasonCode) {
    return reasonCode == CallErrorClassifier.microphoneDeniedReasonCode ||
        reasonCode == CallErrorClassifier.cameraDeniedReasonCode;
  }

  VoiceCallFailureReason remoteMediaPermissionFailure(String? reasonCode) {
    return reasonCode == CallErrorClassifier.cameraDeniedReasonCode
        ? VoiceCallFailureReason.remoteCameraDenied
        : VoiceCallFailureReason.remoteMicrophoneDenied;
  }

  String remoteMediaPermissionDetail(String? reasonCode) {
    return reasonCode == CallErrorClassifier.cameraDeniedReasonCode
        ? CallErrorClassifier.remoteCameraPermissionRequired
        : CallErrorClassifier.remoteMicrophonePermissionRequired;
  }

  VoiceCallState stateAfterTerminalWriteFailure(
    VoiceCallState current, {
    Object? error,
    required int nowMs,
  }) {
    return current.copyWith(
      phase: VoiceCallPhase.failed,
      detail: 'Could not notify peer that the call ended. Try again.',
      error: error,
      failureReason: VoiceCallFailureReason.signalingFailed,
      isCameraMuted: false,
      isDeafened: false,
      isRemoteCameraMuted: false,
      hasLocalVideo: false,
      hasRemoteVideo: false,
      videoFirstFrameTimedOut: false,
      mediaReconnecting: false,
      outputRoute: VoiceCallOutputRoute.systemDefault,
      updatedAt: nowMs,
      clearOutputRouteWarning: true,
      clearOutputRouteTarget: true,
      clearReconnectingSince: true,
      audioLevel: const VoiceAudioLevel.unavailable(),
    );
  }

  bool isSameLiveSessionState(
    VoiceCallState latest, {
    required bool runtimeShutDown,
    required bool ownsRuntimeSession,
    String? callId,
    int? sessionEpoch,
  }) {
    if (runtimeShutDown || !ownsRuntimeSession) {
      return false;
    }
    return latest.callId == callId &&
        latest.sessionEpoch == sessionEpoch &&
        latest.phase != VoiceCallPhase.idle &&
        latest.phase != VoiceCallPhase.failed;
  }

  bool isSameLiveState(VoiceCallState latest, VoiceCallState expected) {
    return latest.callId == expected.callId &&
        latest.sessionEpoch == expected.sessionEpoch &&
        latest.phase != VoiceCallPhase.idle &&
        latest.phase != VoiceCallPhase.failed;
  }

  VoiceCallState stateAfterLocalEnd(
    VoiceCallState current, {
    required String detail,
    VoiceCallFailureReason? failureReason,
    String? failureDetail,
    required int nowMs,
  }) {
    if (failureReason == null) {
      return const VoiceCallState.idle();
    }
    return current.copyWith(
      phase: VoiceCallPhase.failed,
      detail: failureDetail ?? detail,
      failureReason: failureReason,
      isCameraMuted: false,
      isDeafened: false,
      isRemoteCameraMuted: false,
      hasLocalVideo: false,
      hasRemoteVideo: false,
      videoFirstFrameTimedOut: false,
      mediaReconnecting: false,
      outputRoute: VoiceCallOutputRoute.systemDefault,
      updatedAt: nowMs,
      clearError: true,
      clearOutputRouteWarning: true,
      clearOutputRouteTarget: true,
      clearReconnectingSince: true,
      audioLevel: const VoiceAudioLevel.unavailable(),
    );
  }
}
