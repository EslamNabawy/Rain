/// # call_error_classifier.dart
///
/// [CallErrorClassifier] provides pure-function error classification for voice
/// and video call failures. Maps raw error objects and normalized text to
/// typed reason codes (busy, rejected, networkLost, signalingFailed, etc.) and
/// user-facing messages, plus [CallSignalingFailureSnapshot] for retry policy.
///
/// **Key types:** [CallErrorClassifier], [CallSignalingFailureSnapshot]
///
/// **Depends on:** protocol_brain, call retry policy, voice call state

import 'package:protocol_brain/protocol_brain.dart';

import 'call_retry_policy.dart';
import 'runtime_interaction_guard.dart';
import 'voice_call_state.dart';

final class CallErrorClassifier {
  const CallErrorClassifier._();

  static const String failedReasonCode = 'failed';
  static const String busyReasonCode = 'busy';
  static const String rejectedReasonCode = 'rejected';
  static const String signalingFailedReasonCode = 'signalingFailed';
  static const String networkLostReasonCode = 'networkLost';
  static const String expiredReasonCode = 'expired';
  static const String ringingTimeoutReasonCode = 'ringingTimeout';
  static const String iceTimeoutReasonCode = 'iceTimeout';
  static const String noRemoteAudioReasonCode = 'noRemoteAudio';
  static const String relayUnavailableReasonCode = 'relayUnavailable';
  static const String videoRendererFailedReasonCode = 'videoRendererFailed';
  static const String videoFirstFrameTimeoutReasonCode =
      'videoFirstFrameTimeout';
  static const String microphoneDeniedReasonCode = 'microphoneDenied';
  static const String cameraDeniedReasonCode = 'cameraDenied';

  static const String microphonePermissionRequired =
      'Microphone permission required.';
  static const String remoteMicrophonePermissionRequired =
      'Peer microphone permission required.';
  static const String cameraPermissionRequired = 'Camera permission required.';
  static const String remoteCameraPermissionRequired =
      'Peer camera permission required.';
  static const String fileTransferRequired =
      'Finish the active file transfer first.';
  static const String rejectedMessage = 'Call declined.';
  static const String networkLostMessage =
      'Network connection lost. Call ended.';
  static const String signalingFailedMessage = 'Call setup failed. Try again.';
  static const String timedOutMessage = 'Call timed out.';
  static const String mediaFailedMessage =
      'Call media could not connect. Try again.';
  static const String relayUnavailableMessage =
      'Relay connection is unavailable. Check TURN configuration.';
  static const String videoFailedMessage =
      'Video could not connect. Try again.';
  static const String videoBackgroundedMessage =
      'Video call ended because the app went to background.';
  static const String audioRouteUnavailableMessage = 'Audio route unavailable.';
  static const String reconnectingMessage =
      'Peer connection interrupted. Reconnecting...';

  static CallSignalingFailureSnapshot? signalingFailureSnapshotForError(
    Object error, {
    String? peerId,
  }) {
    final normalized = normalizeErrorText(error).toLowerCase();
    if (!isSignalingError(error, normalized) &&
        !CallRetryPolicy.isBusyConflictMessage(normalized) &&
        !CallRetryPolicy.isCleanupConflictMessage(normalized)) {
      return null;
    }
    return CallSignalingFailureSnapshot(
      message: normalized,
      lockWasReclaimed:
          normalized.contains('lock was reclaimed') ||
          normalized.contains('old call state was cleaned'),
      terminalRoomWasCleaned:
          normalized.contains('terminal room cleaned') ||
          normalized.contains('terminal room'),
      corruptRoomWasRepaired:
          normalized.contains('corrupt room repaired') ||
          normalized.contains('corrupt terminal'),
      cleanupInProgress:
          normalized.contains('cleanup in progress') ||
          normalized.contains('cleaning up'),
      peerId: peerId ?? busyUser(normalized),
    );
  }

  static bool shouldRetryTransientCreateFailure(
    Object error,
    CallRetryDecision? decision,
  ) {
    if (decision?.kind != CallRetryDecisionKind.signalingFailed) {
      return false;
    }
    final normalized = normalizeErrorText(error).toLowerCase();
    if (CallRetryPolicy.isBusyConflictMessage(normalized) ||
        CallRetryPolicy.isOfflineMessage(normalized)) {
      return false;
    }
    return normalized.contains('[firebase_database/unknown]') ||
        normalized.contains('firebase database error') ||
        normalized.contains('firebase voice call create failed at') ||
        normalized.contains('permission-denied') ||
        normalized.contains('permission denied') ||
        normalized.trim().isEmpty;
  }

  static VoiceCallFailureReason? failureReasonForRetryDecision(
    CallRetryDecision? decision,
  ) {
    return switch (decision?.kind) {
      CallRetryDecisionKind.peerBusy => VoiceCallFailureReason.peerBusy,
      CallRetryDecisionKind.peerOffline ||
      CallRetryDecisionKind.cleanedStaleState ||
      CallRetryDecisionKind.cleanupInProgress ||
      CallRetryDecisionKind.signalingFailed =>
        VoiceCallFailureReason.signalingFailed,
      CallRetryDecisionKind.proceed || null => null,
    };
  }

  static String? failureDetailForRetryDecision(CallRetryDecision? decision) {
    return switch (decision?.kind) {
      CallRetryDecisionKind.peerBusy ||
      CallRetryDecisionKind.peerOffline ||
      CallRetryDecisionKind.cleanedStaleState ||
      CallRetryDecisionKind.cleanupInProgress ||
      CallRetryDecisionKind.signalingFailed => decision?.userMessage,
      CallRetryDecisionKind.proceed || null => null,
    };
  }

  static String failureTaxonomy({
    required String failureCode,
    required String userMessage,
    required String nativeError,
  }) {
    final normalized = '$failureCode $userMessage $nativeError'.toLowerCase();
    if (CallRetryPolicy.isOfflineMessage(normalized) ||
        normalized.contains('offline')) {
      return 'presence_offline';
    }
    if (normalized.contains('could not confirm') ||
        normalized.contains('presence unknown')) {
      return 'presence_unknown';
    }
    if (failureCode == microphoneDeniedReasonCode ||
        failureCode == cameraDeniedReasonCode ||
        normalized.contains('microphone permission') ||
        normalized.contains('camera permission') ||
        normalized.contains('notallowed') ||
        normalized.contains('not allowed') ||
        normalized.contains('permission denied by user') ||
        normalized.contains('permission was denied') ||
        normalized.contains('denied permission')) {
      return 'media_permission_denied';
    }
    if (normalized.contains('relay') || normalized.contains('turn')) {
      return 'turn_unavailable';
    }
    if (normalized.contains('malformed') ||
        normalized.contains('invalid remote') ||
        normalized.contains('corrupt remote') ||
        normalized.contains('bad remote') ||
        normalized.contains('candidate frame')) {
      return 'malformed_remote_data';
    }
    if (normalized.contains('ice timeout') ||
        normalized.contains('ice failed') ||
        normalized.contains('ice failure') ||
        normalized.contains('ice connection') ||
        RegExp(r'\bice\b').hasMatch(normalized)) {
      return 'ice_failed';
    }
    if (normalized.contains('timeout') || normalized.contains('timed out')) {
      return 'media_timeout';
    }
    if (normalized.contains('terminal') && normalized.contains('write')) {
      return 'terminal_write_failed';
    }
    if (normalized.contains('reclaimed') ||
        normalized.contains('stale') ||
        normalized.contains('cleaned')) {
      return 'stale_lock_repaired';
    }
    if (normalized.contains('already terminal') ||
        normalized.contains('already ended') ||
        normalized.contains('room is terminal') ||
        normalized.contains('room is already terminal') ||
        normalized.contains('terminal room state')) {
      return 'room_terminal';
    }
    if (CallRetryPolicy.isBusyConflictMessage(normalized) ||
        normalized.contains('already in a call')) {
      return 'real_busy_lock';
    }
    if (failureCode == busyReasonCode || normalized.contains('busy')) {
      return 'peer_busy_response';
    }
    if (normalized.contains('rules') || normalized.contains('rejected write')) {
      return 'rules_rejected_write';
    }
    if (normalized.contains('permission-denied') ||
        normalized.contains('permission denied')) {
      return 'firebase_permission_denied';
    }
    return 'unknown';
  }

  static VoiceCallFailureReason? failureReasonForError(Object error) {
    final normalized = normalizeErrorText(error).toLowerCase();
    if (isBusyError(normalized)) {
      return VoiceCallFailureReason.peerBusy;
    }
    if (isRejectedError(normalized)) {
      return VoiceCallFailureReason.rejected;
    }
    if (isNetworkLostError(normalized)) {
      return VoiceCallFailureReason.networkLost;
    }
    if (isExpiredError(normalized)) {
      return VoiceCallFailureReason.expired;
    }
    if (error is TurnUnavailableException ||
        normalized.contains('relay connection is unavailable') ||
        normalized.contains('turn configuration')) {
      return VoiceCallFailureReason.relayUnavailable;
    }
    if (isOfflineError(normalized)) {
      return VoiceCallFailureReason.signalingFailed;
    }
    if (isSignalingError(error, normalized)) {
      return VoiceCallFailureReason.signalingFailed;
    }
    if (isVideoRendererError(normalized)) {
      return VoiceCallFailureReason.videoRendererFailed;
    }
    if (isNativeMediaError(normalized) ||
        normalized.contains('ice timeout') ||
        normalized.contains('no remote audio')) {
      return VoiceCallFailureReason.mediaConnectionFailed;
    }
    return null;
  }

  static String? failureDetailForError(
    Object error, {
    required String? currentPeerId,
    required String selfUsername,
  }) {
    final normalized = normalizeErrorText(error).toLowerCase();
    if (isBusyError(normalized)) {
      final busy = busyUser(normalized);
      if (busy != null && busy != _normalizeUsername(selfUsername)) {
        return '@$busy is already in a call.';
      }
      return 'Peer is already in a call.';
    }
    if (isRejectedError(normalized)) {
      return rejectedMessage;
    }
    if (isNetworkLostError(normalized)) {
      return networkLostMessage;
    }
    if (isExpiredError(normalized)) {
      return timedOutMessage;
    }
    if (error is TurnUnavailableException ||
        normalized.contains('relay connection is unavailable') ||
        normalized.contains('turn configuration')) {
      return relayUnavailableMessage;
    }
    if (isOfflineError(normalized)) {
      final peerId = currentPeerId ?? '';
      final unknownPeer = RuntimeInteractionGuard.presenceUnknownMessage(
        peerId,
      );
      return normalized.contains('could not confirm') ||
              normalized.contains('presence unknown')
          ? unknownPeer
          : RuntimeInteractionGuard.peerOfflineMessage(peerId);
    }
    if (isSignalingError(error, normalized)) {
      return signalingFailedMessage;
    }
    if (isVideoRendererError(normalized)) {
      return videoFailedMessage;
    }
    if (isNativeMediaError(normalized) ||
        normalized.contains('ice timeout') ||
        normalized.contains('no remote audio')) {
      return mediaFailedMessage;
    }
    return null;
  }

  static String normalizeErrorText(Object error) {
    final raw = error.toString().trim();
    const prefixes = <String>[
      'Exception: ',
      'Bad state: ',
      'StateError: ',
      'VoiceSignalingException: ',
    ];
    var message = raw;
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        message = raw.substring(prefix.length).trim();
        break;
      }
    }
    return message;
  }

  static String errorMessage(
    Object error, {
    required String? currentPeerId,
    required String selfUsername,
  }) {
    final message = normalizeErrorText(error);
    final typedDetail = failureDetailForError(
      error,
      currentPeerId: currentPeerId,
      selfUsername: selfUsername,
    );
    if (typedDetail != null) {
      return typedDetail;
    }
    return message;
  }

  static bool isBusyError(String normalized) {
    return normalized.contains('peer is busy') ||
        normalized == 'busy.' ||
        normalized.contains('active voice call already exists') ||
        normalized.contains('activevoicepairs') ||
        normalized.contains('active voice pair') ||
        normalized.contains('activevoiceusers') ||
        normalized.contains('active voice user');
  }

  static bool isOfflineError(String normalized) {
    return CallRetryPolicy.isOfflineMessage(normalized);
  }

  static String? busyUser(String normalized) {
    const marker = 'active voice call already exists for user ';
    final markerIndex = normalized.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }
    final tail = normalized.substring(markerIndex + marker.length).trim();
    if (tail.isEmpty) {
      return null;
    }
    return _normalizeUsername(tail.split(RegExp(r'[\s.]')).first);
  }

  static bool isRejectedError(String normalized) {
    return normalized == 'rejected.' ||
        normalized.contains('call declined') ||
        normalized.contains('call rejected');
  }

  static bool isNetworkLostError(String normalized) {
    return normalized.contains('network connection lost') ||
        normalized.contains('network lost') ||
        normalized.contains('internet connection') ||
        normalized.contains('network is unavailable') ||
        normalized.contains('network unavailable');
  }

  static bool isExpiredError(String normalized) {
    return normalized.contains('call timed out') ||
        normalized.contains('voice call expired') ||
        normalized.contains('call room expired') ||
        normalized == 'expired.';
  }

  static bool isSignalingError(Object error, String normalized) {
    return error is VoiceSignalingException ||
        normalized.contains('voice signaling') ||
        normalized.contains('firebase') ||
        normalized.contains('unknown voice call') ||
        normalized.contains('voice call already exists') ||
        normalized.contains('already ended') ||
        normalized.contains('permission-denied') ||
        normalized.contains('database');
  }

  static bool isNativeMediaError(String normalized) {
    return normalized.contains('rtcrtptransceiver') ||
        normalized.contains('setdirection') ||
        normalized.contains('setremotedescription') ||
        normalized.contains('peerconnectionsetremotedescription') ||
        normalized.contains('m-line') ||
        normalized.contains('peer connection changed while');
  }

  static bool isVideoRendererError(String normalized) {
    return normalized.contains('video renderer') ||
        normalized.contains('rtc video renderer') ||
        normalized.contains('rtcvideorenderer');
  }

  static VoiceCallFailureReason? localMediaFailureReason(Object error) {
    if (isVideoRendererError(error.toString().toLowerCase())) {
      return VoiceCallFailureReason.videoRendererFailed;
    }
    if (error is CallMediaException) {
      return switch (error.reason) {
        CallMediaFailureReason.cameraDenied ||
        CallMediaFailureReason.cameraUnavailable =>
          VoiceCallFailureReason.cameraDenied,
        CallMediaFailureReason.microphoneDenied =>
          VoiceCallFailureReason.microphoneDenied,
        CallMediaFailureReason.mediaCaptureFailed ||
        CallMediaFailureReason.negotiationFailed => null,
      };
    }
    final normalized = error.toString().toLowerCase();
    if (normalized.contains('camera') &&
        (normalized.contains('permission') ||
            normalized.contains('denied') ||
            normalized.contains('unavailable'))) {
      return VoiceCallFailureReason.cameraDenied;
    }
    final permissionDenied =
        normalized.contains('notallowed') ||
        normalized.contains('not allowed') ||
        normalized.contains('permission denied') ||
        normalized.contains('permission was denied') ||
        normalized.contains('denied permission') ||
        normalized.contains('microphone permission');
    return permissionDenied ? VoiceCallFailureReason.microphoneDenied : null;
  }

  static String? localMediaFailureDetail(Object error) {
    return switch (localMediaFailureReason(error)) {
      VoiceCallFailureReason.microphoneDenied => microphonePermissionRequired,
      VoiceCallFailureReason.cameraDenied => cameraPermissionRequired,
      VoiceCallFailureReason.videoRendererFailed => videoFailedMessage,
      _ => null,
    };
  }

  static String _normalizeUsername(String username) {
    return username.trim().toLowerCase();
  }
}
