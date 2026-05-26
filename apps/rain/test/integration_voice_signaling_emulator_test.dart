import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'utils/firebase_emulator_signaling_adapter.dart';

const bool runIntegrationTests = bool.fromEnvironment(
  'RUN_RAIN_INTEGRATION_TESTS',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!runIntegrationTests) return;
    HttpOverrides.global = null;
  });

  tearDownAll(() {
    if (!runIntegrationTests) return;
    HttpOverrides.global = null;
  });

  test(
    'Firebase emulator voice signaling contract',
    () async {
      final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final alice = 'alicev$runId';
      final bob = 'bobv$runId';
      final callId = 'voice-$runId';
      final createdAt = DateTime.now().millisecondsSinceEpoch;

      final adapterAlice = FirebaseEmulatorSignalingAdapter();
      final adapterBob = FirebaseEmulatorSignalingAdapter();

      try {
        await adapterAlice.register(alice, 'alicepw');
        await adapterBob.register(bob, 'bob123');
        await adapterAlice.login(alice, 'alicepw');
        await adapterAlice.writeFriendRequest(bob, alice);
        await adapterBob.login(bob, 'bob123');
        await adapterBob.upsertFriendship(bob, alice);
        await adapterAlice.login(alice, 'alicepw');

        final incoming = adapterBob.watchIncomingCalls(bob).first;
        final room = await adapterAlice.createOutgoingCall(
          callId: callId,
          caller: alice,
          callee: bob,
          createdAt: createdAt,
          expiresAt: createdAt + const Duration(minutes: 5).inMilliseconds,
        );

        expect(room.status, VoiceCallSignalingStatus.ringing);
        expect((await incoming).callId, callId);

        await adapterBob.acceptCall(
          callId: callId,
          callee: bob,
          acceptedAt: createdAt + 1,
        );

        final offerEvent = adapterBob.watchVoiceOffer(callId).first;
        await adapterAlice.writeVoiceOffer(
          callId: callId,
          caller: alice,
          offer: _envelope('encrypted-offer', createdAt + 2),
          updatedAt: createdAt + 2,
        );
        expect((await offerEvent).ciphertext, 'encrypted-offer');

        final answerEvent = adapterAlice.watchVoiceAnswer(callId).first;
        await adapterBob.writeVoiceAnswer(
          callId: callId,
          callee: bob,
          answer: _envelope('encrypted-answer', createdAt + 3),
          updatedAt: createdAt + 3,
        );
        expect((await answerEvent).ciphertext, 'encrypted-answer');

        final callerIce = adapterBob
            .watchIceCandidates(callId: callId, role: VoiceCallRole.caller)
            .first;
        await adapterAlice.writeIceCandidate(
          callId: callId,
          username: alice,
          role: VoiceCallRole.caller,
          candidate: _envelope('encrypted-caller-ice', createdAt + 4),
          createdAt: createdAt + 4,
        );
        expect((await callerIce).envelope.ciphertext, 'encrypted-caller-ice');

        final calleeIce = adapterAlice
            .watchIceCandidates(callId: callId, role: VoiceCallRole.callee)
            .first;
        await adapterBob.writeIceCandidate(
          callId: callId,
          username: bob,
          role: VoiceCallRole.callee,
          candidate: _envelope('encrypted-callee-ice', createdAt + 5),
          createdAt: createdAt + 5,
        );
        expect((await calleeIce).envelope.ciphertext, 'encrypted-callee-ice');

        await adapterBob.markConnected(
          callId: callId,
          username: bob,
          connectedAt: createdAt + 6,
        );
        await adapterAlice.endCall(
          callId: callId,
          username: alice,
          status: VoiceCallSignalingStatus.ended,
          endedAt: createdAt + 7,
          reasonCode: 'hangup',
          reason: 'Ended.',
        );

        final ended = await adapterBob.fetchCall(callId);
        expect(ended?.status, VoiceCallSignalingStatus.ended);
        expect(ended?.endedBy, alice);

        final retryCallId = 'voice-retry-$runId';
        final retryRoom = await adapterAlice.createOutgoingCall(
          callId: retryCallId,
          caller: alice,
          callee: bob,
          createdAt: createdAt + 8,
          expiresAt: createdAt + const Duration(minutes: 5).inMilliseconds + 8,
        );
        expect(retryRoom.status, VoiceCallSignalingStatus.ringing);
        await adapterAlice.endCall(
          callId: retryCallId,
          username: alice,
          status: VoiceCallSignalingStatus.ended,
          endedAt: createdAt + 9,
          reasonCode: 'cleanup',
          reason: 'Test cleanup.',
        );

        final reverseVideoCallId = 'video-reverse-$runId';
        final reverseIncoming = adapterAlice.watchIncomingCalls(alice).first;
        final reverseRoom = await adapterBob.createOutgoingCall(
          callId: reverseVideoCallId,
          caller: bob,
          callee: alice,
          createdAt: createdAt + 10,
          expiresAt: createdAt + const Duration(minutes: 5).inMilliseconds + 10,
          mediaMode: CallMediaMode.video,
        );
        expect(reverseRoom.status, VoiceCallSignalingStatus.ringing);
        expect(reverseRoom.mediaMode, CallMediaMode.video);
        expect((await reverseIncoming).callId, reverseVideoCallId);
        await adapterAlice.endCall(
          callId: reverseVideoCallId,
          username: alice,
          status: VoiceCallSignalingStatus.ended,
          endedAt: createdAt + 11,
          reasonCode: 'cleanup',
          reason: 'Reverse video cleanup.',
        );
      } finally {
        await adapterAlice.dispose();
        await adapterBob.dispose();
      }
    },
    skip: runIntegrationTests ? null : 'Requires Firebase emulators',
  );
}

VoiceSignalingEnvelope _envelope(String ciphertext, int timestamp) {
  return VoiceSignalingEnvelope(
    v: VoiceSignalingEnvelope.version,
    alg: VoiceSignalingEnvelope.algorithmName,
    ts: timestamp,
    nonce: 'nonce-$timestamp',
    ciphertext: ciphertext,
    mac: 'mac-$timestamp',
  );
}
