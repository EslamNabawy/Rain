/// # protocol_error_classifier.dart — protocol_brain package
///
/// Stateless utility that classifies protocol-level errors into user-facing messages. Strips Dart exception prefixes and produces specialized messages for signaling encryption failures and connection setup errors.
///
/// **Key types:** ProtocolErrorClassifier
///
/// **Package:** protocol_brain
///
/// **Depends on:** peer_core, signaling_cipher (SignalingEncryptionException), session_manager (Session, SessionState, SessionPhase, PeerConnectionRoute)
import 'package:peer_core/peer_core.dart';

import '../adapters/signaling_cipher.dart';
import 'session_manager.dart';

/// Classifies protocol-level errors and produces user-facing messages.
///
/// This class is stateless and can be unit tested in isolation.
/// It handles:
/// - Connection setup failure classification
/// - Signaling failure message formatting
class ProtocolErrorClassifier {
  const ProtocolErrorClassifier();

  /// Classifies a connection-setup failure and returns a user-facing message.
  ///
  /// Strips common Dart exception prefixes so the message is readable.
  String classifyConnectSetupFailure(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    if (message.startsWith('Bad state: ')) {
      return message.substring('Bad state: '.length);
    }
    if (message.startsWith('StateError: ')) {
      return message.substring('StateError: '.length);
    }
    return message;
  }

  /// Returns a user-facing message for a signaling stream failure.
  ///
  /// Handles [SignalingEncryptionException] with a specific message about
  /// build/key mismatch, and falls back to a generic message for other errors.
  String signalingFailureMessage(Object error) {
    if (error is SignalingEncryptionException) {
      return 'Encrypted signaling data could not be read. Make sure both devices use the same latest build and signaling encryption key, then clear stale Firebase rooms before retrying.';
    }
    return 'Peer signaling data could not be read: $error';
  }

  /// Builds a [Session] snapshot representing a signaling stream failure.
  Session sessionForSignalingStreamError({
    required Session currentSnapshot,
    required String source,
    required String errorMessage,
  }) {
    return currentSnapshot.copyWith(
      state: SessionState.failed,
      phase: SessionPhase.failed,
      detail: 'Signaling failed while reading $source data.',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      error: errorMessage,
      route: PeerConnectionRoute.unknown(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Builds a [Session] snapshot representing a local ICE write failure.
  Session sessionForLocalIceWriteError({
    required Session currentSnapshot,
    required Object error,
  }) {
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    return currentSnapshot.copyWith(
      state: SessionState.failed,
      phase: SessionPhase.failed,
      detail: 'Signaling failed while sending ICE candidate.',
      updatedAt: updatedAt,
      error: 'Peer signaling data could not be written: $error',
      route: PeerConnectionRoute.unknown(updatedAt: updatedAt),
    );
  }

  /// Builds a [Session] snapshot representing a handshake timeout.
  Session sessionForHandshakeTimeout({required Session currentSnapshot}) {
    return currentSnapshot.copyWith(
      state: SessionState.failed,
      phase: SessionPhase.failed,
      detail: 'Handshake timed out.',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      error: 'Handshake timed out.',
      route: PeerConnectionRoute.unknown(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Builds a [Session] snapshot representing failure after exhausting retries.
  Session sessionForRetriesExhausted({required Session currentSnapshot}) {
    return currentSnapshot.copyWith(
      state: SessionState.failed,
      phase: SessionPhase.failed,
      detail: 'Connection failed after retries.',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      error: 'Connection failed after retries.',
      route: PeerConnectionRoute.unknown(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Builds a [Session] snapshot for relay fallback unavailability.
  Session sessionForRelayUnavailable({
    required Session currentSnapshot,
    required String directFailure,
  }) {
    return currentSnapshot.copyWith(
      state: SessionState.failed,
      phase: SessionPhase.failed,
      detail: 'Direct path blocked. Relay fallback unavailable.',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      error: 'Direct path blocked. No TURN relay is configured for this build.',
      route: PeerConnectionRoute.unknown(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Builds a [Session] snapshot for relay fallback failure.
  Session sessionForRelayFallbackFailed({
    required Session currentSnapshot,
    required String errorMessage,
  }) {
    return currentSnapshot.copyWith(
      state: SessionState.failed,
      phase: SessionPhase.failed,
      detail: 'Direct path blocked. Relay fallback failed.',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      error: 'Direct path blocked. Relay fallback failed: $errorMessage',
      route: PeerConnectionRoute.unknown(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Builds a [Session] snapshot for network recovery failure.
  Session sessionForNetworkRecoveryFailed({
    required Session currentSnapshot,
    required String errorMessage,
  }) {
    return currentSnapshot.copyWith(
      state: SessionState.failed,
      phase: SessionPhase.failed,
      detail: 'Network recovery failed.',
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      error: 'Network recovery failed: $errorMessage',
      route: PeerConnectionRoute.unknown(
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
}
