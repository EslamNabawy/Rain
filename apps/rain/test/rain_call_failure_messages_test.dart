/// # rain_call_failure_messages_test.dart
///
/// Tests for voice/video call failure message sanitization and mapping. Covers WebRTC native errors, Firebase permission errors, network loss detection, and retryability logic.
///
/// **Key types:** rainSanitizeVoiceCallFailureDetail, rainVoiceCallFailureDetail, rainVoiceCallCanRetry, VoiceCallState, VoiceCallFailureReason
///
/// **Depends on:** flutter_test, rain voice_call_state, rain_call_controls
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';

void main() {
  group('voice/video failure message regressions', () {
    test('WebRTC transceiver and SDP native errors map to media failure', () {
      expect(
        rainSanitizeVoiceCallFailureDetail(
          'Unable to RTCRtpTransceiver::setDirection: '
          'RtpTransceiver has been disposed.',
        ),
        'Call media could not connect. Try again.',
      );
      expect(
        rainSanitizeVoiceCallFailureDetail(
          'Unable to RTCPeerConnection::setRemoteDescription: '
          'peerConnectionSetRemoteDescription failed.',
        ),
        'Call media could not connect. Try again.',
      );
    });

    test('Firebase permission-denied errors map to setup failure', () {
      expect(
        rainSanitizeVoiceCallFailureDetail(
          '[firebase_database/unknown] Firebase Database error: '
          'Permission denied',
        ),
        'Call setup failed. Try again.',
      );
    });

    test('network-loss details stay distinct from media setup failures', () {
      expect(
        rainSanitizeVoiceCallFailureDetail(
          'Network connection lost. Call ended.',
        ),
        'Network connection lost. Call ended.',
      );
    });

    test('typed media failure reason wins over raw native detail', () {
      final state = VoiceCallState(
        phase: VoiceCallPhase.failed,
        peerId: 'bob',
        callId: 'call-1',
        isOutgoing: true,
        detail: 'Network connection lost. Call ended.',
        failureReason: VoiceCallFailureReason.mediaConnectionFailed,
      );

      expect(
        rainVoiceCallFailureDetail(state),
        'Call media could not connect. Try again.',
      );
      expect(rainVoiceCallCanRetry(state), isTrue);
    });

    test('network loss is terminal and not immediately retryable', () {
      final state = VoiceCallState(
        phase: VoiceCallPhase.failed,
        peerId: 'bob',
        callId: 'call-1',
        isOutgoing: true,
        detail: 'ICE disconnected after peer closed Rain.',
        failureReason: VoiceCallFailureReason.networkLost,
      );

      expect(
        rainVoiceCallFailureDetail(state),
        'Network connection lost. Call ended.',
      );
      expect(rainVoiceCallCanRetry(state), isFalse);
    });
  });
}
