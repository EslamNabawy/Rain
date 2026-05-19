import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/transport/turn_relay_probe.dart';

void main() {
  const attempt = IceAttemptDescriptor(
    stage: IceAttemptStage.primaryRelay,
    policy: PeerIceTransportPolicy.relayOnly,
    providerTier: IceProviderTier.primaryRelay,
    providerId: 'primary-relay',
    timeout: Duration(seconds: 30),
    connectAttemptId: 'probe-1',
    attemptIndex: 1,
  );

  test('forced relay probe refuses STUN-only config', () async {
    final probe = TurnRelayProbe(
      iceServersForAttempt: (_) async => const <Map<String, dynamic>>[
        <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
      ],
    );

    final result = await probe.run(peerId: 'bob', attempt: attempt);

    expect(result.succeeded, isFalse);
    expect(result.error, 'Relay credentials unavailable.');
  });

  test(
    'forced relay probe uses relay-only policy and returns provider detail',
    () async {
      PeerIceTransportPolicy? observedPolicy;
      List<Map<String, dynamic>>? observedServers;
      final probe = TurnRelayProbe(
        iceServersForAttempt: (_) async => const <Map<String, dynamic>>[
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
          <String, dynamic>{
            'urls': <String>[
              'turn:relay.example.com:3478?transport=udp',
              'turns:relay.example.com:5349?transport=tcp',
            ],
            'username': 'u',
            'credential': 'p',
          },
        ],
        configCheck:
            (
              PeerIceTransportPolicy policy,
              List<Map<String, dynamic>> iceServers,
            ) async {
              observedPolicy = policy;
              observedServers = iceServers;
            },
      );

      final result = await probe.run(peerId: 'bob', attempt: attempt);

      expect(result.succeeded, isTrue);
      expect(result.providerId, 'primary-relay');
      expect(result.stage, IceAttemptStage.primaryRelay);
      expect(result.turnUrlCount, 2);
      expect(observedPolicy, PeerIceTransportPolicy.relayOnly);
      expect(observedServers, isNotNull);
      expect(result.userMessage, 'Relay credentials ready. 2 TURN URLs.');
    },
  );

  test('forced relay probe maps provider errors to user-safe text', () async {
    final probe = TurnRelayProbe(
      iceServersForAttempt: (_) async {
        throw StateError('Relay authorization failed. Sign in again.');
      },
    );

    final result = await probe.run(peerId: 'bob', attempt: attempt);

    expect(result.succeeded, isFalse);
    expect(result.error, 'Relay authorization failed. Sign in again.');
    expect(result.userMessage, 'Relay authorization failed. Sign in again.');
  });
}
