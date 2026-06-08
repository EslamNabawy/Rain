import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/application/runtime/call_error_classifier.dart';
import 'package:rain/application/runtime/voice_call_room_coordinator.dart';
import 'package:rain/application/runtime/voice_call_state.dart';

void main() {
  group('VoiceCallRoomCoordinator', () {
    const coordinator = VoiceCallRoomCoordinator.instance;

    group('recordRoomStatusTransition', () {
      test('returns null for first transition', () {
        final map = <String, VoiceCallSignalingStatus>{};
        final prev = coordinator.recordRoomStatusTransition(
          map,
          'call-1',
          VoiceCallSignalingStatus.ringing,
        );
        expect(prev, isNull);
        expect(map['call-1'], VoiceCallSignalingStatus.ringing);
      });

      test('returns previous status on subsequent transition', () {
        final map = <String, VoiceCallSignalingStatus>{
          'call-1': VoiceCallSignalingStatus.ringing,
        };
        final prev = coordinator.recordRoomStatusTransition(
          map,
          'call-1',
          VoiceCallSignalingStatus.connected,
        );
        expect(prev, VoiceCallSignalingStatus.ringing);
        expect(map['call-1'], VoiceCallSignalingStatus.connected);
      });
    });

    group('terminalRoomDetail', () {
      test('returns peer ended message when ended by remote', () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          endedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.ended,
          endedBy: 'alice',
        );
        final detail = coordinator.terminalRoomDetail(
          room,
          'bob',
          detailForSessionState: (_) => null,
        );
        expect(detail, 'Peer ended the call.');
      });

      test('returns room reason when ended locally', () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          endedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.ended,
          endedBy: 'bob',
          reason: 'All done',
        );
        final detail = coordinator.terminalRoomDetail(
          room,
          'bob',
          detailForSessionState: (_) => null,
        );
        expect(detail, 'All done');
      });

      test('returns non-empty room reason for non-ended terminal status', () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.failed,
          reason: 'Something went wrong',
        );
        final detail = coordinator.terminalRoomDetail(
          room,
          'bob',
          detailForSessionState: (_) => null,
        );
        expect(detail, 'Something went wrong');
      });

      test('delegates to detailForSessionState when room reason is empty',
          () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.failed,
          reasonCode: CallErrorClassifier.microphoneDeniedReasonCode,
        );
        final detail = coordinator.terminalRoomDetail(
          room,
          'bob',
          detailForSessionState: (_) => 'Mapped detail',
        );
        expect(detail, 'Mapped detail');
      });

      test('falls back to mediaFailedMessage when everything is null', () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.failed,
        );
        final detail = coordinator.terminalRoomDetail(
          room,
          'bob',
          detailForSessionState: (_) => null,
        );
        expect(detail, CallErrorClassifier.mediaFailedMessage);
      });

      test('skips reason for remote media permission codes', () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.failed,
          reason: 'Some reason',
          reasonCode: CallErrorClassifier.remoteMicrophonePermissionRequired,
        );
        final detail = coordinator.terminalRoomDetail(
          room,
          'bob',
          detailForSessionState: (_) => 'Permission detail',
        );
        expect(detail, 'Permission detail');
      });
    });

    group('terminalRoomFailureReason', () {
      test('returns null for cleanly ended room', () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          endedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.ended,
          endedBy: 'alice',
        );
        final reason = coordinator.terminalRoomFailureReason(
          room,
          failureReasonForSessionState: (_) => null,
        );
        expect(reason, isNull);
      });

      test('delegates to failureReasonForSessionState for non-ended', () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.failed,
          reasonCode: CallErrorClassifier.failedReasonCode,
        );
        final reason = coordinator.terminalRoomFailureReason(
          room,
          failureReasonForSessionState: (_) =>
              VoiceCallFailureReason.mediaConnectionFailed,
        );
        expect(reason, VoiceCallFailureReason.mediaConnectionFailed);
      });

      test('falls back to mediaConnectionFailed', () {
        final room = const VoiceCallRoom(
          v: 1,
          callId: 'c1',
          pairId: 'alice:bob',
          caller: 'alice',
          callee: 'bob',
          createdAt: 100,
          updatedAt: 200,
          expiresAt: 300,
          status: VoiceCallSignalingStatus.failed,
        );
        final reason = coordinator.terminalRoomFailureReason(
          room,
          failureReasonForSessionState: (_) => null,
        );
        expect(reason, VoiceCallFailureReason.mediaConnectionFailed);
      });
    });

    group('reasonCodeForFailure', () {
      test('returns null for null reason', () {
        expect(coordinator.reasonCodeForFailure(null), isNull);
      });

      test('maps microphoneDenied correctly', () {
        expect(
          coordinator.reasonCodeForFailure(
              VoiceCallFailureReason.microphoneDenied),
          CallErrorClassifier.microphoneDeniedReasonCode,
        );
      });

      test('maps remoteMicrophoneDenied to microphoneDenied code', () {
        expect(
          coordinator.reasonCodeForFailure(
              VoiceCallFailureReason.remoteMicrophoneDenied),
          CallErrorClassifier.microphoneDeniedReasonCode,
        );
      });

      test('maps fileTransferActive to busy code', () {
        expect(
          coordinator.reasonCodeForFailure(
              VoiceCallFailureReason.fileTransferActive),
          CallErrorClassifier.busyReasonCode,
        );
      });

      test('maps videoRendererFailed correctly', () {
        expect(
          coordinator.reasonCodeForFailure(
              VoiceCallFailureReason.videoRendererFailed),
          CallErrorClassifier.videoRendererFailedReasonCode,
        );
      });

      test('maps mediaConnectionFailed correctly', () {
        expect(
          coordinator.reasonCodeForFailure(
              VoiceCallFailureReason.mediaConnectionFailed),
          CallErrorClassifier.failedReasonCode,
        );
      });
    });

    group('isTerminalRoomWriteError', () {
      test('detects PERMISSION_DENIED', () {
        expect(
          coordinator.isTerminalRoomWriteError(
              StateError('PERMISSION_DENIED: write denied')),
          isTrue,
        );
      });

      test('detects already deleted', () {
        expect(
          coordinator.isTerminalRoomWriteError(
              StateError('Node already deleted')),
          isTrue,
        );
      });

      test('returns false for unrelated errors', () {
        expect(
          coordinator.isTerminalRoomWriteError(StateError('network timeout')),
          isFalse,
        );
      });
    });
  });
}
