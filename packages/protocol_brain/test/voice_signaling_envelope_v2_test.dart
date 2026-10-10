import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/src/voice_signaling_contract.dart';

Map<Object?, Object?> _json({
  int v = 2,
  Object? salt = 'AAAAAAAAAAAAAAAAAAAAAA==',
}) {
  return <Object?, Object?>{
    'v': v,
    'alg': VoiceSignalingEnvelope.algorithmName,
    'ts': 10,
    'from': 'alice',
    'to': 'bob',
    'salt': ?salt,
    'nonce': 'nonce',
    'ciphertext': 'ct',
    'mac': 'mac',
  };
}

void main() {
  const max = VoiceSignalingEnvelope.maxSdpCiphertextLength;

  test('v=2 envelope with salt round-trips', () {
    final envelope = VoiceSignalingEnvelope.fromJson(
      _json(),
      maxCiphertextLength: max,
    );

    expect(envelope.v, VoiceSignalingEnvelope.versionPerPair);
    expect(envelope.toJson(maxCiphertextLength: max)['salt'], isNotNull);
  });

  test('v=1 envelope has no salt and still validates', () {
    final envelope = VoiceSignalingEnvelope.fromJson(
      _json(v: 1, salt: null),
      maxCiphertextLength: max,
    );

    expect(envelope.salt, isNull);
    expect(
      envelope.toJson(maxCiphertextLength: max).containsKey('salt'),
      isFalse,
    );
  });

  test('v=2 without a salt and unknown versions are rejected', () {
    expect(
      () => VoiceSignalingEnvelope.fromJson(
        _json(salt: null),
        maxCiphertextLength: max,
      ),
      throwsFormatException,
    );
    expect(
      () => VoiceSignalingEnvelope.fromJson(
        _json(v: 3),
        maxCiphertextLength: max,
      ),
      throwsFormatException,
    );
  });
}
