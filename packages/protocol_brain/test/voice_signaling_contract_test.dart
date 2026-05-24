import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:protocol_brain/testing.dart';

void main() {
  test('normalizes participants and derives canonical pair roles', () {
    expect(voiceCallPairId(' Bob ', 'alice'), 'alice:bob');

    final room = _room(
      caller: 'alice',
      callee: 'bob',
      status: VoiceCallSignalingStatus.ringing,
    );

    expect(
      voiceCallRoleFor(room: room, username: 'ALICE'),
      VoiceCallRole.caller,
    );
    expect(
      voiceCallRoleFor(room: room, username: ' bob '),
      VoiceCallRole.callee,
    );
    expect(
      () => voiceCallPairId('alice', 'Alice'),
      throwsA(isA<FormatException>()),
    );
  });

  test('encrypted envelopes validate bounded SDP and ICE payload sizes', () {
    final offer = _envelope(ciphertext: 'sdp-envelope');

    expect(
      offer.toJson(
        maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
      ),
      containsPair('alg', VoiceSignalingEnvelope.algorithmName),
    );
    expect(
      () =>
          _envelope(
            ciphertext:
                'x' * (VoiceSignalingEnvelope.maxIceCiphertextLength + 1),
          ).toJson(
            maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength,
          ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => VoiceSignalingEnvelope.fromJson(<Object?, Object?>{
        'v': 1,
        'alg': 'plaintext',
        'ts': 1000,
        'nonce': 'nonce',
        'ciphertext': 'candidate',
        'mac': 'mac',
      }, maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'fake adapter creates room, callee inbox, and active pair lock',
    () async {
      final adapter = FakeVoiceSignalingAdapter();
      addTearDown(adapter.dispose);

      final inboxEvent = adapter.watchIncomingCalls('bob').first;
      final roomEvent = adapter
          .watchCall('call-1')
          .where((VoiceCallRoom? room) => room != null)
          .cast<VoiceCallRoom>()
          .first;

      final room = await adapter.createOutgoingCall(
        callId: 'call-1',
        caller: 'Alice',
        callee: 'Bob',
        createdAt: 1000,
        expiresAt: 2000,
      );

      expect(room.callId, 'call-1');
      expect(room.pairId, 'alice:bob');
      expect(room.status, VoiceCallSignalingStatus.ringing);
      expect(adapter.activePairLocks.keys, contains('alice:bob'));
      expect(adapter.inboxFor('bob').single.callId, 'call-1');
      expect((await inboxEvent).status, VoiceCallSignalingStatus.ringing);
      expect((await roomEvent).callId, 'call-1');

      await expectLater(
        adapter.createOutgoingCall(
          callId: 'call-2',
          caller: 'bob',
          callee: 'alice',
          createdAt: 1100,
          expiresAt: 2100,
        ),
        throwsA(isA<VoiceSignalingException>()),
      );
    },
  );

  test('fake adapter reclaims stale orphan active pair lock', () async {
    final adapter = FakeVoiceSignalingAdapter();
    addTearDown(adapter.dispose);

    adapter.seedActivePairLockForTest(
      const VoiceActivePairLock(
        pairId: 'alice:bob',
        callId: 'orphan-call',
        caller: 'alice',
        callee: 'bob',
        createdAt: 1000,
        updatedAt: 1000,
        expiresAt: 60000,
      ),
    );

    final room = await adapter.createOutgoingCall(
      callId: 'call-2',
      caller: 'alice',
      callee: 'bob',
      createdAt: 20000,
      expiresAt: 80000,
    );

    expect(room.callId, 'call-2');
    expect(adapter.activePairLocks['alice:bob']?.callId, 'call-2');
    expect(adapter.rooms.keys, contains('call-2'));
  });

  test('fake adapter reclaims caller-owned orphan lock immediately', () async {
    final adapter = FakeVoiceSignalingAdapter();
    addTearDown(adapter.dispose);

    adapter.seedActivePairLockForTest(
      const VoiceActivePairLock(
        pairId: 'alice:bob',
        callId: 'orphan-call',
        caller: 'alice',
        callee: 'bob',
        createdAt: 1000,
        updatedAt: 1000,
        expiresAt: 60000,
      ),
    );

    final room = await adapter.createOutgoingCall(
      callId: 'call-2',
      caller: 'alice',
      callee: 'bob',
      createdAt: 1001,
      expiresAt: 61000,
    );

    expect(room.callId, 'call-2');
    expect(adapter.activePairLocks['alice:bob']?.callId, 'call-2');
    expect(adapter.inboxFor('bob').single.callId, 'call-2');
  });

  test('fake adapter does not let callee steal fresh orphan lock', () async {
    final adapter = FakeVoiceSignalingAdapter();
    addTearDown(adapter.dispose);

    adapter.seedActivePairLockForTest(
      const VoiceActivePairLock(
        pairId: 'alice:bob',
        callId: 'orphan-call',
        caller: 'alice',
        callee: 'bob',
        createdAt: 1000,
        updatedAt: 1000,
        expiresAt: 60000,
      ),
    );

    await expectLater(
      adapter.createOutgoingCall(
        callId: 'call-2',
        caller: 'bob',
        callee: 'alice',
        createdAt: 1001,
        expiresAt: 61000,
      ),
      throwsA(isA<VoiceSignalingException>()),
    );

    expect(adapter.activePairLocks['alice:bob']?.callId, 'orphan-call');
    expect(adapter.rooms, isEmpty);
  });

  test('fake adapter reclaims terminal room with leftover lock', () async {
    final adapter = FakeVoiceSignalingAdapter();
    addTearDown(adapter.dispose);

    await adapter.createOutgoingCall(
      callId: 'call-1',
      caller: 'alice',
      callee: 'bob',
      createdAt: 1000,
      expiresAt: 60000,
    );
    await adapter.endCall(
      callId: 'call-1',
      username: 'alice',
      status: VoiceCallSignalingStatus.failed,
      endedAt: 1200,
      reasonCode: 'mediaConnectionFailed',
      reason: 'Call media could not connect.',
    );
    adapter.seedActivePairLockForTest(
      const VoiceActivePairLock(
        pairId: 'alice:bob',
        callId: 'call-1',
        caller: 'alice',
        callee: 'bob',
        createdAt: 1000,
        updatedAt: 1000,
        expiresAt: 60000,
      ),
    );

    final room = await adapter.createOutgoingCall(
      callId: 'call-2',
      caller: 'alice',
      callee: 'bob',
      createdAt: 1300,
      expiresAt: 61300,
    );

    expect(room.callId, 'call-2');
    expect(adapter.activePairLocks['alice:bob']?.callId, 'call-2');
    expect(adapter.rooms.keys, isNot(contains('call-1')));
  });

  test(
    'fake adapter deleting old terminal room preserves newer lock',
    () async {
      final adapter = FakeVoiceSignalingAdapter();
      addTearDown(adapter.dispose);

      await adapter.createOutgoingCall(
        callId: 'call-1',
        caller: 'alice',
        callee: 'bob',
        createdAt: 1000,
        expiresAt: 60000,
      );
      await adapter.endCall(
        callId: 'call-1',
        username: 'alice',
        status: VoiceCallSignalingStatus.ended,
        endedAt: 1100,
        reasonCode: 'hangup',
        reason: 'Ended.',
      );
      await adapter.createOutgoingCall(
        callId: 'call-2',
        caller: 'alice',
        callee: 'bob',
        createdAt: 1200,
        expiresAt: 61200,
      );

      await adapter.deleteCall('call-1');

      expect(adapter.rooms.keys, contains('call-2'));
      expect(adapter.activePairLocks['alice:bob']?.callId, 'call-2');
    },
  );

  test('fake adapter stores video media mode and camera mute state', () async {
    final adapter = FakeVoiceSignalingAdapter();
    addTearDown(adapter.dispose);

    final room = await adapter.createOutgoingCall(
      callId: 'call-1',
      caller: 'alice',
      callee: 'bob',
      createdAt: 1000,
      expiresAt: 2000,
      mediaMode: CallMediaMode.video,
    );

    expect(room.mediaMode, CallMediaMode.video);
    expect(room.toJson(), containsPair('mediaMode', 'video'));
    expect(room.cameraMuted, <String, bool>{'alice': false, 'bob': false});

    await adapter.setCameraMuted(
      callId: 'call-1',
      username: 'alice',
      cameraMuted: true,
      updatedAt: 1100,
    );

    final updated = await adapter.fetchCall('call-1');
    expect(updated?.mediaMode, CallMediaMode.video);
    expect(updated?.cameraMuted['alice'], isTrue);
  });

  test('old room without media mode reads as audio', () {
    final room = VoiceCallRoom.fromJson(
      callId: 'call-1',
      json: _roomJson()..remove('mediaMode'),
    );

    expect(room.mediaMode, CallMediaMode.audio);
  });

  test('invalid media mode is rejected', () {
    expect(
      () => VoiceCallRoom.fromJson(
        callId: 'call-1',
        json: _roomJson(mediaMode: 'screen'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'fake adapter enforces role-specific offer answer and ICE writes',
    () async {
      final adapter = FakeVoiceSignalingAdapter();
      addTearDown(adapter.dispose);
      await adapter.createOutgoingCall(
        callId: 'call-1',
        caller: 'alice',
        callee: 'bob',
        createdAt: 1000,
        expiresAt: 3000,
        mediaMode: CallMediaMode.video,
      );
      await adapter.acceptCall(
        callId: 'call-1',
        callee: 'bob',
        acceptedAt: 1100,
      );

      await expectLater(
        adapter.writeVoiceOffer(
          callId: 'call-1',
          caller: 'bob',
          offer: _envelope(ciphertext: 'offer'),
          updatedAt: 1200,
        ),
        throwsA(isA<VoiceSignalingException>()),
      );

      final offerEvent = adapter.watchVoiceOffer('call-1').first;
      await adapter.writeVoiceOffer(
        callId: 'call-1',
        caller: 'alice',
        offer: _envelope(ciphertext: 'offer'),
        updatedAt: 1200,
      );
      expect((await offerEvent).ciphertext, 'offer');

      await expectLater(
        adapter.writeVoiceAnswer(
          callId: 'call-1',
          callee: 'alice',
          answer: _envelope(ciphertext: 'answer'),
          updatedAt: 1300,
        ),
        throwsA(isA<VoiceSignalingException>()),
      );

      final answerEvent = adapter.watchVoiceAnswer('call-1').first;
      await adapter.writeVoiceAnswer(
        callId: 'call-1',
        callee: 'bob',
        answer: _envelope(ciphertext: 'answer'),
        updatedAt: 1300,
      );
      expect((await answerEvent).ciphertext, 'answer');

      await expectLater(
        adapter.writeIceCandidate(
          callId: 'call-1',
          username: 'bob',
          role: VoiceCallRole.caller,
          candidate: _envelope(ciphertext: 'caller-ice'),
          createdAt: 1400,
        ),
        throwsA(isA<VoiceSignalingException>()),
      );

      final iceEvent = adapter
          .watchIceCandidates(callId: 'call-1', role: VoiceCallRole.caller)
          .first;
      final candidateId = await adapter.writeIceCandidate(
        callId: 'call-1',
        username: 'alice',
        role: VoiceCallRole.caller,
        candidate: _envelope(ciphertext: 'caller-ice'),
        createdAt: 1400,
      );

      expect(candidateId, 'ice-1');
      final candidate = await iceEvent;
      expect(candidate.role, VoiceCallRole.caller);
      expect(candidate.envelope.ciphertext, 'caller-ice');
    },
  );

  test(
    'fake adapter updates state and releases lock on terminal status',
    () async {
      final adapter = FakeVoiceSignalingAdapter();
      addTearDown(adapter.dispose);
      await adapter.createOutgoingCall(
        callId: 'call-1',
        caller: 'alice',
        callee: 'bob',
        createdAt: 1000,
        expiresAt: 3000,
        mediaMode: CallMediaMode.video,
      );
      await adapter.acceptCall(
        callId: 'call-1',
        callee: 'bob',
        acceptedAt: 1100,
      );
      await adapter.markConnected(
        callId: 'call-1',
        username: 'alice',
        connectedAt: 1500,
      );
      await adapter.setMuted(
        callId: 'call-1',
        username: 'bob',
        muted: true,
        updatedAt: 1600,
      );
      await adapter.setCameraMuted(
        callId: 'call-1',
        username: 'bob',
        cameraMuted: true,
        updatedAt: 1650,
      );

      var room = await adapter.fetchCall('call-1');
      expect(room?.status, VoiceCallSignalingStatus.connected);
      expect(room?.mediaMode, CallMediaMode.video);
      expect(room?.muted['bob'], isTrue);
      expect(room?.cameraMuted['bob'], isTrue);
      expect(adapter.activePairLocks, contains('alice:bob'));

      await adapter.endCall(
        callId: 'call-1',
        username: 'bob',
        status: VoiceCallSignalingStatus.ended,
        endedAt: 1700,
        reasonCode: 'hangup',
        reason: 'Ended.',
      );

      room = await adapter.fetchCall('call-1');
      expect(room?.status, VoiceCallSignalingStatus.ended);
      expect(room?.endedBy, 'bob');
      expect(adapter.activePairLocks, isNot(contains('alice:bob')));
      await expectLater(
        adapter.setMuted(
          callId: 'call-1',
          username: 'alice',
          muted: true,
          updatedAt: 1800,
        ),
        throwsA(isA<VoiceSignalingException>()),
      );
      await expectLater(
        adapter.setCameraMuted(
          callId: 'call-1',
          username: 'alice',
          cameraMuted: false,
          updatedAt: 1800,
        ),
        throwsA(isA<VoiceSignalingException>()),
      );
    },
  );
}

VoiceCallRoom _room({
  required String caller,
  required String callee,
  required VoiceCallSignalingStatus status,
}) {
  return VoiceCallRoom(
    v: VoiceCallRoom.version,
    callId: 'call-1',
    pairId: voiceCallPairId(caller, callee),
    caller: normalizeVoiceCallUsername(caller),
    callee: normalizeVoiceCallUsername(callee),
    status: status,
    createdAt: 1000,
    updatedAt: 1000,
    expiresAt: 2000,
  );
}

VoiceSignalingEnvelope _envelope({required String ciphertext}) {
  return VoiceSignalingEnvelope(
    v: VoiceSignalingEnvelope.version,
    alg: VoiceSignalingEnvelope.algorithmName,
    ts: 1000,
    nonce: 'nonce',
    ciphertext: ciphertext,
    mac: 'mac',
  );
}

Map<Object?, Object?> _roomJson({String mediaMode = 'audio'}) {
  return <Object?, Object?>{
    'v': VoiceCallRoom.version,
    'pairId': 'alice:bob',
    'caller': 'alice',
    'callee': 'bob',
    'status': VoiceCallSignalingStatus.ringing.name,
    'mediaMode': mediaMode,
    'createdAt': 1000,
    'updatedAt': 1000,
    'expiresAt': 2000,
  };
}
