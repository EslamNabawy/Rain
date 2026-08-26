/// # voice_call_room_coordinator.dart
///
/// [VoiceCallRoomCoordinator] tracks Firebase voice call room status
/// transitions and resolves terminal room detail/reason messages. Stateless —
/// receives maps via parameters so the runtime retains ownership of mutable
/// state.
///
/// **Key types:** [VoiceCallRoomCoordinator]
///
/// **Depends on:** call error classifier, voice call state
library;

import 'package:protocol_brain/protocol_brain.dart';

import '../call_error_classifier.dart';
import '../voice_call_state.dart';

/// Tracks Firebase voice call room status transitions and provides
/// terminal room detail/reason resolution without owning runtime state.
///
/// Extracted from VoiceCallRuntime (Phase 2a) to isolate room lifecycle
/// ownership from command orchestration and media session management.
///
/// This coordinator is intentionally stateless — it receives the maps it
/// operates on via parameters, so the runtime retains ownership of mutable
/// state while the decision logic is centralized and testable.
final class VoiceCallRoomCoordinator {
  const VoiceCallRoomCoordinator();

  /// Singleton instance for convenience.
  static const VoiceCallRoomCoordinator instance = VoiceCallRoomCoordinator();

  // ---------------------------------------------------------------------------

  /// Records a room [status] transition for [callId] in [statusByCallId] and
  /// returns the previous status (or `null` if first transition).
  VoiceCallSignalingStatus? recordRoomStatusTransition(
    Map<String, VoiceCallSignalingStatus> statusByCallId,
    String callId,
    VoiceCallSignalingStatus status,
  ) {
    final previous = statusByCallId[callId];
    statusByCallId[callId] = status;
    return previous;
  }

  // ---------------------------------------------------------------------------
  // Terminal room detail resolution
  // ---------------------------------------------------------------------------

  /// Resolves the user-facing detail message for a terminal [room] from the
  /// perspective of [localUser].
  String terminalRoomDetail(
    VoiceCallRoom room,
    String localUser, {
    required String? Function(VoiceCallSessionState) detailForSessionState,
  }) {
    if (room.status == VoiceCallSignalingStatus.ended &&
        room.endedBy != null &&
        room.endedBy != localUser) {
      return 'Peer ended the call.';
    }
    if (room.status == VoiceCallSignalingStatus.ended) {
      return room.reason ?? 'Call ended.';
    }
    final roomReason = room.reason?.trim();
    if (roomReason != null &&
        roomReason.isNotEmpty &&
        !_isRemoteMediaPermissionCode(room.reasonCode)) {
      return roomReason;
    }
    final syntheticState = _terminalSessionStateForRoom(room);
    return detailForSessionState(syntheticState) ??
        _terminalReasonForStatus(room.status) ??
        CallErrorClassifier.mediaFailedMessage;
  }

  /// Resolves the [VoiceCallFailureReason] for a terminal [room], or `null`
  /// if the room ended cleanly.
  VoiceCallFailureReason? terminalRoomFailureReason(
    VoiceCallRoom room, {
    required VoiceCallFailureReason? Function(VoiceCallSessionState)
    failureReasonForSessionState,
  }) {
    if (room.status == VoiceCallSignalingStatus.ended) {
      return null;
    }
    return failureReasonForSessionState(_terminalSessionStateForRoom(room)) ??
        VoiceCallFailureReason.mediaConnectionFailed;
  }

  /// Resolves the reason code string for a given [failureReason].
  String? reasonCodeForFailure(VoiceCallFailureReason? reason) {
    return switch (reason) {
      null => null,
      VoiceCallFailureReason.microphoneDenied ||
      VoiceCallFailureReason.remoteMicrophoneDenied =>
        CallErrorClassifier.microphoneDeniedReasonCode,
      VoiceCallFailureReason.cameraDenied ||
      VoiceCallFailureReason.remoteCameraDenied =>
        CallErrorClassifier.cameraDeniedReasonCode,
      VoiceCallFailureReason.peerBusy ||
      VoiceCallFailureReason.fileTransferActive =>
        CallErrorClassifier.busyReasonCode,
      VoiceCallFailureReason.rejected => CallErrorClassifier.rejectedReasonCode,
      VoiceCallFailureReason.networkLost =>
        CallErrorClassifier.networkLostReasonCode,
      VoiceCallFailureReason.signalingFailed =>
        CallErrorClassifier.signalingFailedReasonCode,
      VoiceCallFailureReason.expired => CallErrorClassifier.expiredReasonCode,
      VoiceCallFailureReason.ringingTimeout =>
        CallErrorClassifier.ringingTimeoutReasonCode,
      VoiceCallFailureReason.mediaIceTimeout =>
        CallErrorClassifier.iceTimeoutReasonCode,
      VoiceCallFailureReason.mediaNoRemoteAudio =>
        CallErrorClassifier.noRemoteAudioReasonCode,
      VoiceCallFailureReason.relayUnavailable =>
        CallErrorClassifier.relayUnavailableReasonCode,
      VoiceCallFailureReason.videoRendererFailed =>
        CallErrorClassifier.videoRendererFailedReasonCode,
      VoiceCallFailureReason.videoFirstFrameTimeout =>
        CallErrorClassifier.videoFirstFrameTimeoutReasonCode,
      VoiceCallFailureReason.mediaConnectionFailed =>
        CallErrorClassifier.failedReasonCode,
    };
  }

  // ---------------------------------------------------------------------------
  // Late-frame / terminal-already-closed classification
  // ---------------------------------------------------------------------------

  /// Returns `true` if [error] indicates a terminal-already-closed write.
  bool isTerminalRoomWriteError(Object error) {
    final message = error.toString();
    return message.contains('PERMISSION_DENIED') ||
        message.contains('permission denied') ||
        message.contains('already deleted') ||
        message.contains('already closed') ||
        message.contains('room is terminal');
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static VoiceCallSessionState _terminalSessionStateForRoom(
    VoiceCallRoom room,
  ) {
    return VoiceCallSessionState(
      phase: VoiceCallSessionPhase.failed,
      updatedAt: room.endedAt ?? room.updatedAt,
      mediaMode: room.mediaMode,
      detail: room.reason ?? _terminalReasonForStatus(room.status),
      reasonCode:
          room.reasonCode ??
          switch (room.status) {
            VoiceCallSignalingStatus.expired =>
              CallErrorClassifier.expiredReasonCode,
            VoiceCallSignalingStatus.failed =>
              CallErrorClassifier.failedReasonCode,
            _ => null,
          },
    );
  }

  static String? _terminalReasonForStatus(VoiceCallSignalingStatus status) {
    return switch (status) {
      VoiceCallSignalingStatus.expired => CallErrorClassifier.timedOutMessage,
      _ => null,
    };
  }

  static bool _isRemoteMediaPermissionCode(String? reasonCode) {
    return reasonCode == CallErrorClassifier.microphonePermissionRequired ||
        reasonCode == CallErrorClassifier.cameraPermissionRequired ||
        reasonCode == CallErrorClassifier.remoteMicrophonePermissionRequired ||
        reasonCode == CallErrorClassifier.remoteCameraPermissionRequired;
  }
}
