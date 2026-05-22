import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

void main() {
  test('peer state machine enforces happy path transitions', () {
    final machine = PeerStateMachine();

    expect(machine.state, PeerState.idle);
    machine.transition(PeerState.ready);
    machine.transition(PeerState.offering);
    machine.transition(PeerState.connecting);
    machine.transition(PeerState.connected);
    machine.transition(PeerState.reconnecting);
    machine.transition(PeerState.failed);
    machine.transition(PeerState.idle);

    expect(machine.state, PeerState.idle);
  });

  test('peer state machine rejects invalid transitions', () {
    final machine = PeerStateMachine();

    expect(() => machine.transition(PeerState.connected), throwsStateError);

    machine.transition(PeerState.ready);
    machine.transition(PeerState.offering);
    machine.transition(PeerState.connecting);

    expect(() => machine.transition(PeerState.failed), throwsStateError);
  });

  test(
    'peer config keeps direct P2P candidates enabled before relay fallback',
    () {
      final config = PeerConfig(
        iceServers: const <Map<String, dynamic>>[
          <String, dynamic>{'urls': 'stun:stun.l.google.com:19302'},
          <String, dynamic>{
            'urls': 'turn:turn.example:3478',
            'username': 'rain',
            'credential': 'secret',
          },
        ],
        platform: _FakePlatformBridge(),
      );

      expect(config.toRtcConfiguration(), <String, Object?>{
        'iceServers': config.iceServers,
        'sdpSemantics': 'unified-plan',
        'iceTransportPolicy': 'all',
      });
    },
  );

  test('peer config can force relay-only for fallback attempts', () {
    final config = PeerConfig(
      iceServers: const <Map<String, dynamic>>[
        <String, dynamic>{
          'urls': 'turn:turn.example:3478?transport=udp',
          'username': 'rain',
          'credential': 'secret',
        },
      ],
      platform: _FakePlatformBridge(),
      iceTransportPolicy: PeerIceTransportPolicy.relayOnly,
    );

    expect(config.hasRelayServer, isTrue);
    expect(config.toRtcConfiguration()['iceTransportPolicy'], 'relay');
    expect(
      config
          .copyWith(iceTransportPolicy: PeerIceTransportPolicy.all)
          .toRtcConfiguration()['iceTransportPolicy'],
      'all',
    );
  });

  test(
    'default peer waits for chat and control channels before connected',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();
      final connectedEvents = <void>[];
      final subscription = peer.onConnected.listen(connectedEvents.add);

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));

      platform.connection.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await pumpEventQueue();

      expect(peer.state, PeerState.connecting);
      expect(connectedEvents, isEmpty);

      platform.channel(PeerChannels.chat).emitOpen();
      await pumpEventQueue();

      expect(peer.state, PeerState.connecting);
      expect(connectedEvents, isEmpty);

      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
      expect(connectedEvents, hasLength(1));

      await subscription.cancel();
    },
  );

  test('default peer rejects chat send before data channel opens', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));

    expect(
      () => peer.send(PeerChannels.chat, 'too soon'),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'default peer treats open chat and control channels as connected',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));

      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
    },
  );

  test(
    'default peer recovers from transient disconnect without a rebuild',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();
      final connectedEvents = <void>[];
      final disconnectedEvents = <void>[];
      final connectedSubscription = peer.onConnected.listen(
        connectedEvents.add,
      );
      final disconnectedSubscription = peer.onDisconnected.listen(
        disconnectedEvents.add,
      );

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));

      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      platform.connection.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
      );
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
      expect(disconnectedEvents, isEmpty);

      platform.connection.emitConnectionState(
        RTCPeerConnectionState.RTCPeerConnectionStateConnected,
      );
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
      expect(connectedEvents, hasLength(1));

      await connectedSubscription.cancel();
      await disconnectedSubscription.cancel();
    },
  );

  test(
    'default peer keeps session connected when optional channel closes',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();
      final disconnectedEvents = <void>[];
      final disconnectedSubscription = peer.onDisconnected.listen(
        disconnectedEvents.add,
      );

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      await peer.openChannel(PeerChannels.file);
      platform.channel(PeerChannels.file).emitOpen();
      await pumpEventQueue();
      await peer.closeChannel(PeerChannels.file);
      await pumpEventQueue();

      expect(peer.state, PeerState.connected);
      expect(disconnectedEvents, isEmpty);

      await disconnectedSubscription.cancel();
    },
  );

  test('default peer gives required channel closes a grace window', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    final disconnectedEvents = <void>[];
    final disconnectedSubscription = peer.onDisconnected.listen(
      disconnectedEvents.add,
    );

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
    platform.channel(PeerChannels.chat).emitOpen();
    platform.channel(PeerChannels.control).emitOpen();
    await pumpEventQueue();

    await peer.closeChannel(PeerChannels.control);
    await pumpEventQueue();

    expect(peer.state, PeerState.connected);
    expect(disconnectedEvents, isEmpty);

    await peer.destroy();
    await disconnectedSubscription.cancel();
  });

  test('default peer chunks large binary payloads on file channel', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    final receivedMessages = <PeerMessage>[];
    final subscription = peer.onMessage.listen(receivedMessages.add);
    final payload = List<int>.generate(40 * 1024, (int index) => index % 251);

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
    platform.channel(PeerChannels.chat).emitOpen();
    platform.channel(PeerChannels.control).emitOpen();
    platform.channel(PeerChannels.file).emitOpen();
    await pumpEventQueue();

    peer.send(PeerChannels.file, Uint8List.fromList(payload));
    final sentMessages = platform.channel(PeerChannels.file).sentMessages;

    expect(sentMessages.length, greaterThan(1));
    expect(
      sentMessages.map((RTCDataChannelMessage message) => message.isBinary),
      everyElement(isFalse),
    );
    for (final message in sentMessages) {
      platform.channel(PeerChannels.file).onMessage?.call(message);
    }
    await pumpEventQueue();

    expect(receivedMessages, hasLength(1));
    expect(receivedMessages.single.channelId, PeerChannels.file);
    expect(receivedMessages.single.data, Uint8List.fromList(payload));

    await subscription.cancel();
  });

  test('default peer drops malformed zero-total chunk frames', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    final receivedMessages = <PeerMessage>[];
    final subscription = peer.onMessage.listen(receivedMessages.add);

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
    platform.channel(PeerChannels.chat).emitOpen();
    platform.channel(PeerChannels.control).emitOpen();
    await pumpEventQueue();

    platform
        .channel(PeerChannels.chat)
        .onMessage
        ?.call(
          RTCDataChannelMessage(
            jsonEncode(<String, Object?>{
              'type': 'chunk',
              'id': 'bad-zero-total',
              'index': 0,
              'total': 0,
              'isBinary': false,
              'payload': base64Encode(utf8.encode('ignored')),
            }),
          ),
        );
    await pumpEventQueue();

    expect(receivedMessages, isEmpty);

    await subscription.cancel();
  });

  test(
    'default peer rejects oversized chunk totals without poisoning id',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();
      final receivedMessages = <PeerMessage>[];
      final subscription = peer.onMessage.listen(receivedMessages.add);

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      String frame({required int total, required String text}) {
        return jsonEncode(<String, Object?>{
          'type': 'chunk',
          'id': 'reused-id',
          'index': 0,
          'total': total,
          'isBinary': false,
          'payload': base64Encode(utf8.encode(text)),
        });
      }

      platform
          .channel(PeerChannels.chat)
          .onMessage
          ?.call(RTCDataChannelMessage(frame(total: 2048, text: 'poison')));
      platform
          .channel(PeerChannels.chat)
          .onMessage
          ?.call(RTCDataChannelMessage(frame(total: 1, text: 'accepted')));
      await pumpEventQueue();

      expect(receivedMessages, hasLength(1));
      expect(receivedMessages.single.data, 'accepted');

      await subscription.cancel();
    },
  );

  test('default peer maps selected host/srflx route as direct', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    platform.connection.statsReports = _routeStats(
      localType: 'host',
      remoteType: 'srflx',
    );

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    final route = await peer.currentRoute();

    expect(route.kind, PeerRouteKind.direct);
    expect(route.localCandidateType, 'host');
    expect(route.remoteCandidateType, 'srflx');
    expect(route.selectedCandidatePairId, 'pair-1');
    expect(route.protocol, 'udp');
    expect(route.rtt, 0.04);
    expect(route.bitrate, 1200000);
  });

  test('default peer reports selected route address family', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    platform.connection.statsReports = _routeStats(
      localType: 'host',
      remoteType: 'srflx',
      localAddress: '2001:db8::10',
      remoteAddress: '[2001:db8::20]:49152',
    );

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    final route = await peer.currentRoute();

    expect(route.kind, PeerRouteKind.direct);
    expect(route.localAddressFamily, PeerAddressFamily.ipv6);
    expect(route.remoteAddressFamily, PeerAddressFamily.ipv6);
    expect(route.addressFamily, PeerAddressFamily.ipv6);
  });

  test('default peer reports legacy route address family', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    platform.connection.statsReports = <StatsReport>[
      StatsReport('pair-legacy', 'googCandidatePair', 1, <String, Object?>{
        'googActiveConnection': 'true',
        'googLocalCandidateType': 'local',
        'googRemoteCandidateType': 'stun',
        'googLocalAddress': '192.0.2.10:49152',
        'googRemoteAddress': '198.51.100.20:3478',
      }),
    ];

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    final route = await peer.currentRoute();

    expect(route.kind, PeerRouteKind.direct);
    expect(route.localAddressFamily, PeerAddressFamily.ipv4);
    expect(route.remoteAddressFamily, PeerAddressFamily.ipv4);
    expect(route.addressFamily, PeerAddressFamily.ipv4);
  });

  test('default peer maps selected relay route as relay', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    platform.connection.statsReports = _routeStats(
      localType: 'relay',
      remoteType: 'prflx',
      relayProtocol: 'udp',
    );

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    final route = await peer.currentRoute();

    expect(route.kind, PeerRouteKind.relay);
    expect(route.localCandidateType, 'relay');
    expect(route.remoteCandidateType, 'prflx');
    expect(route.relayProtocol, 'udp');
  });

  test('default peer maps Android legacy candidate pair stats', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    platform.connection.statsReports = <StatsReport>[
      StatsReport('pair-legacy', 'googCandidatePair', 1, <String, Object?>{
        'googActiveConnection': 'true',
        'googLocalCandidateType': 'local',
        'googRemoteCandidateType': 'stun',
        'googRtt': '42',
        'googAvailableSendBandwidth': '900000',
      }),
    ];

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    final route = await peer.currentRoute();

    expect(route.kind, PeerRouteKind.direct);
    expect(route.localCandidateType, 'host');
    expect(route.remoteCandidateType, 'srflx');
    expect(route.selectedCandidatePairId, 'pair-legacy');
    expect(route.rtt, 0.042);
    expect(route.bitrate, 900000);
  });

  test(
    'default peer reports unknown route when no selected pair exists',
    () async {
      final platform = _FakePlatformBridge();
      final peer = DefaultPeerCore();
      platform.connection.statsReports = <StatsReport>[
        StatsReport('pair-1', 'candidate-pair', 1, <String, Object?>{
          'state': 'in-progress',
        }),
      ];

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );

      final route = await peer.currentRoute();

      expect(route.kind, PeerRouteKind.unknown);
    },
  );

  test('default peer keeps malformed route stats unknown', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    platform.connection.statsReports = <StatsReport>[
      StatsReport('pair-1', 'candidate-pair', 1, <String, Object?>{
        'selected': true,
        'localCandidateId': 'missing-local',
        'remoteCandidateId': 'missing-remote',
      }),
    ];

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    final route = await peer.currentRoute();

    expect(route.kind, PeerRouteKind.unknown);
    expect(route.localCandidateType, isNull);
    expect(route.remoteCandidateType, isNull);
  });

  test('default peer captures local audio and creates media offer', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
    platform.channel(PeerChannels.chat).emitOpen();
    platform.channel(PeerChannels.control).emitOpen();
    await pumpEventQueue();

    await peer.startLocalAudio();
    expect(platform.connection.addedTracks, isEmpty);

    final offer = await peer.createMediaOffer();

    expect(platform.prepareVoiceAudioCalls, 1);
    expect(platform.userMediaConstraints.single['video'], isFalse);
    expect(platform.connection.fakeTransceivers, isEmpty);
    expect(platform.connection.addedTracks, <String?>['audio-1']);
    expect(platform.connection.addedTrackStreamIds, <String?>['local-audio']);
    expect(offer.type, 'offer');
    expect(platform.connection.localDescriptions.last.sdp, 'offer-sdp');
  });

  test('default peer applies media offer and answer while connected', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
    platform.channel(PeerChannels.chat).emitOpen();
    platform.channel(PeerChannels.control).emitOpen();
    await pumpEventQueue();

    final answer = await peer.applyMediaOffer(
      RTCSessionDescription('media-offer-sdp', 'offer'),
    );
    await peer.applyMediaAnswer(
      RTCSessionDescription('media-answer-sdp', 'answer'),
    );

    expect(answer.type, 'answer');
    expect(platform.connection.addedTracks, <String?>['audio-1']);
    expect(platform.connection.addedTrackStreamIds, <String?>['local-audio']);
    expect(platform.connection.operations, <String>[
      'createOffer',
      'setLocalDescription:offer',
      'setRemoteDescription:answer',
      'setRemoteDescription:offer',
      'addTrack:audio-1',
      'createAnswer',
      'setLocalDescription:answer',
      'setRemoteDescription:answer',
    ]);
    expect(
      platform.connection.remoteDescriptions.map((value) => value.sdp),
      <String?>['answer-sdp', 'media-offer-sdp', 'media-answer-sdp'],
    );
  });

  test('default peer stops local audio and clears native call audio', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
    platform.channel(PeerChannels.chat).emitOpen();
    platform.channel(PeerChannels.control).emitOpen();
    await pumpEventQueue();

    await peer.startLocalAudio();
    await peer.createMediaOffer();
    await peer.stopLocalAudio();

    expect(platform.connection.fakeTransceivers, isEmpty);
    expect(platform.connection.removedSenderIds, <String>['sender-audio-1']);
    expect(
      platform.connection.addedTrackSenders.single.replacedTrackIds,
      <String?>[null],
    );
    expect(platform.audioStream.audioTrack.stopped, isTrue);
    expect(platform.audioStream.disposed, isTrue);
    expect(platform.clearVoiceAudioCalls, 1);
  });

  test(
    'default peer clears native call audio when microphone capture fails',
    () async {
      final platform = _FakePlatformBridge()
        ..getUserMediaError = StateError('Microphone permission denied');
      final peer = DefaultPeerCore();

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      await expectLater(
        peer.startLocalAudio(),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('Microphone permission denied'),
          ),
        ),
      );

      expect(platform.prepareVoiceAudioCalls, 1);
      expect(platform.clearVoiceAudioCalls, 1);
      expect(platform.userMediaConstraints, hasLength(1));
    },
  );

  test(
    'default peer aborts local audio if the peer is destroyed during capture',
    () async {
      final platform = _FakePlatformBridge()
        ..getUserMediaCompleter = Completer<MediaStream>();
      final peer = DefaultPeerCore();

      await peer.init(
        PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await peer.createOffer();
      await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
      platform.channel(PeerChannels.chat).emitOpen();
      platform.channel(PeerChannels.control).emitOpen();
      await pumpEventQueue();

      final audioStart = peer.startLocalAudio();
      await pumpEventQueue();
      await peer.destroy();
      platform.getUserMediaCompleter!.complete(platform.audioStream);

      await expectLater(
        audioStart,
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('Peer connection changed while capturing local audio'),
          ),
        ),
      );

      expect(platform.audioStream.audioTrack.stopped, isTrue);
      expect(platform.audioStream.disposed, isTrue);
      expect(platform.clearVoiceAudioCalls, greaterThanOrEqualTo(1));
    },
  );

  test('default peer mutes microphone through platform bridge', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    await peer.createOffer();
    await peer.setAnswer(RTCSessionDescription('answer-sdp', 'answer'));
    platform.channel(PeerChannels.chat).emitOpen();
    platform.channel(PeerChannels.control).emitOpen();
    await pumpEventQueue();

    await peer.startLocalAudio();
    await peer.setMicrophoneMuted(muted: true);

    expect(platform.muteCalls, <bool>[true]);
    expect(platform.audioStream.audioTrack.enabled, isFalse);
  });

  test('default peer emits remote audio track events', () async {
    final platform = _FakePlatformBridge();
    final peer = DefaultPeerCore();
    final remoteTracks = <PeerRemoteTrack>[];
    final subscription = peer.onRemoteTrack.listen(remoteTracks.add);

    await peer.init(
      PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    final remoteStream = _FakeMediaStream(
      'remote-stream',
      _FakeMediaTrack('remote-audio'),
    );
    platform.connection.onTrack?.call(
      RTCTrackEvent(
        track: remoteStream.audioTrack,
        streams: <MediaStream>[remoteStream],
      ),
    );
    await pumpEventQueue();

    expect(remoteTracks, hasLength(1));
    expect(remoteTracks.single.track.id, 'remote-audio');

    await subscription.cancel();
  });
}

List<StatsReport> _routeStats({
  required String localType,
  required String remoteType,
  String? relayProtocol,
  String? localAddress,
  String? remoteAddress,
}) {
  return <StatsReport>[
    StatsReport('transport-1', 'transport', 1, <String, Object?>{
      'selectedCandidatePairId': 'pair-1',
    }),
    StatsReport('pair-1', 'candidate-pair', 1, <String, Object?>{
      'state': 'succeeded',
      'localCandidateId': 'local-1',
      'remoteCandidateId': 'remote-1',
      'currentRoundTripTime': 0.04,
      'availableOutgoingBitrate': 1200000,
    }),
    StatsReport('local-1', 'local-candidate', 1, <String, Object?>{
      'candidateType': localType,
      'protocol': 'udp',
      ...localAddress == null
          ? const <String, Object?>{}
          : <String, Object?>{'address': localAddress},
      ...relayProtocol == null
          ? const <String, Object?>{}
          : <String, Object?>{'relayProtocol': relayProtocol},
    }),
    StatsReport('remote-1', 'remote-candidate', 1, <String, Object?>{
      'candidateType': remoteType,
      'protocol': 'udp',
      ...remoteAddress == null
          ? const <String, Object?>{}
          : <String, Object?>{'address': remoteAddress},
    }),
  ];
}

class _FakePlatformBridge implements PlatformBridge {
  final _FakeRtcPeerConnection connection = _FakeRtcPeerConnection();
  final Map<String, _FakeRtcDataChannel> channels =
      <String, _FakeRtcDataChannel>{};
  final _FakeMediaStream audioStream = _FakeMediaStream(
    'local-audio',
    _FakeMediaTrack('audio-1'),
  );
  final List<Map<String, dynamic>> userMediaConstraints =
      <Map<String, dynamic>>[];
  final List<bool> muteCalls = <bool>[];
  Object? getUserMediaError;
  Completer<MediaStream>? getUserMediaCompleter;
  int prepareVoiceAudioCalls = 0;
  int clearVoiceAudioCalls = 0;

  _FakeRtcDataChannel channel(String label) => channels[label]!;

  @override
  Future<RTCPeerConnection> createPeerConnection(Map<String, dynamic> config) {
    return Future<RTCPeerConnection>.value(connection);
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    RTCPeerConnection pc,
    String label,
    RTCDataChannelInit opts,
  ) async {
    final channel = _FakeRtcDataChannel(label);
    channels[label] = channel;
    return channel;
  }

  @override
  Future<void> clearVoiceAudio() async {
    clearVoiceAudioCalls += 1;
  }

  @override
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) async {
    userMediaConstraints.add(constraints);
    final error = getUserMediaError;
    if (error != null) {
      throw error;
    }
    final completer = getUserMediaCompleter;
    if (completer != null) {
      return completer.future;
    }
    return audioStream;
  }

  @override
  StorageBackend getLocalStorage() => MemoryStorageBackend();

  @override
  Future<void> prepareVoiceAudio() async {
    prepareVoiceAudioCalls += 1;
  }

  @override
  Future<void> setMicrophoneMuted(
    MediaStreamTrack track, {
    required bool muted,
  }) async {
    muteCalls.add(muted);
    track.enabled = !muted;
  }
}

class _FakeRtcPeerConnection extends Fake implements RTCPeerConnection {
  RTCPeerConnectionState? _connectionState =
      RTCPeerConnectionState.RTCPeerConnectionStateNew;
  List<StatsReport> statsReports = <StatsReport>[];
  final List<_FakeRtpTransceiver> fakeTransceivers = <_FakeRtpTransceiver>[];
  final List<String?> addedTracks = <String?>[];
  final List<String?> addedTrackStreamIds = <String?>[];
  final List<_FakeRtpSender> addedTrackSenders = <_FakeRtpSender>[];
  final List<String> removedSenderIds = <String>[];
  final List<String> operations = <String>[];
  final List<RTCSessionDescription> localDescriptions =
      <RTCSessionDescription>[];
  final List<RTCSessionDescription> remoteDescriptions =
      <RTCSessionDescription>[];

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCDataChannel channel)? onDataChannel;

  @override
  Function(RTCTrackEvent event)? onTrack;

  @override
  RTCPeerConnectionState? get connectionState => _connectionState;

  void emitConnectionState(RTCPeerConnectionState state) {
    _connectionState = state;
    onConnectionState?.call(state);
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    operations.add('createOffer');
    return RTCSessionDescription('offer-sdp', 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    operations.add('createAnswer');
    return RTCSessionDescription('answer-sdp', 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    operations.add('setLocalDescription:${description.type}');
    localDescriptions.add(description);
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    operations.add('setRemoteDescription:${description.type}');
    remoteDescriptions.add(description);
  }

  @override
  Future<RTCRtpTransceiver> addTransceiver({
    MediaStreamTrack? track,
    RTCRtpMediaType? kind,
    RTCRtpTransceiverInit? init,
  }) async {
    final sender = _FakeRtpSender(
      'transceiver-sender-${fakeTransceivers.length + 1}',
      track,
    );
    final transceiver = _FakeRtpTransceiver(
      'transceiver-${fakeTransceivers.length + 1}',
      sender,
      init?.direction ?? TransceiverDirection.SendRecv,
    );
    fakeTransceivers.add(transceiver);
    return transceiver;
  }

  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async {
    operations.add('addTrack:${track.id}');
    addedTracks.add(track.id);
    addedTrackStreamIds.add(stream?.id);
    final sender = _FakeRtpSender('sender-${track.id}', track);
    addedTrackSenders.add(sender);
    return sender;
  }

  @override
  Future<bool> removeTrack(RTCRtpSender sender) async {
    if (sender is _FakeRtpSender) {
      removedSenderIds.add(sender.id);
    }
    return true;
  }

  @override
  Future<List<RTCRtpTransceiver>> getTransceivers() async => fakeTransceivers;

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {}

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async {
    return statsReports;
  }

  @override
  Future<void> close() async {}
}

class _FakeRtpSender extends Fake implements RTCRtpSender {
  _FakeRtpSender(this.id, [MediaStreamTrack? track]) : _track = track;

  final String id;
  final List<String?> replacedTrackIds = <String?>[];
  final List<List<MediaStream>> streamSets = <List<MediaStream>>[];
  MediaStreamTrack? _track;

  @override
  String get senderId => id;

  @override
  MediaStreamTrack? get track => _track;

  @override
  Future<void> replaceTrack(MediaStreamTrack? track) async {
    _track = track;
    replacedTrackIds.add(track?.id);
  }

  @override
  Future<void> setStreams(List<MediaStream> streams) async {
    streamSets.add(streams);
  }
}

class _FakeRtpTransceiver extends Fake implements RTCRtpTransceiver {
  _FakeRtpTransceiver(this.transceiverId, this.sender, this._direction);

  @override
  final String transceiverId;

  @override
  final _FakeRtpSender sender;

  final List<TransceiverDirection> directionChanges = <TransceiverDirection>[];
  TransceiverDirection _direction;

  @override
  String get mid => transceiverId;

  @override
  bool get stoped => false;

  @override
  Future<TransceiverDirection?> getCurrentDirection() async => _direction;

  @override
  Future<TransceiverDirection> getDirection() async => _direction;

  @override
  Future<void> setDirection(TransceiverDirection direction) async {
    _direction = direction;
    directionChanges.add(direction);
  }
}

class _FakeRtcDataChannel extends Fake implements RTCDataChannel {
  _FakeRtcDataChannel(this._label);

  final String _label;
  RTCDataChannelState? _state = RTCDataChannelState.RTCDataChannelConnecting;
  final List<RTCDataChannelMessage> sentMessages = <RTCDataChannelMessage>[];

  @override
  Function(RTCDataChannelState state)? onDataChannelState;

  @override
  Function(RTCDataChannelMessage data)? onMessage;

  @override
  RTCDataChannelState? get state => _state;

  @override
  String? get label => _label;

  @override
  int? get id => _label.hashCode;

  @override
  int? get bufferedAmount => 0;

  @override
  int? bufferedAmountLowThreshold;

  void emitOpen() {
    _state = RTCDataChannelState.RTCDataChannelOpen;
    onDataChannelState?.call(_state!);
  }

  @override
  Future<void> send(RTCDataChannelMessage message) async {
    sentMessages.add(message);
  }

  @override
  Future<void> close() async {
    _state = RTCDataChannelState.RTCDataChannelClosed;
    onDataChannelState?.call(_state!);
  }
}

class _FakeMediaStream extends Fake implements MediaStream {
  _FakeMediaStream(this._id, this.audioTrack);

  final String _id;
  final _FakeMediaTrack audioTrack;
  bool disposed = false;

  @override
  String get id => _id;

  @override
  List<MediaStreamTrack> getAudioTracks() => <MediaStreamTrack>[audioTrack];

  @override
  List<MediaStreamTrack> getTracks() => <MediaStreamTrack>[audioTrack];

  @override
  List<MediaStreamTrack> getVideoTracks() => const <MediaStreamTrack>[];

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeMediaTrack extends Fake implements MediaStreamTrack {
  _FakeMediaTrack(this._id);

  final String _id;
  bool stopped = false;
  bool _enabled = true;

  @override
  String? get id => _id;

  @override
  String? get kind => 'audio';

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool value) {
    _enabled = value;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
