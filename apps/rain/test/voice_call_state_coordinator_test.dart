/// # voice_call_state_coordinator_test.dart
///
/// Tests VoiceCallStateCoordinator which maps protocol session phases to runtime phases, resolves failure reasons from error codes, and extracts diagnostic detail from session state.
///
/// **Key types:** VoiceCallStateCoordinator, VoiceCallSessionPhase, VoiceCallPhase, VoiceCallFailureReason, CallErrorClassifier
///
/// **Depends on:** package:rain/application/runtime/voice_call/voice_call_state_coordinator.dart, package:rain/application/runtime/call_error_classifier.dart, package:protocol_brain/protocol_brain.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/application/runtime/call_error_classifier.dart';
import 'package:rain/application/runtime/voice_call/voice_call_state_coordinator.dart';
import 'package:rain/application/runtime/voice_call_state.dart';

void main() {
  group('VoiceCallStateCoordinator', () {
    const coordinator = VoiceCallStateCoordinator.instance;

    test('maps protocol session phases to runtime phases', () {
      expect(
        coordinator.mapSessionPhase(VoiceCallSessionPhase.connectingMedia),
        VoiceCallPhase.connectingMedia,
      );
      expect(
        coordinator.mapSessionPhase(VoiceCallSessionPhase.outgoingRinging),
        VoiceCallPhase.outgoingRinging,
      );
      expect(
        coordinator.mapSessionPhase(VoiceCallSessionPhase.active),
        VoiceCallPhase.active,
      );
      expect(
        coordinator.mapSessionPhase(VoiceCallSessionPhase.failed),
        VoiceCallPhase.failed,
      );
    });

    test('resolves failed session reason and detail from reason code', () {
      const state = VoiceCallSessionState(
        phase: VoiceCallSessionPhase.failed,
        updatedAt: 42,
        reasonCode: CallErrorClassifier.videoRendererFailedReasonCode,
      );

      expect(
        coordinator.failureReasonForSessionState(
          state,
          localMediaFailureReason: (_) => null,
        ),
        VoiceCallFailureReason.videoRendererFailed,
      );
      expect(
        coordinator.detailForSessionState(
          state,
          localMediaFailureDetail: (_) => null,
          errorMessage: (_) => 'fallback',
        ),
        CallErrorClassifier.videoFailedMessage,
      );
    });

    test('clears expired start-blocking call state for preflight', () {
      const stale = VoiceCallState(
        phase: VoiceCallPhase.connectingMedia,
        callId: 'call-1',
        sessionEpoch: 100,
      );

      expect(
        coordinator.startPreflightState(
          stale,
          expiry: const Duration(milliseconds: 50),
          nowMs: 151,
        ),
        const VoiceCallState.idle(),
      );
    });

    test('terminal write failure resets volatile media state', () {
      const current = VoiceCallState(
        phase: VoiceCallPhase.ending,
        callId: 'call-1',
        sessionEpoch: 1,
        isCameraMuted: true,
        isDeafened: true,
        hasLocalVideo: true,
        hasRemoteVideo: true,
        mediaReconnecting: true,
      );

      final next = coordinator.stateAfterTerminalWriteFailure(
        current,
        error: 'denied',
        nowMs: 99,
      );

      expect(next.phase, VoiceCallPhase.failed);
      expect(next.failureReason, VoiceCallFailureReason.signalingFailed);
      expect(next.isCameraMuted, isFalse);
      expect(next.isDeafened, isFalse);
      expect(next.hasLocalVideo, isFalse);
      expect(next.hasRemoteVideo, isFalse);
      expect(next.mediaReconnecting, isFalse);
      expect(next.updatedAt, 99);
    });
  });
}
