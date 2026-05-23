import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peer_core/peer_core.dart';
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
    expect(session.state.detail, 'Call timed out.');
    expect(media.disposeCalls, 1);
  });

  test('stale sequence and wrong peer frames are ignored', () async {
    final media = _FakeVoiceMediaConnection();
    final sent = <VoiceCallFrame>[];
    final session = _session(media: media, sent: sent);

    await session.startOutgoing();
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
}

VoiceCallSession _session({
  required _FakeVoiceMediaConnection media,
  required List<VoiceCallFrame> sent,
  String localPeerId = 'alice',
  String remotePeerId = 'bob',
  VoiceCallSessionTimeouts? timeouts,
}) {
  return VoiceCallSession(
    localPeerId: localPeerId,
    remotePeerId: remotePeerId,
    callId: 'call-1',
    sessionEpoch: 11,
    media: media,
    sendFrame: sent.add,
    timeouts: timeouts ?? _timeouts(),
    clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
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
  );
}

final class _FakeVoiceMediaConnection implements VoiceMediaConnection {
  final StreamController<VoiceIceCandidate> _iceController =
      StreamController<VoiceIceCandidate>.broadcast();
  final StreamController<VoiceRemoteAudioTrack> _trackController =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaState> _stateController =
      StreamController<VoiceMediaState>.broadcast();

  int startLocalAudioCalls = 0;
  int createOfferCalls = 0;
  int disposeCalls = 0;
  final List<String> acceptedOffers = <String>[];
  final List<String> appliedAnswers = <String>[];
  final List<VoiceIceCandidate> remoteCandidates = <VoiceIceCandidate>[];

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack =>
      _trackController.stream;

  @override
  Stream<VoiceMediaState> get onStateChanged => _stateController.stream;

  @override
  Future<void> startLocalAudio() async {
    startLocalAudioCalls += 1;
  }

  @override
  Future<VoiceSessionDescription> createOffer() async {
    createOfferCalls += 1;
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
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  void emitIceCandidate(VoiceIceCandidate candidate) {
    _iceController.add(candidate);
  }

  void emitState(VoiceMediaState state) {
    _stateController.add(state);
  }
}
