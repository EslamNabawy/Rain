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
}
