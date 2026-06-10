import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  test(
    'outgoing invite flow sends invite then canonical owner offer',
    () async {
      final media = _FakeVoiceMediaConnection();
      final sent = <VoiceCallFrame>[];
      final session = _session(
        media: media,
        sent: sent,
        localPeerId: 'alice',
        remotePeerId: 'bob',
      );

      await session.startOutgoing();

      expect(session.state.phase, VoiceCallSessionPhase.outgoingRinging);
      expect(media.startLocalAudioCalls, 1);
      expect(
        sent.map((VoiceCallFrame frame) => frame.type),
        <VoiceCallFrameType>[VoiceCallFrameType.invite],
      );
      expect(sent.single.seq, 1);
      expect(sent.single.sessionEpoch, 11);
      expect(sent.single.mediaMode, CallMediaMode.audio);

      await session.handleFrame(
        _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
      );

      expect(session.state.phase, VoiceCallSessionPhase.connectingMedia);
      expect(media.createOfferCalls, 1);
      expect(
        sent.map((VoiceCallFrame frame) => frame.type),
        <VoiceCallFrameType>[
          VoiceCallFrameType.invite,
          VoiceCallFrameType.offer,
        ],
      );
      expect(sent.last.sdpType, 'offer');
      expect(sent.last.sdp, 'local-offer');
      expect(sent.last.seq, 2);
    },
  );

  test('video call sends invite with media mode video', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      mediaMode: CallMediaMode.video,
    );

    await session.startOutgoing();

    expect(sent.single.type, VoiceCallFrameType.invite);
    expect(sent.single.mediaMode, CallMediaMode.video);
    expect(media.startLocalAudioCalls, 1);
  });

  test(
    'incoming accept flow answers remote offer and waits for media',
    () async {
      final media = _FakeVoiceMediaConnection();
      final sent = <VoiceCallFrame>[];
      final session = _session(
        media: media,
        sent: sent,
        localPeerId: 'bob',
        remotePeerId: 'alice',
      );

      await session.handleFrame(
        _frame(VoiceCallFrameType.invite, from: 'alice', to: 'bob', seq: 1),
      );
      expect(session.state.phase, VoiceCallSessionPhase.incomingRinging);

      await session.acceptIncoming();

      expect(session.state.phase, VoiceCallSessionPhase.connectingMedia);
      expect(media.startLocalAudioCalls, 1);
      expect(media.createOfferCalls, 0);
      expect(
        sent.map((VoiceCallFrame frame) => frame.type),
        <VoiceCallFrameType>[VoiceCallFrameType.accept],
      );

      await session.handleFrame(
        _frame(
          VoiceCallFrameType.offer,
          from: 'alice',
          to: 'bob',
          seq: 2,
          sdp: 'remote-offer',
          sdpType: 'offer',
        ),
      );

      expect(media.acceptedOffers, <String>['remote-offer']);
      expect(
        sent.map((VoiceCallFrame frame) => frame.type),
        <VoiceCallFrameType>[
          VoiceCallFrameType.accept,
          VoiceCallFrameType.answer,
        ],
      );
      expect(sent.last.sdpType, 'answer');
      expect(sent.last.sdp, 'local-answer');

      media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
      await pumpEventQueue();

      expect(session.state.phase, VoiceCallSessionPhase.active);
    },
  );

  test('active session forwards voice audio levels', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);
    final states = <VoiceCallSessionState>[];
    final subscription = session.onStateChanged.listen(states.add);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
    media.emitAudioLevel(
      VoiceMediaAudioLevel(
        remoteLevel: 0.72,
        localLevel: 0.08,
        updatedAt: 1234,
        source: VoiceMediaAudioLevelSource.audioLevel,
      ),
    );
    await pumpEventQueue();

    expect(session.state.phase, VoiceCallSessionPhase.active);
    expect(session.state.audioLevel.remoteLevel, 0.72);
    expect(session.state.audioLevel.localLevel, 0.08);
    expect(
      session.state.audioLevel.source,
      VoiceMediaAudioLevelSource.audioLevel,
    );
    expect(
      states.map((VoiceCallSessionState state) => state.audioLevel.remoteLevel),
      contains(0.72),
    );

    await subscription.cancel();
  });

  test(
    'active session exposes media reconnect metadata without failing',
    () async {
      final media = _FakeVoiceMediaConnection();
      final sent = <VoiceCallFrame>[];
      final session = _session(media: media, sent: sent);

      await session.startOutgoing();
      await session.handleFrame(
        _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
      );
      media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
      await pumpEventQueue();

      session.markMediaReconnecting(detail: 'Peer connection interrupted.');

      expect(session.state.phase, VoiceCallSessionPhase.active);
      expect(session.state.mediaReconnecting, isTrue);
      expect(session.state.reconnectingSince, 1000);
      expect(session.state.detail, 'Peer connection interrupted.');
      expect(media.disposeCalls, 0);
      expect(
        sent.map((VoiceCallFrame frame) => frame.type),
        isNot(contains(VoiceCallFrameType.hangup)),
      );

      session.clearMediaReconnecting();

      expect(session.state.phase, VoiceCallSessionPhase.active);
      expect(session.state.mediaReconnecting, isFalse);
      expect(session.state.reconnectingSince, isNull);
    },
  );

  test(
    'active session follows media reconnecting and connected states',
    () async {
      final media = _FakeVoiceMediaConnection();
      final sent = <VoiceCallFrame>[];
      final session = _session(media: media, sent: sent);

      await session.startOutgoing();
      await session.handleFrame(
        _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
      );
      media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
      await pumpEventQueue();

      media.emitState(
        const VoiceMediaState(
          phase: VoiceMediaPhase.reconnecting,
          detail: 'Call media reconnecting.',
        ),
      );
      await pumpEventQueue();

      expect(session.state.phase, VoiceCallSessionPhase.active);
      expect(session.state.mediaReconnecting, isTrue);
      expect(session.state.detail, 'Waiting for call media restart.');
      expect(media.disposeCalls, 0);

      media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
      await pumpEventQueue();

      expect(session.state.phase, VoiceCallSessionPhase.active);
      expect(session.state.mediaReconnecting, isFalse);
      expect(session.state.reconnectingSince, isNull);
      expect(
        sent.map((VoiceCallFrame frame) => frame.type),
        isNot(contains(VoiceCallFrameType.hangup)),
      );
    },
  );

  test(
    'offer owner sends ICE restart offer when active media disconnects',
    () async {
      final media = _FakeVoiceMediaConnection();
      final sent = <VoiceCallFrame>[];
      final session = _session(media: media, sent: sent);

      await session.startOutgoing();
      await session.handleFrame(
        _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
      );
      media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
      await pumpEventQueue();

      media.emitState(
        const VoiceMediaState(
          phase: VoiceMediaPhase.reconnecting,
          detail: 'Call media reconnecting.',
        ),
      );
      await pumpEventQueue();

      final offers = sent
          .where(
            (VoiceCallFrame frame) => frame.type == VoiceCallFrameType.offer,
          )
          .toList(growable: false);
      expect(media.createOfferIceRestartFlags, <bool>[false, true]);
      expect(offers, hasLength(2));
      expect(offers.first.mediaSeq, 1);
      expect(offers.last.mediaSeq, 2);
      expect(session.state.phase, VoiceCallSessionPhase.active);
      expect(session.state.mediaReconnecting, isTrue);
    },
  );

  test('answerer accepts ICE restart offer while active', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      localPeerId: 'bob',
      remotePeerId: 'alice',
    );

    await session.handleFrame(
      _frame(VoiceCallFrameType.invite, from: 'alice', to: 'bob', seq: 1),
    );
    await session.acceptIncoming();
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.offer,
        from: 'alice',
        to: 'bob',
        seq: 2,
        sdp: 'initial-offer',
        sdpType: 'offer',
        mediaSeq: 1,
      ),
    );
    media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
    await pumpEventQueue();

    await session.handleFrame(
      _frame(
        VoiceCallFrameType.offer,
        from: 'alice',
        to: 'bob',
        seq: 3,
        sdp: 'restart-offer',
        sdpType: 'offer',
        mediaSeq: 2,
      ),
    );

    final answers = sent
        .where(
          (VoiceCallFrame frame) => frame.type == VoiceCallFrameType.answer,
        )
        .toList(growable: false);
    expect(media.acceptedOffers, <String>['initial-offer', 'restart-offer']);
    expect(answers, hasLength(2));
    expect(answers.last.mediaSeq, 2);
    expect(session.state.phase, VoiceCallSessionPhase.active);
    expect(session.state.mediaReconnecting, isTrue);
  });

  test('active session deafen and output route are local only', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
    await pumpEventQueue();

    expect(session.state.phase, VoiceCallSessionPhase.active);
    final sentBeforeLocalControls = sent.length;

    await session.setDeafened(deafened: true);
    await session.setAudioOutputRoute(VoiceMediaOutputRoute.speaker);

    expect(media.deafenCalls, <bool>[true]);
    expect(media.outputRoutes, <VoiceMediaOutputRoute>[
      VoiceMediaOutputRoute.speaker,
    ]);
    expect(sent, hasLength(sentBeforeLocalControls));
    expect(
      sent.any((VoiceCallFrame frame) => frame.type == VoiceCallFrameType.mute),
      isFalse,
    );
  });

  test('outgoing invite send failure is signaling failure', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      sendFrame: (_) {
        throw StateError('firebase write denied');
      },
    );

    await expectLater(session.startOutgoing(), throwsStateError);

    expect(session.state.phase, VoiceCallSessionPhase.failed);
    expect(session.state.detail, 'Voice call signaling failed.');
    expect(session.state.reasonCode, 'signalingFailed');
    expect(media.startLocalAudioCalls, 1);
    expect(media.disposeCalls, 1);
    expect(sent, isEmpty);
  });

  test(
    'incoming accept send failure is not reported as microphone denial',
    () async {
      final media = _FakeVoiceMediaConnection();
      final sent = <VoiceCallFrame>[];
      final session = _session(
        media: media,
        sent: sent,
        localPeerId: 'bob',
        remotePeerId: 'alice',
        sendFrame: (VoiceCallFrame frame) {
          sent.add(frame);
          if (frame.type == VoiceCallFrameType.accept) {
            throw StateError('firebase accept denied');
          }
        },
      );

      await session.handleFrame(
        _frame(VoiceCallFrameType.invite, from: 'alice', to: 'bob', seq: 1),
      );
      await expectLater(session.acceptIncoming(), throwsStateError);

      expect(session.state.phase, VoiceCallSessionPhase.failed);
      expect(session.state.detail, 'Voice call signaling failed.');
      expect(session.state.reasonCode, 'signalingFailed');
      expect(
        sent.where(
          (VoiceCallFrame frame) =>
              frame.type == VoiceCallFrameType.reject &&
              frame.reasonCode == 'microphoneDenied',
        ),
        isEmpty,
      );
      expect(sent.first.type, VoiceCallFrameType.accept);
      expect(sent.last.type, VoiceCallFrameType.hangup);
      expect(sent.last.reasonCode, 'signalingFailed');
    },
  );

  test('video renderer preflight failure sends typed reject reason', () async {
    final media = _FakeVoiceMediaConnection()
      ..startLocalAudioError = StateError(
        'Video renderer failed while attaching local video stream.',
      );
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      localPeerId: 'bob',
      remotePeerId: 'alice',
      mediaMode: CallMediaMode.video,
    );

    await session.handleFrame(
      _frame(
        VoiceCallFrameType.invite,
        from: 'alice',
        to: 'bob',
        seq: 1,
        mediaMode: CallMediaMode.video,
      ),
    );
    await expectLater(session.acceptIncoming(), throwsStateError);

    expect(session.state.phase, VoiceCallSessionPhase.failed);
    expect(session.state.detail, 'Video could not connect. Try again.');
    expect(session.state.reasonCode, 'videoRendererFailed');
    expect(sent.single.type, VoiceCallFrameType.reject);
    expect(sent.single.reasonCode, 'videoRendererFailed');
  });

  test('reject and busy fail the outgoing call and dispose media', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.busy,
        from: 'bob',
        to: 'alice',
        seq: 1,
        reason: 'Busy.',
      ),
    );

    expect(session.state.phase, VoiceCallSessionPhase.failed);
    expect(session.state.detail, 'Peer is busy.');
    expect(media.disposeCalls, 1);
  });

  test('ringing timeout fails and cleans up media', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      timeouts: _timeouts(ringing: const Duration(milliseconds: 5)),
    );

    await session.startOutgoing();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(session.state.phase, VoiceCallSessionPhase.failed);
    expect(session.state.detail, 'Call timed out while ringing.');
    expect(media.disposeCalls, 1);
  });

  test(
    'wrong call id, stale epoch, and wrong peer frames are ignored',
    () async {
      final media = _FakeVoiceMediaConnection();
      final sent = <VoiceCallFrame>[];
      final session = _session(media: media, sent: sent);

      await session.startOutgoing();
      await session.handleFrame(
        _frame(
          VoiceCallFrameType.accept,
          from: 'bob',
          to: 'alice',
          callId: 'other-call',
          seq: 1,
        ),
      );
      await session.handleFrame(
        _frame(
          VoiceCallFrameType.accept,
          from: 'bob',
          to: 'alice',
          sessionEpoch: 10,
          seq: 1,
        ),
      );
      await session.handleFrame(
        _frame(VoiceCallFrameType.accept, from: 'mallory', to: 'alice', seq: 1),
      );
      expect(media.createOfferCalls, 0);

      await session.handleFrame(
        _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
      );
      expect(media.createOfferCalls, 1);

      await session.handleFrame(
        _frame(
          VoiceCallFrameType.answer,
          from: 'bob',
          to: 'alice',
          seq: 1,
          sdp: 'stale-answer',
          sdpType: 'answer',
        ),
      );
      expect(media.appliedAnswers, isEmpty);
    },
  );

  test(
    'stale video offer is ignored by call id, session epoch, and sequence',
    () async {
      final media = _FakeVoiceMediaConnection();
      final sent = <VoiceCallFrame>[];
      final logs = <String>[];
      final session = _session(
        media: media,
        sent: sent,
        logger: logs.add,
        localPeerId: 'bob',
        remotePeerId: 'alice',
        mediaMode: CallMediaMode.video,
      );

      await session.handleFrame(
        _frame(
          VoiceCallFrameType.invite,
          from: 'alice',
          to: 'bob',
          seq: 1,
          mediaMode: CallMediaMode.video,
        ),
      );
      await session.acceptIncoming();

      await session.handleFrame(
        _frame(
          VoiceCallFrameType.offer,
          from: 'alice',
          to: 'bob',
          callId: 'old-call',
          seq: 2,
          sdp: 'wrong-call-offer',
          sdpType: 'offer',
        ),
      );
      await session.handleFrame(
        _frame(
          VoiceCallFrameType.offer,
          from: 'alice',
          to: 'bob',
          seq: 2,
          sessionEpoch: 10,
          sdp: 'old-epoch-offer',
          sdpType: 'offer',
        ),
      );

      expect(media.acceptedOffers, isEmpty);

      await session.handleFrame(
        _frame(
          VoiceCallFrameType.offer,
          from: 'alice',
          to: 'bob',
          seq: 2,
          sdp: 'video-offer',
          sdpType: 'offer',
        ),
      );
      await session.handleFrame(
        _frame(
          VoiceCallFrameType.offer,
          from: 'alice',
          to: 'bob',
          seq: 2,
          sdp: 'duplicate-video-offer',
          sdpType: 'offer',
        ),
      );

      expect(media.acceptedOffers, <String>['video-offer']);
      expect(logs, contains('late offer frame for stale callId=old-call'));
      expect(logs, contains('late offer frame for stale sessionEpoch=10'));
      expect(logs, contains('stale offer frame seq=2'));
    },
  );

  test('camera mute frame changes remote camera state only', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      mediaMode: CallMediaMode.video,
    );

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
    await pumpEventQueue();

    await session.handleFrame(
      _frame(
        VoiceCallFrameType.mute,
        from: 'bob',
        to: 'alice',
        seq: 2,
        cameraMuted: true,
      ),
    );

    expect(session.state.isRemoteMuted, isFalse);
    expect(session.state.isRemoteCameraMuted, isTrue);

    await session.handleFrame(
      _frame(
        VoiceCallFrameType.mute,
        from: 'bob',
        to: 'alice',
        seq: 3,
        muted: true,
      ),
    );

    expect(session.state.isRemoteMuted, isTrue);
    expect(session.state.isRemoteCameraMuted, isTrue);
  });

  test('incoming reject sends reject and disposes voice media', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      localPeerId: 'bob',
      remotePeerId: 'alice',
    );

    await session.handleFrame(
      _frame(VoiceCallFrameType.invite, from: 'alice', to: 'bob', seq: 1),
    );
    await session.rejectIncoming(reason: 'No.');

    expect(session.state.phase, VoiceCallSessionPhase.idle);
    expect(session.state.detail, 'No.');
    expect(media.disposeCalls, 1);
    expect(sent.single.type, VoiceCallFrameType.reject);
    expect(sent.single.reason, 'No.');
  });

  test('hangup clears only the voice session', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.hangup,
        from: 'bob',
        to: 'alice',
        seq: 1,
        reason: 'Ended.',
      ),
    );

    expect(session.state.phase, VoiceCallSessionPhase.idle);
    expect(session.state.detail, 'Ended.');
    expect(media.disposeCalls, 1);
    expect(sent.map((VoiceCallFrame frame) => frame.type), <VoiceCallFrameType>[
      VoiceCallFrameType.invite,
    ]);
  });

  test('local ICE candidates are sent as sequenced candidate frames', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );

    media.emitIceCandidate(
      const VoiceIceCandidate(
        candidate: 'candidate:1 1 udp 1 127.0.0.1 9 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );
    await pumpEventQueue();

    expect(sent.last.type, VoiceCallFrameType.candidate);
    expect(sent.last.seq, 3);
    expect(sent.last.candidate, startsWith('candidate:1'));
    expect(sent.last.sdpMid, '0');
    expect(sent.last.sdpMLineIndex, 0);
  });

  test('remote ICE candidate is routed to media while connecting', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.candidate,
        from: 'bob',
        to: 'alice',
        seq: 2,
        candidate: 'candidate:remote 1 udp 1 127.0.0.1 9 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );

    expect(media.remoteCandidates, hasLength(1));
    expect(media.remoteCandidates.single.candidate, startsWith('candidate:'));
    expect(media.remoteCandidates.single.sdpMid, '0');
    expect(media.remoteCandidates.single.sdpMLineIndex, 0);
  });

  test('remote candidate before answer does not stale-drop answer', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.candidate,
        from: 'bob',
        to: 'alice',
        seq: 3,
        candidate: 'candidate:early 1 udp 1 127.0.0.1 9 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.answer,
        from: 'bob',
        to: 'alice',
        seq: 2,
        sdp: 'remote-answer',
        sdpType: 'answer',
      ),
    );

    expect(media.remoteCandidates, hasLength(1));
    expect(media.appliedAnswers, <String>['remote-answer']);
  });

  test('remote candidate before offer does not stale-drop offer', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      localPeerId: 'bob',
      remotePeerId: 'alice',
    );

    await session.handleFrame(
      _frame(VoiceCallFrameType.invite, from: 'alice', to: 'bob', seq: 1),
    );
    await session.acceptIncoming();
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.candidate,
        from: 'alice',
        to: 'bob',
        seq: 3,
        candidate: 'candidate:early 1 udp 1 127.0.0.1 9 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.offer,
        from: 'alice',
        to: 'bob',
        seq: 2,
        sdp: 'remote-offer',
        sdpType: 'offer',
      ),
    );

    expect(media.remoteCandidates, hasLength(1));
    expect(media.acceptedOffers, <String>['remote-offer']);
    expect(sent.last.type, VoiceCallFrameType.answer);
  });

  test('duplicate remote ICE candidate is ignored', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    final candidate = _frame(
      VoiceCallFrameType.candidate,
      from: 'bob',
      to: 'alice',
      seq: 3,
      candidate: 'candidate:duplicate 1 udp 1 127.0.0.1 9 typ host',
      sdpMid: '0',
      sdpMLineIndex: 0,
    );

    await session.handleFrame(candidate);
    await session.handleFrame(candidate);

    expect(media.remoteCandidates, hasLength(1));
  });

  test('late media frames after local hangup are ignored', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final logs = <String>[];
    final session = _session(media: media, sent: sent, logger: logs.add);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    await session.hangUp();
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.answer,
        from: 'bob',
        to: 'alice',
        seq: 2,
        sdp: 'late-answer',
        sdpType: 'answer',
      ),
    );
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.candidate,
        from: 'bob',
        to: 'alice',
        seq: 3,
        candidate: 'candidate:late 1 udp 1 127.0.0.1 9 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );

    expect(session.state.phase, VoiceCallSessionPhase.idle);
    expect(media.appliedAnswers, isEmpty);
    expect(media.remoteCandidates, isEmpty);
    expect(logs, contains('answer frame in idle'));
    expect(logs, contains('candidate frame in idle'));
  });

  test('late candidate after dispose is ignored', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final logs = <String>[];
    final session = _session(media: media, sent: sent, logger: logs.add);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    await session.dispose();
    await session.handleFrame(
      _frame(
        VoiceCallFrameType.candidate,
        from: 'bob',
        to: 'alice',
        seq: 3,
        candidate: 'candidate:late 1 udp 1 127.0.0.1 9 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );

    expect(media.remoteCandidates, isEmpty);
    expect(logs, contains('late candidate frame after dispose'));
  });

  test('failed session ignores late connected media state', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    media.emitState(
      const VoiceMediaState(
        phase: VoiceMediaPhase.failed,
        detail: 'native ice failed',
      ),
    );
    await pumpEventQueue();
    expect(session.state.phase, VoiceCallSessionPhase.failed);

    media.emitState(const VoiceMediaState(phase: VoiceMediaPhase.connected));
    await pumpEventQueue();

    expect(session.state.phase, VoiceCallSessionPhase.failed);
  });

  test('media failure attaches diagnostics to failed session state', () async {
    final media = _FakeVoiceMediaConnection()
      ..diagnosticSnapshot = const VoiceMediaDiagnostics(
        mediaStates: <String>['connecting', 'failed | native ice failed'],
        iceConnectionStates: <String>[
          'RTCIceConnectionState.RTCIceConnectionStateFailed',
        ],
        peerConnectionStates: <String>[
          'RTCPeerConnectionState.RTCPeerConnectionStateFailed',
        ],
        localCandidateCount: 1,
        remoteCandidateCount: 2,
      );
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    media.emitState(
      const VoiceMediaState(
        phase: VoiceMediaPhase.failed,
        detail: 'native ice failed',
      ),
    );
    await pumpEventQueue();

    expect(session.state.phase, VoiceCallSessionPhase.failed);
    expect(session.state.mediaDiagnostics?.localCandidateCount, 1);
    expect(session.state.mediaDiagnostics?.remoteCandidateCount, 2);
    expect(
      session.state.mediaDiagnostics?.iceConnectionStates,
      contains('RTCIceConnectionState.RTCIceConnectionStateFailed'),
    );
    expect(sent.last.type, VoiceCallFrameType.hangup);
    expect(sent.last.reasonCode, 'failed');
  });

  test('answer timeout sends failed hangup and disposes media', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(
      media: media,
      sent: sent,
      timeouts: _timeouts(answer: const Duration(milliseconds: 5)),
    );

    await session.startOutgoing();
    await session.handleFrame(
      _frame(VoiceCallFrameType.accept, from: 'bob', to: 'alice', seq: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(session.state.phase, VoiceCallSessionPhase.failed);
    expect(session.state.detail, 'Timed out waiting for voice media answer.');
    expect(media.disposeCalls, 1);
    expect(sent.last.type, VoiceCallFrameType.hangup);
    expect(sent.last.reasonCode, 'failed');
  });
}

VoiceCallSession _session({
  required _FakeVoiceMediaConnection media,
  required List<VoiceCallFrame> sent,
  String localPeerId = 'alice',
  String remotePeerId = 'bob',
  VoiceCallSessionTimeouts? timeouts,
  VoiceCallFrameSender? sendFrame,
  VoiceCallLogSink? logger,
  CallMediaMode mediaMode = CallMediaMode.audio,
}) {
  return VoiceCallSession(
    localPeerId: localPeerId,
    remotePeerId: remotePeerId,
    callId: 'call-1',
    sessionEpoch: 11,
    media: media,
    sendFrame: sendFrame ?? sent.add,
    timeouts: timeouts ?? _timeouts(),
    clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
    logger: logger,
    mediaMode: mediaMode,
  );
}

VoiceCallSessionTimeouts _timeouts({
  Duration ringing = const Duration(seconds: 30),
  Duration answer = const Duration(seconds: 30),
  Duration media = const Duration(seconds: 30),
  Duration cleanup = const Duration(milliseconds: 50),
}) {
  return VoiceCallSessionTimeouts(
    ringing: ringing,
    answer: answer,
    media: media,
    cleanup: cleanup,
  );
}

VoiceCallFrame _frame(
  VoiceCallFrameType type, {
  required String from,
  required String to,
  required int seq,
  String callId = 'call-1',
  int sessionEpoch = 11,
  String? reason,
  String? sdp,
  String? sdpType,
  int? mediaSeq,
  String? candidate,
  String? sdpMid,
  int? sdpMLineIndex,
  bool? muted,
  bool? cameraMuted,
  CallMediaMode mediaMode = CallMediaMode.audio,
}) {
  return VoiceCallFrame(
    type: type,
    callId: callId,
    from: from,
    to: to,
    sentAt: 1000,
    seq: seq,
    sessionEpoch: sessionEpoch,
    reason: reason,
    sdp: sdp,
    sdpType: sdpType,
    mediaSeq: mediaSeq,
    candidate: candidate,
    sdpMid: sdpMid,
    sdpMLineIndex: sdpMLineIndex,
    muted: muted,
    cameraMuted: cameraMuted,
    mediaMode: mediaMode,
  );
}

final class _FakeVoiceMediaConnection implements VoiceMediaConnection {
  final StreamController<VoiceIceCandidate> _iceController =
      StreamController<VoiceIceCandidate>.broadcast();
  final StreamController<VoiceRemoteAudioTrack> _trackController =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaAudioLevel> _audioLevelController =
      StreamController<VoiceMediaAudioLevel>.broadcast();
  final StreamController<VoiceMediaState> _stateController =
      StreamController<VoiceMediaState>.broadcast();

  int startLocalAudioCalls = 0;
  Object? startLocalAudioError;
  int createOfferCalls = 0;
  final List<bool> createOfferIceRestartFlags = <bool>[];
  int disposeCalls = 0;
  final List<String> acceptedOffers = <String>[];
  final List<String> appliedAnswers = <String>[];
  final List<VoiceIceCandidate> remoteCandidates = <VoiceIceCandidate>[];
  final List<bool> deafenCalls = <bool>[];
  final List<VoiceMediaOutputRoute> outputRoutes = <VoiceMediaOutputRoute>[];
  VoiceMediaDiagnostics diagnosticSnapshot = const VoiceMediaDiagnostics();

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack =>
      _trackController.stream;

  @override
  Stream<VoiceMediaAudioLevel> get onAudioLevelChanged =>
      _audioLevelController.stream;

  @override
  Stream<VoiceMediaState> get onStateChanged => _stateController.stream;

  @override
  VoiceMediaDiagnostics get diagnostics => diagnosticSnapshot;

  @override
  Future<void> startLocalAudio() async {
    startLocalAudioCalls += 1;
    final error = startLocalAudioError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<VoiceSessionDescription> createOffer({bool iceRestart = false}) async {
    createOfferCalls += 1;
    createOfferIceRestartFlags.add(iceRestart);
    return const VoiceSessionDescription(sdp: 'local-offer', type: 'offer');
  }

  @override
  Future<VoiceSessionDescription> acceptOffer(
    VoiceSessionDescription offer,
  ) async {
    acceptedOffers.add(offer.sdp);
    return const VoiceSessionDescription(sdp: 'local-answer', type: 'answer');
  }

  @override
  Future<void> applyAnswer(VoiceSessionDescription answer) async {
    appliedAnswers.add(answer.sdp);
  }

  @override
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> setMuted({required bool muted}) async {}

  @override
  Future<void> setDeafened({required bool deafened}) async {
    deafenCalls.add(deafened);
  }

  @override
  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route) async {
    outputRoutes.add(route);
  }

  @override
  Future<void> selectAudioOutputDevice(String deviceId) async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  void emitIceCandidate(VoiceIceCandidate candidate) {
    _iceController.add(candidate);
  }

  void emitState(VoiceMediaState state) {
    _stateController.add(state);
  }

  void emitAudioLevel(VoiceMediaAudioLevel level) {
    _audioLevelController.add(level);
  }
}
