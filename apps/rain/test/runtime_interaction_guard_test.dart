import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/runtime_interaction_guard.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  group('RuntimeInteractionGuard', () {
    test('manual disconnect blocks automatic reconnect only', () {
      final automatic = RuntimeInteractionGuard.canConnectPeer(
        peerId: 'bob',
        interactive: false,
        manualDisconnectedPeers: <String>{'bob'},
        peerConnectionAvailable: true,
      );
      final interactive = RuntimeInteractionGuard.canConnectPeer(
        peerId: 'bob',
        interactive: true,
        manualDisconnectedPeers: <String>{'bob'},
        peerConnectionAvailable: true,
      );

      expect(automatic.allowed, isFalse);
      expect(
        automatic.reasonCode,
        RuntimeInteractionReasonCode.manualDisconnectActive,
      );
      expect(automatic.userMessage, contains('Press Connect'));
      expect(interactive.allowed, isTrue);
    });

    test('active call blocks calling another peer with specific message', () {
      final decision = RuntimeInteractionGuard.canStartCall(
        peerId: 'cara',
        mediaMode: CallMediaMode.video,
        voiceCallState: VoiceCallState(
          phase: VoiceCallPhase.active,
          peerId: 'bob',
          callId: 'call-1',
          sessionEpoch: 1,
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, RuntimeInteractionReasonCode.activeCall);
      expect(decision.blockingPeerId, 'bob');
      expect(decision.callId, 'call-1');
      expect(
        decision.userMessage,
        'You are already in a call with @bob. End it before calling @cara.',
      );
    });

    test('failed call does not block a retry', () {
      final decision = RuntimeInteractionGuard.canStartCall(
        peerId: 'bob',
        mediaMode: CallMediaMode.audio,
        voiceCallState: const VoiceCallState(
          phase: VoiceCallPhase.failed,
          peerId: 'bob',
          callId: 'call-1',
          sessionEpoch: 1,
        ),
      );

      expect(decision.allowed, isTrue);
    });

    test('active transfer blocks starting and accepting calls globally', () {
      final transfer = _transfer(peerId: 'bob');
      final outgoing = RuntimeInteractionGuard.canStartCall(
        peerId: 'cara',
        mediaMode: CallMediaMode.audio,
        voiceCallState: const VoiceCallState.idle(),
        activeTransfer: transfer,
      );
      final incoming = RuntimeInteractionGuard.canAcceptCall(
        peerId: 'cara',
        callId: 'call-2',
        voiceCallState: const VoiceCallState(
          phase: VoiceCallPhase.incomingRinging,
          peerId: 'cara',
          callId: 'call-2',
          sessionEpoch: 2,
        ),
        activeTransfer: transfer,
      );

      expect(outgoing.allowed, isFalse);
      expect(incoming.allowed, isFalse);
      expect(
        outgoing.reasonCode,
        RuntimeInteractionReasonCode.activeFileTransfer,
      );
      expect(incoming.transferId, 'transfer-1');
      expect(outgoing.blockingPeerId, 'bob');
    });

    test('active call blocks file transfers for every peer', () {
      final decision = RuntimeInteractionGuard.canStartFileTransfer(
        peerId: 'cara',
        voiceCallState: VoiceCallState(
          phase: VoiceCallPhase.outgoingRinging,
          peerId: 'bob',
          callId: 'call-1',
          sessionEpoch: 1,
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reasonCode, RuntimeInteractionReasonCode.activeCall);
      expect(decision.blockingPeerId, 'bob');
      expect(decision.userMessage, 'Finish the call before sending files.');
    });

    test(
      'false busy cleanup becomes a retryable guard decision',
      () {
        fail(
          'Phase 03 must add a stale-call cleanup/false-busy reason so the '
          'UI can show "Old call state was cleaned. Try again." instead of '
          'leaving the caller stuck as peer busy.',
        );
      },
      skip: 'Phase 03 adds stale cleanup guard decisions.',
    );

    test(
      'call cleanup in progress blocks duplicate retry with explicit message',
      () {
        fail(
          'Phase 03 must expose a cleanup-in-progress decision that blocks a '
          'duplicate call retry with "Call state is cleaning up. Try again in a moment.".',
        );
      },
      skip: 'Phase 03 adds cleanup-in-progress guard decisions.',
    );
  });
}

FileTransferRecord _transfer({required String peerId}) {
  return FileTransferRecord(
    id: 'transfer-1',
    peerId: peerId,
    messageId: 'message-1',
    direction: FileTransferDirection.outgoing,
    fileName: 'note.txt',
    fileSize: 1,
    bytesTransferred: 0,
    state: FileTransferState.sending,
    createdAt: 1,
    updatedAt: 1,
  );
}
