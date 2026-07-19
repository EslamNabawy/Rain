import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  test('encrypts and decrypts room-scoped signaling payloads', () async {
    final cipher = SignalingCipher.fromKeyMaterial(
      'rain-test-signaling-key-material-32-bytes',
    );
    final payload = <String, Object?>{
      'sdp': <String, Object?>{
        'type': 'offer',
        'sdp': 'v=0\r\ncandidate:private-address',
      },
      'ts': 1778911256590,
    };

    final encrypted = await cipher.encryptPayload(
      roomId: 'alice:bob',
      purpose: SignalingCipher.offerPurpose,
      timestamp: 1778911256590,
      sender: 'alice',
      receiver: 'bob',
      payload: payload,
    );

    final envelopeJson = jsonEncode(encrypted);
    expect(encrypted['alg'], SignalingCipher.algorithmName);
    expect(encrypted['from'], 'alice');
    expect(encrypted['to'], 'bob');
    expect(encrypted, isNot(contains('sdp')));
    expect(envelopeJson, isNot(contains('private-address')));
    expect(envelopeJson, isNot(contains('candidate:')));

    final decrypted = await cipher.decryptPayload(
      roomId: 'alice:bob',
      purpose: SignalingCipher.offerPurpose,
      payload: Map<Object?, Object?>.from(encrypted),
      sender: 'alice',
      receiver: 'bob',
    );
    final sdp = Map<Object?, Object?>.from(decrypted['sdp']! as Map);

    expect(sdp['type'], 'offer');
    expect(sdp['sdp'], 'v=0\r\ncandidate:private-address');
    expect(decrypted['ts'], 1778911256590);
  });

  test('binds encrypted payloads to room and purpose', () async {
    final cipher = SignalingCipher.fromKeyMaterial(
      'rain-test-signaling-key-material-32-bytes',
    );
    final encrypted = await cipher.encryptPayload(
      roomId: 'alice:bob',
      purpose: SignalingCipher.offerPurpose,
      timestamp: 1,
      sender: 'alice',
      receiver: 'bob',
      payload: <String, Object?>{
        'sdp': <String, Object?>{'type': 'offer', 'sdp': 'v=0'},
        'ts': 1,
      },
    );

    await expectLater(
      cipher.decryptPayload(
        roomId: 'alice:bob',
        purpose: SignalingCipher.answerPurpose,
        payload: Map<Object?, Object?>.from(encrypted),
        sender: 'alice',
        receiver: 'bob',
      ),
      throwsA(isA<SignalingEncryptionException>()),
    );

    await expectLater(
      cipher.decryptPayload(
        roomId: 'alice:carol',
        purpose: SignalingCipher.offerPurpose,
        payload: Map<Object?, Object?>.from(encrypted),
        sender: 'alice',
        receiver: 'bob',
      ),
      throwsA(isA<SignalingEncryptionException>()),
    );

    await expectLater(
      cipher.decryptPayload(
        roomId: 'alice:bob',
        purpose: SignalingCipher.offerPurpose,
        payload: Map<Object?, Object?>.from(encrypted),
        sender: 'bob',
        receiver: 'alice',
      ),
      throwsA(isA<SignalingEncryptionException>()),
    );

    final tamperedContext = Map<Object?, Object?>.from(encrypted);
    tamperedContext['from'] = 'mallory';
    await expectLater(
      cipher.decryptPayload(
        roomId: 'alice:bob',
        purpose: SignalingCipher.offerPurpose,
        payload: tamperedContext,
      ),
      throwsA(isA<SignalingEncryptionException>()),
    );
  });

  test('keeps legacy plaintext signaling readable during migration', () async {
    final cipher = SignalingCipher.fromKeyMaterial(
      'rain-test-signaling-key-material-32-bytes',
    );
    final legacy = <Object?, Object?>{
      'sdp': <Object?, Object?>{'type': 'answer', 'sdp': 'v=0'},
      'ts': 2,
    };

    final decrypted = await cipher.decryptPayload(
      roomId: 'alice:bob',
      purpose: SignalingCipher.answerPurpose,
      payload: legacy,
    );

    expect(decrypted, same(legacy));
  });

  group('TASK-001 per-pair v=2 crypto core', () {
    const pairKey = 'rain-test-pair-key-material-32-bytes!!';
    final payload = <String, Object?>{
      'sdp': <String, Object?>{'type': 'offer', 'sdp': 'v=0'},
      'ts': 1778911256590,
    };

    test('encrypts and decrypts with per-pair context', () async {
      final cipher = SignalingCipher.forPair(
        pairKeyMaterial: pairKey,
        from: 'alice',
        to: 'bob',
        sessionId: 's1',
      );
      final encrypted = await cipher.encryptPayloadV2(
        roomId: 'alice:bob',
        purpose: SignalingCipher.offerPurpose,
        timestamp: 1778911256590,
        sender: 'alice',
        receiver: 'bob',
        payload: payload,
      );

      expect(encrypted['v'], SignalingCipher.envelopeVersionV2);
      expect(encrypted['alg'], SignalingCipher.algorithmName);
      expect(encrypted['from'], 'alice');
      expect(encrypted['to'], 'bob');
      expect(encrypted['salt'], isA<String>());
      expect(jsonEncode(encrypted), isNot(contains('private-address')));

      final decrypted = await cipher.decryptPayloadV2(
        roomId: 'alice:bob',
        purpose: SignalingCipher.offerPurpose,
        payload: Map<Object?, Object?>.from(encrypted),
        sender: 'alice',
        receiver: 'bob',
      );
      final sdp = Map<Object?, Object?>.from(decrypted['sdp']! as Map);
      expect(sdp['type'], 'offer');
    });

    test('different pairs derive different keys (isolation)', () async {
      final aliceBob = SignalingCipher.forPair(
        pairKeyMaterial: pairKey,
        from: 'alice',
        to: 'bob',
        sessionId: 's1',
      );
      final aliceCarol = SignalingCipher.forPair(
        pairKeyMaterial: pairKey,
        from: 'alice',
        to: 'carol',
        sessionId: 's1',
      );

      final ab = await aliceBob.encryptPayloadV2(
        roomId: 'alice:bob',
        purpose: SignalingCipher.offerPurpose,
        timestamp: 1,
        sender: 'alice',
        receiver: 'bob',
        payload: payload,
      );
      final ac = await aliceCarol.encryptPayloadV2(
        roomId: 'alice:carol',
        purpose: SignalingCipher.offerPurpose,
        timestamp: 1,
        sender: 'alice',
        receiver: 'carol',
        payload: payload,
      );

      // Same pair key material, different pair context => unlinkable ciphertext.
      expect(jsonEncode(ab), isNot(jsonEncode(ac)));

      // Alice↔Bob cipher cannot decrypt Alice↔Carol envelope.
      await expectLater(
        aliceBob.decryptPayloadV2(
          roomId: 'alice:carol',
          purpose: SignalingCipher.offerPurpose,
          payload: Map<Object?, Object?>.from(ac),
          sender: 'alice',
          receiver: 'carol',
        ),
        throwsA(isA<SignalingEncryptionException>()),
      );
    });

    test('random per-envelope salt makes repeated encrypts differ', () async {
      final cipher = SignalingCipher.forPair(
        pairKeyMaterial: pairKey,
        from: 'alice',
        to: 'bob',
        sessionId: 's1',
      );

      final first = await cipher.encryptPayloadV2(
        roomId: 'alice:bob',
        purpose: SignalingCipher.offerPurpose,
        timestamp: 1,
        sender: 'alice',
        receiver: 'bob',
        payload: payload,
      );
      final second = await cipher.encryptPayloadV2(
        roomId: 'alice:bob',
        purpose: SignalingCipher.offerPurpose,
        timestamp: 1,
        sender: 'alice',
        receiver: 'bob',
        payload: payload,
      );

      // Nonce + salt are random per envelope => ciphertexts differ.
      expect(first['salt'], isNot(second['salt']));
      expect(jsonEncode(first), isNot(jsonEncode(second)));
    });

    test('v=1 root-key holder cannot decrypt a v=2 envelope', () async {
      final pairCipher = SignalingCipher.forPair(
        pairKeyMaterial: pairKey,
        from: 'alice',
        to: 'bob',
        sessionId: 's1',
      );
      final v2 = await pairCipher.encryptPayloadV2(
        roomId: 'alice:bob',
        purpose: SignalingCipher.offerPurpose,
        timestamp: 1,
        sender: 'alice',
        receiver: 'bob',
        payload: payload,
      );

      // The app-wide v=1 signaling cipher shares no per-pair key material.
      final legacyCipher = SignalingCipher.fromKeyMaterial(
        'rain-test-signaling-key-material-32-bytes',
      );
      await expectLater(
        legacyCipher.decryptPayloadV2(
          roomId: 'alice:bob',
          purpose: SignalingCipher.offerPurpose,
          payload: Map<Object?, Object?>.from(v2),
          sender: 'alice',
          receiver: 'bob',
        ),
        throwsA(isA<SignalingEncryptionException>()),
      );
    });
  });
}
