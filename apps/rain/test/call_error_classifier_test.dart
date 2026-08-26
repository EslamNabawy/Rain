/// # call_error_classifier_test
///
/// Tests call error classification, normalization, and failure taxonomy mapping for voice/video call failures.
///
/// **Key types:** CallErrorClassifier, VoiceCallFailureReason, CallRetryDecision.
///
/// **Depends on:** protocol_brain signaling errors and native WebRTC media exceptions.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/call_error_classifier.dart';
import 'package:rain/application/runtime/call_retry_policy.dart';
import 'package:rain/application/runtime/voice_call_state.dart';

void main() {
  group('CallErrorClassifier', () {
    test('normalizes common exception prefixes', () {
      expect(
        CallErrorClassifier.normalizeErrorText(
          StateError('VoiceSignalingException: Firebase denied'),
        ),
        'VoiceSignalingException: Firebase denied',
      );
    });

    test('extracts voice lock busy user from signaling errors', () {
      final snapshot = CallErrorClassifier.signalingFailureSnapshotForError(
        StateError('Active voice call already exists for user Bob.'),
      );

      expect(snapshot, isNotNull);
      expect(snapshot!.peerId, 'bob');
      expect(snapshot.lockWasReclaimed, isFalse);
      expect(snapshot.cleanupInProgress, isFalse);
      expect(
        CallErrorClassifier.failureDetailForError(
          StateError('Active voice call already exists for user Bob.'),
          currentPeerId: 'bob',
          selfUsername: 'alice',
        ),
        '@bob is already in a call.',
      );
    });

    test('keeps transient create retry conservative', () {
      expect(
        CallErrorClassifier.shouldRetryTransientCreateFailure(
          '[firebase_database/unknown] Firebase Database error: Permission denied',
          const CallRetryDecision(
            kind: CallRetryDecisionKind.signalingFailed,
            userMessage: 'failed',
          ),
        ),
        isTrue,
      );
      expect(
        CallErrorClassifier.shouldRetryTransientCreateFailure(
          'Active voice call already exists for user bob.',
          const CallRetryDecision(
            kind: CallRetryDecisionKind.signalingFailed,
            userMessage: 'failed',
          ),
        ),
        isFalse,
      );
    });

    test('classifies native media, TURN, and local permission failures', () {
      expect(
        CallErrorClassifier.failureReasonForError(
          'Unable to RTCPeerConnection::setRemoteDescription',
        ),
        VoiceCallFailureReason.mediaConnectionFailed,
      );
      expect(
        CallErrorClassifier.failureReasonForError(
          const TurnUnavailableException(
            TurnReadinessResult(
              readiness: TurnReadiness.unavailableNoRelayServer,
              hasRelayServer: false,
            ),
          ),
        ),
        VoiceCallFailureReason.relayUnavailable,
      );
      expect(
        CallErrorClassifier.localMediaFailureReason(
          const CallMediaException(
            CallMediaFailureReason.cameraDenied,
            'Camera denied',
          ),
        ),
        VoiceCallFailureReason.cameraDenied,
      );
    });

    test('produces stable failure taxonomy values', () {
      expect(
        CallErrorClassifier.failureTaxonomy(
          failureCode: 'signalingFailed',
          userMessage: 'Old call state was cleaned. Try again.',
          nativeError: 'terminal room cleaned',
        ),
        'stale_lock_repaired',
      );
      expect(
        CallErrorClassifier.failureTaxonomy(
          failureCode: 'failed',
          userMessage: 'Permission denied',
          nativeError: '[firebase_database/permission-denied]',
        ),
        'firebase_permission_denied',
      );
      expect(
        CallErrorClassifier.failureTaxonomy(
          failureCode: 'microphoneDenied',
          userMessage: 'Microphone permission required.',
          nativeError: 'NotAllowedError: permission denied by user',
        ),
        'media_permission_denied',
      );
      expect(
        CallErrorClassifier.failureTaxonomy(
          failureCode: 'failed',
          userMessage: 'Call already ended.',
          nativeError: 'room is already terminal',
        ),
        'room_terminal',
      );
      expect(
        CallErrorClassifier.failureTaxonomy(
          failureCode: 'failed',
          userMessage: 'Remote data rejected.',
          nativeError: 'malformed remote candidate frame',
        ),
        'malformed_remote_data',
      );
      expect(
        CallErrorClassifier.failureTaxonomy(
          failureCode: 'relayUnavailable',
          userMessage: 'Relay connection is unavailable.',
          nativeError: 'TURN broker returned no relay candidates',
        ),
        'turn_unavailable',
      );
      expect(
        CallErrorClassifier.failureTaxonomy(
          failureCode: 'busy',
          userMessage: 'Busy.',
          nativeError: 'Busy.',
        ),
        'peer_busy_response',
      );
      expect(
        CallErrorClassifier.failureTaxonomy(
          failureCode: 'signalingFailed',
          userMessage: 'Peer is busy.',
          nativeError: 'activeVoiceUsers/bob already in a call',
        ),
        'real_busy_lock',
      );
    });
  });
}
