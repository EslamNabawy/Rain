import '../call_error_classifier.dart';
import '../call_retry_policy.dart';
import '../voice_call_state.dart';

/// Pure delegation to [CallErrorClassifier] for voice call error handling.
///
/// Extracted from VoiceCallRuntime to isolate error classification
/// from runtime state management. All methods are pure functions
/// that delegate to [CallErrorClassifier].
final class VoiceCallErrorCoordinator {
  const VoiceCallErrorCoordinator();

  /// Singleton instance for convenience.
  static const VoiceCallErrorCoordinator instance = VoiceCallErrorCoordinator();

  /// Creates a signaling failure snapshot for [error].
  CallSignalingFailureSnapshot? signalingFailureSnapshotForError(
    Object error, {
    String? peerId,
  }) {
    return CallErrorClassifier.signalingFailureSnapshotForError(
      error,
      peerId: peerId,
    );
  }

  /// Returns `true` if a transient voice create failure should be retried.
  bool shouldRetryTransientCreateFailure(
    Object error,
    CallRetryDecision? decision,
  ) {
    return CallErrorClassifier.shouldRetryTransientCreateFailure(
      error,
      decision,
    );
  }

  /// Resolves the failure reason for a retry decision.
  VoiceCallFailureReason? failureReasonForRetryDecision(
    CallRetryDecision? decision,
  ) {
    return CallErrorClassifier.failureReasonForRetryDecision(decision);
  }

  /// Resolves the failure detail for a retry decision.
  String? failureDetailForRetryDecision(CallRetryDecision? decision) {
    return CallErrorClassifier.failureDetailForRetryDecision(decision);
  }

  /// Builds a failure taxonomy string.
  String failureTaxonomy({
    required String failureCode,
    required String userMessage,
    required String nativeError,
  }) {
    return CallErrorClassifier.failureTaxonomy(
      failureCode: failureCode,
      userMessage: userMessage,
      nativeError: nativeError,
    );
  }

  /// Resolves the failure reason for an error.
  VoiceCallFailureReason? failureReasonForError(Object error) {
    return CallErrorClassifier.failureReasonForError(error);
  }

  /// Resolves the failure detail for an error.
  String? failureDetailForError(
    Object error, {
    String? currentPeerId,
    required String selfUsername,
  }) {
    return CallErrorClassifier.failureDetailForError(
      error,
      currentPeerId: currentPeerId,
      selfUsername: selfUsername,
    );
  }

  /// Normalizes error text for comparison.
  String normalizeErrorText(Object error) {
    return CallErrorClassifier.normalizeErrorText(error);
  }

  /// Resolves a user-facing error message.
  String errorMessage(
    Object error, {
    String? currentPeerId,
    required String selfUsername,
  }) {
    return CallErrorClassifier.errorMessage(
      error,
      currentPeerId: currentPeerId,
      selfUsername: selfUsername,
    );
  }

  /// Extracts the busy user from a normalized error string.
  String? busyUser(String normalized) {
    return CallErrorClassifier.busyUser(normalized);
  }

  /// Resolves a local media failure reason.
  VoiceCallFailureReason? localMediaFailureReason(Object error) {
    return CallErrorClassifier.localMediaFailureReason(error);
  }

  /// Resolves a local media failure detail.
  String? localMediaFailureDetail(Object error) {
    return CallErrorClassifier.localMediaFailureDetail(error);
  }
}
