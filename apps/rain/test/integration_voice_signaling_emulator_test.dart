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

  test(
    'Firebase emulator rejects signaling rule bypasses',
    () async {
      final runId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final alice = 'alicex$runId';
      final bob = 'bobx$runId';
      final createdAt = DateTime.now().millisecondsSinceEpoch;
      final expiresAt = createdAt + const Duration(minutes: 5).inMilliseconds;

      final adapterAlice = FirebaseEmulatorSignalingAdapter();
      final adapterBob = FirebaseEmulatorSignalingAdapter();

      try {
        await _registerFriends(
          adapterAlice: adapterAlice,
          adapterBob: adapterBob,
          alice: alice,
          bob: bob,
        );

        final roomId = voiceCallPairId(alice, bob);
        await adapterAlice.putRawForTest(
          <String>['rooms', roomId],
          <String, Object?>{
            'userA': alice,
            'userB': bob,
            'attemptId': '$roomId:$createdAt',
            'createdAt': createdAt,
            'updatedAt': createdAt,
            'expiresAt': expiresAt,
            'offer': _rawEnvelope('offer', createdAt),
          },
        );
        await adapterBob.patchRawForTest(
          <String>['rooms', roomId],
          <String, Object?>{
            'answer': _rawEnvelope('answer', createdAt + 1),
            'updatedAt': createdAt + 1,
          },
        );

        await _expectDenied(
          adapterAlice.patchRawForTest(
            <String>['rooms', roomId],
            <String, Object?>{'attemptId': '$roomId:${createdAt + 2}'},
          ),
        );
        await _expectDenied(
          adapterAlice.patchRawForTest(
            <String>['rooms', roomId],
            <String, Object?>{'createdAt': createdAt + 2},
          ),
        );
        await _expectDenied(
          adapterAlice.putRawForTest(
            <String>['rooms', roomId],
            <String, Object?>{
              'userA': alice,
              'userB': bob,
              'attemptId': '$roomId:${createdAt + 3}',
              'createdAt': createdAt + 3,
              'updatedAt': createdAt + 3,
              'expiresAt': expiresAt + 3,
              'offer': _rawEnvelope('new-offer', createdAt + 3),
              'answer': _rawEnvelope('stale-answer', createdAt + 1),
            },
          ),
        );
        await _expectDenied(
          adapterBob.patchRawForTest(
            <String>['rooms', roomId],
            <String, Object?>{
              'callerICE/bad': _rawEnvelope('caller-ice', createdAt + 4),
            },
          ),
        );

        await _expectDenied(
          _createMaliciousVoiceCall(
            adapterAlice: adapterAlice,
            callId: 'preseed-offer-$runId',
            caller: alice,
            callee: bob,
            createdAt: createdAt + 10,
            expiresAt: expiresAt + 10,
            extra: <String, Object?>{
              'offer': _rawEnvelope('offer', createdAt + 10),
            },
          ),
        );
        await _expectDenied(
          _createMaliciousVoiceCall(
            adapterAlice: adapterAlice,
            callId: 'preseed-answer-$runId',
            caller: alice,
            callee: bob,
            createdAt: createdAt + 20,
            expiresAt: expiresAt + 20,
            extra: <String, Object?>{
              'answer': _rawEnvelope('answer', createdAt + 20),
            },
          ),
        );
        await _expectDenied(
          _createMaliciousVoiceCall(
            adapterAlice: adapterAlice,
            callId: 'preseed-ice-$runId',
            caller: alice,
            callee: bob,
            createdAt: createdAt + 30,
            expiresAt: expiresAt + 30,
            extra: <String, Object?>{
              'ice': <String, Object?>{
                'callee': <String, Object?>{
                  'bad': _rawEnvelope('callee-ice', createdAt + 30),
                },
              },
            },
          ),
        );
        await _expectDenied(
          _createMaliciousVoiceCall(
            adapterAlice: adapterAlice,
            callId: 'preseed-terminal-$runId',
            caller: alice,
            callee: bob,
            createdAt: createdAt + 40,
            expiresAt: expiresAt + 40,
            extra: <String, Object?>{
              'endedAt': createdAt + 40,
              'endedBy': alice,
            },
          ),
        );
        await _expectDenied(
          _createMaliciousVoiceCall(
            adapterAlice: adapterAlice,
            callId: 'preseed-muted-$runId',
            caller: alice,
            callee: bob,
            createdAt: createdAt + 50,
            expiresAt: expiresAt + 50,
            extra: <String, Object?>{
              'muted': <String, Object?>{alice: true, bob: false},
            },
          ),
        );
        await _expectDenied(
          _createMaliciousVoiceCall(
            adapterAlice: adapterAlice,
            callId: 'preseed-camera-muted-$runId',
            caller: alice,
            callee: bob,
            createdAt: createdAt + 55,
            expiresAt: expiresAt + 55,
            extra: <String, Object?>{
              'cameraMuted': <String, Object?>{alice: false, bob: true},
            },
          ),
        );
        await _expectDenied(
          adapterAlice.putRawForTest(
            <String>['voiceCallInboxes', bob, 'bad-inbox-$runId'],
            _voiceInboxJson(
              from: alice,
              to: bob,
              createdAt: createdAt + 60,
              expiresAt: expiresAt + 60,
              status: 'accepted',
            ),
          ),
        );

        final callId = 'valid-$runId';
        await adapterAlice.createOutgoingCall(
          callId: callId,
          caller: alice,
          callee: bob,
          createdAt: createdAt + 70,
          expiresAt: expiresAt + 70,
        );
        await _expectDenied(
          adapterAlice.patchRawForTest(
            <String>['voiceCalls', callId],
            <String, Object?>{
              'status': 'accepted',
              'updatedAt': createdAt + 71,
            },
          ),
        );
        await adapterBob.acceptCall(
          callId: callId,
          callee: bob,
          acceptedAt: createdAt + 72,
        );
        await _expectDenied(
          adapterBob.putRawForTest(<String>[
            'voiceCalls',
            callId,
            'offer',
          ], _rawEnvelope('callee-offer', createdAt + 73)),
        );
        await adapterAlice.writeVoiceOffer(
          callId: callId,
          caller: alice,
          offer: _envelope('caller-offer', createdAt + 74),
          updatedAt: createdAt + 74,
        );
        await _expectDenied(
          adapterAlice.putRawForTest(<String>[
            'voiceCalls',
            callId,
            'answer',
          ], _rawEnvelope('caller-answer', createdAt + 75)),
        );
        await _expectDenied(
          adapterBob.putRawForTest(<String>[
            'voiceCalls',
            callId,
            'ice',
            'caller',
            'bad',
          ], _rawEnvelope('callee-as-caller-ice', createdAt + 76)),
        );
      } finally {
        await adapterAlice.dispose();
        await adapterBob.dispose();
      }
    },
    skip: runIntegrationTests ? null : 'Requires Firebase emulators',
  );
}

Future<void> _registerFriends({
  required FirebaseEmulatorSignalingAdapter adapterAlice,
  required FirebaseEmulatorSignalingAdapter adapterBob,
  required String alice,
  required String bob,
}) async {
  await adapterAlice.register(alice, 'alicepw');
  await adapterBob.register(bob, 'bob123');
  await adapterAlice.login(alice, 'alicepw');
  await adapterAlice.writeFriendRequest(bob, alice);
  await adapterBob.login(bob, 'bob123');
  await adapterBob.upsertFriendship(bob, alice);
  await adapterAlice.login(alice, 'alicepw');
}

Future<void> _expectDenied(Future<void> operation) async {
  await expectLater(
    operation,
    throwsA(
      isA<HttpException>().having(
        (error) => error.message,
        'message',
        contains('Permission denied'),
      ),
    ),
  );
}

Future<void> _createMaliciousVoiceCall({
  required FirebaseEmulatorSignalingAdapter adapterAlice,
  required String callId,
  required String caller,
  required String callee,
  required int createdAt,
  required int expiresAt,
  required Map<String, Object?> extra,
}) async {
  final pairId = voiceCallPairId(caller, callee);
  await adapterAlice.patchRawForTest(<String>[], <String, Object?>{
    'activeVoicePairs/$pairId': VoiceActivePairLock(
      pairId: pairId,
      callId: callId,
      caller: caller,
      callee: callee,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
    ).toJson(),
    'activeVoiceUsers/$caller': VoiceActiveUserLock(
      username: caller,
      callId: callId,
      pairId: pairId,
      caller: caller,
      callee: callee,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
    ).toJson(),
    'activeVoiceUsers/$callee': VoiceActiveUserLock(
      username: callee,
      callId: callId,
      pairId: pairId,
      caller: caller,
      callee: callee,
      createdAt: createdAt,
      updatedAt: createdAt,
      expiresAt: expiresAt,
    ).toJson(),
  });
  try {
    await adapterAlice.putRawForTest(
      <String>['voiceCalls', callId],
      <String, Object?>{
        ..._voiceRoomJson(
          caller: caller,
          callee: callee,
          createdAt: createdAt,
          expiresAt: expiresAt,
        ),
        ...extra,
      },
    );
  } finally {
    await adapterAlice.deleteRawForTest(<String>['activeVoicePairs', pairId]);
    await adapterAlice.deleteRawForTest(<String>['activeVoiceUsers', caller]);
    await adapterAlice.deleteRawForTest(<String>['activeVoiceUsers', callee]);
  }
}

Map<String, Object?> _voiceRoomJson({
  required String caller,
  required String callee,
  required int createdAt,
  required int expiresAt,
}) {
  return <String, Object?>{
    'v': VoiceCallRoom.version,
    'pairId': voiceCallPairId(caller, callee),
    'caller': caller,
    'callee': callee,
    'status': VoiceCallSignalingStatus.ringing.name,
    'mediaMode': CallMediaMode.audio.name,
    'createdAt': createdAt,
    'updatedAt': createdAt,
    'expiresAt': expiresAt,
    'muted': <String, Object?>{caller: false, callee: false},
  };
}

Map<String, Object?> _voiceInboxJson({
  required String from,
  required String to,
  required int createdAt,
  required int expiresAt,
  required String status,
}) {
  return <String, Object?>{
    'from': from,
    'to': to,
    'pairId': voiceCallPairId(from, to),
    'status': status,
    'createdAt': createdAt,
    'updatedAt': createdAt,
    'expiresAt': expiresAt,
  };
}

Map<String, Object?> _rawEnvelope(String ciphertext, int timestamp) {
  return _envelope(
    ciphertext,
    timestamp,
  ).toJson(maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength);
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
