import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

void main() {
  test(
    'dedicated voice media captures microphone and attaches audio track',
    () async {
      final platform = _FakeVoicePlatformBridge();
      final connection = DefaultVoiceMediaConnection(
        config: PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      final states = <VoiceMediaPhase>[];
      final subscription = connection.onStateChanged.listen(
        (VoiceMediaState state) => states.add(state.phase),
      );

      await connection.startLocalAudio();
      await pumpEventQueue();

      expect(platform.createdConnections, hasLength(1));
      expect(platform.prepareVoiceAudioCalls, 1);
      expect(platform.userMediaConstraints.single, <String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      expect(platform.createdConnections.single.addedTracks, <String?>[
        'audio-1',
      ]);
      expect(platform.createdConnections.single.addedTrackStreamIds, <String?>[
        'local-audio',
      ]);
      expect(
        states,
        containsAllInOrder(<VoiceMediaPhase>[
          VoiceMediaPhase.startingLocalAudio,
          VoiceMediaPhase.localAudioReady,
        ]),
      );

      await subscription.cancel();
      await connection.dispose();
    },
  );

  test(
    'dedicated voice media cleans up when microphone capture fails',
    () async {
      final platform = _FakeVoicePlatformBridge()
        ..getUserMediaError = StateError('mic denied');
      final connection = DefaultVoiceMediaConnection(
        config: PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      final states = <VoiceMediaPhase>[];
      connection.onStateChanged.listen(
        (VoiceMediaState state) => states.add(state.phase),
      );

      await expectLater(connection.startLocalAudio(), throwsStateError);
      await pumpEventQueue();

      expect(platform.prepareVoiceAudioCalls, 1);
      expect(platform.clearVoiceAudioCalls, 1);
      expect(platform.audioStream.disposed, isFalse);
      expect(platform.createdConnections.single.closeCalls, 1);
      expect(platform.createdConnections.single.disposeCalls, 1);
      expect(states, contains(VoiceMediaPhase.failed));
    },
  );

  test('dedicated voice media creates offer after local audio track', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    await connection.startLocalAudio();
    final offer = await connection.createOffer();

    expect(offer.type, 'offer');
    expect(offer.sdp, 'offer-sdp');
    expect(platform.createdConnections.single.operations, <String>[
      'addTrack:audio-1',
      'createOffer',
      'setLocalDescription:offer',
    ]);

    await connection.dispose();
  });

  test('dedicated voice media accepts offer and creates answer', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    await connection.startLocalAudio();
    final answer = await connection.acceptOffer(
      const VoiceSessionDescription(sdp: 'remote-offer-sdp', type: 'offer'),
    );

    expect(answer.type, 'answer');
    expect(answer.sdp, 'answer-sdp');
    expect(
      platform.createdConnections.single.remoteDescriptions.single.type,
      'offer',
    );
    expect(
      platform.createdConnections.single.localDescriptions.single.type,
      'answer',
    );
  });

  test('dedicated voice media buffers candidates before remote SDP', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    await connection.startLocalAudio();
    await connection.addRemoteCandidate(
      const VoiceIceCandidate(
        candidate: 'candidate:1',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );

    expect(platform.createdConnections.single.addedCandidates, isEmpty);

    await connection.acceptOffer(
      const VoiceSessionDescription(sdp: 'remote-offer-sdp', type: 'offer'),
    );

    expect(platform.createdConnections.single.addedCandidates, <String>[
      'candidate:1',
    ]);
  });

  test('dedicated voice media emits ICE and remote audio events', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    final candidates = <VoiceIceCandidate>[];
    final remoteTracks = <VoiceRemoteAudioTrack>[];
    final candidateSubscription = connection.onIceCandidate.listen(
      candidates.add,
    );
    final trackSubscription = connection.onRemoteAudioTrack.listen(
      remoteTracks.add,
    );

    await connection.startLocalAudio();
    platform.createdConnections.single.emitIceCandidate(
      RTCIceCandidate('candidate:local', '0', 0),
    );
    platform.createdConnections.single.emitTrack(
      _FakeMediaTrack('video-1', kind: 'video'),
      platform.audioStream,
    );
    platform.createdConnections.single.emitTrack(
      _FakeMediaTrack('remote-audio-1'),
      platform.audioStream,
    );
    await pumpEventQueue();

    expect(candidates.single.candidate, 'candidate:local');
    expect(remoteTracks, hasLength(1));
    expect(remoteTracks.single.track.id, 'remote-audio-1');

    await candidateSubscription.cancel();
    await trackSubscription.cancel();
    await connection.dispose();
  });

  test('dedicated voice media retains remote audio until dispose', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );
    final remoteTracks = <VoiceRemoteAudioTrack>[];
    final trackSubscription = connection.onRemoteAudioTrack.listen(
      remoteTracks.add,
    );
    final remoteStream = _FakeMediaStream(
      'remote-stream',
      _FakeMediaTrack('remote-audio-1'),
    );

    await connection.startLocalAudio();
    platform.createdConnections.single.emitTrack(
      remoteStream.audioTrack,
      remoteStream,
    );
    platform.createdConnections.single.emitTrack(
      remoteStream.audioTrack,
      remoteStream,
    );
    await pumpEventQueue();

    expect(remoteTracks, hasLength(2));
    expect(connection.diagnostics.remoteAudioTrackCount, 1);
    expect(connection.diagnostics.remoteStreamCount, 1);
    expect(remoteStream.audioTrack.stopped, isFalse);
    expect(remoteStream.disposed, isFalse);

    await trackSubscription.cancel();
    await connection.dispose();

    expect(remoteStream.audioTrack.stopped, isTrue);
    expect(remoteStream.disposed, isTrue);
    expect(connection.diagnostics.remoteAudioTrackCount, 0);
    expect(connection.diagnostics.remoteStreamCount, 0);
  });

  test('dedicated voice media diagnostics capture failure context', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    await connection.startLocalAudio();
    await connection.addRemoteCandidate(
      const VoiceIceCandidate(
        candidate: 'candidate:remote',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );
    platform.createdConnections.single.emitIceCandidate(
      RTCIceCandidate('candidate:local', '0', 0),
    );
    platform.createdConnections.single.onIceConnectionState?.call(
      RTCIceConnectionState.RTCIceConnectionStateChecking,
    );
    platform.createdConnections.single.onIceConnectionState?.call(
      RTCIceConnectionState.RTCIceConnectionStateFailed,
    );
    platform.createdConnections.single.onConnectionState?.call(
      RTCPeerConnectionState.RTCPeerConnectionStateFailed,
    );
    await pumpEventQueue();

    final diagnostics = connection.diagnostics;
    expect(diagnostics.localCandidateCount, 1);
    expect(diagnostics.remoteCandidateCount, 1);
    expect(diagnostics.pendingRemoteCandidateCount, 1);
    expect(diagnostics.mediaStates, contains('startingLocalAudio'));
    expect(diagnostics.mediaStates, contains('localAudioReady'));
    expect(
      diagnostics.iceConnectionStates,
      contains('RTCIceConnectionState.RTCIceConnectionStateFailed'),
    );
    expect(
      diagnostics.peerConnectionStates,
      contains('RTCPeerConnectionState.RTCPeerConnectionStateFailed'),
    );
    expect(diagnostics.hasLocalAudio, isTrue);
    expect(diagnostics.peerConnectionClosed, isFalse);

    await connection.dispose();
  });

  test('dedicated voice media mutes without stopping local track', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    await connection.startLocalAudio();
    await connection.setMuted(muted: true);

    expect(platform.muteCalls, <bool>[true]);
    expect(platform.audioStream.audioTrack.enabled, isFalse);
    expect(platform.audioStream.audioTrack.stopped, isFalse);

    await connection.dispose();
  });

  test('dedicated voice media dispose is idempotent', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    await connection.startLocalAudio();
    await connection.dispose();
    await connection.dispose();

    expect(platform.audioStream.audioTrack.stopped, isTrue);
    expect(platform.audioStream.disposed, isTrue);
    expect(platform.clearVoiceAudioCalls, 1);
    expect(platform.createdConnections.single.closeCalls, 1);
    expect(platform.createdConnections.single.disposeCalls, 1);
  });

  test(
    'dedicated voice media ignores late native callbacks after dispose',
    () async {
      final platform = _FakeVoicePlatformBridge();
      final connection = DefaultVoiceMediaConnection(
        config: PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      final states = <VoiceMediaPhase>[];
      final subscription = connection.onStateChanged.listen(
        (VoiceMediaState state) => states.add(state.phase),
      );

      await connection.startLocalAudio();
      final peerConnection = platform.createdConnections.single;
      final iceCallback = peerConnection.onIceConnectionState;
      final connectionCallback = peerConnection.onConnectionState;
      await connection.dispose();
      iceCallback?.call(RTCIceConnectionState.RTCIceConnectionStateClosed);
      connectionCallback?.call(
        RTCPeerConnectionState.RTCPeerConnectionStateClosed,
      );
      await pumpEventQueue();

      expect(states, isNot(contains(VoiceMediaPhase.failed)));
      expect(states, contains(VoiceMediaPhase.disposed));
      expect(connection.diagnostics.disposed, isTrue);

      await subscription.cancel();
    },
  );

  test(
    'dedicated voice media releases pending capture when disposed mid-start',
    () async {
      final platform = _FakeVoicePlatformBridge()
        ..getUserMediaCompleter = Completer<MediaStream>();
      final connection = DefaultVoiceMediaConnection(
        config: PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      final states = <VoiceMediaPhase>[];
      connection.onStateChanged.listen(
        (VoiceMediaState state) => states.add(state.phase),
      );

      final audioStart = connection.startLocalAudio();
      await pumpEventQueue();
      await connection.dispose();
      platform.getUserMediaCompleter!.complete(platform.audioStream);

      await expectLater(audioStart, throwsStateError);
      expect(platform.audioStream.audioTrack.stopped, isTrue);
      expect(platform.audioStream.disposed, isTrue);
      expect(platform.clearVoiceAudioCalls, 1);
      expect(states, isNot(contains(VoiceMediaPhase.failed)));
    },
  );

  test('dedicated voice media allows only one negotiation at a time', () async {
    final platform = _FakeVoicePlatformBridge();
    final connection = DefaultVoiceMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    await connection.startLocalAudio();
    final peerConnection = platform.createdConnections.single
      ..createOfferCompleter = Completer<RTCSessionDescription>();
    final createOffer = connection.createOffer();
    await pumpEventQueue();

    await expectLater(
      connection.applyAnswer(
        const VoiceSessionDescription(sdp: 'answer-sdp', type: 'answer'),
      ),
      throwsStateError,
    );

    peerConnection.createOfferCompleter!.complete(
      RTCSessionDescription('offer-sdp', 'offer'),
    );
    await expectLater(createOffer, completes);
    await connection.dispose();
  });

  test(
    'dedicated voice media repeated calls create new peer connections',
    () async {
      final platform = _FakeVoicePlatformBridge();

      final first = DefaultVoiceMediaConnection(
        config: PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await first.startLocalAudio();
      await first.dispose();

      final second = DefaultVoiceMediaConnection(
        config: PeerConfig(
          iceServers: const <Map<String, dynamic>>[],
          platform: platform,
        ),
      );
      await second.startLocalAudio();

      expect(platform.createdConnections, hasLength(2));
      expect(
        platform.createdConnections.first,
        isNot(same(platform.createdConnections.last)),
      );

      await second.dispose();
    },
  );
}

class _FakeVoicePlatformBridge implements PlatformBridge {
  final List<_FakeVoicePeerConnection> createdConnections =
      <_FakeVoicePeerConnection>[];
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

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> config,
  ) async {
    final connection = _FakeVoicePeerConnection();
    createdConnections.add(connection);
    return connection;
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    RTCPeerConnection pc,
    String label,
    RTCDataChannelInit opts,
  ) {
    throw UnimplementedError('Voice media tests do not use data channels.');
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

class _FakeVoicePeerConnection extends Fake implements RTCPeerConnection {
  final List<String?> addedTracks = <String?>[];
  final List<String?> addedTrackStreamIds = <String?>[];
  final List<String> addedCandidates = <String>[];
  final List<String> operations = <String>[];
  final List<RTCSessionDescription> localDescriptions =
      <RTCSessionDescription>[];
  final List<RTCSessionDescription> remoteDescriptions =
      <RTCSessionDescription>[];
  Completer<RTCSessionDescription>? createOfferCompleter;
  int closeCalls = 0;
  int disposeCalls = 0;

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Function(RTCIceConnectionState state)? onIceConnectionState;

  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCTrackEvent event)? onTrack;

  @override
  RTCPeerConnectionState? get connectionState =>
      RTCPeerConnectionState.RTCPeerConnectionStateNew;

  void emitIceCandidate(RTCIceCandidate candidate) {
    onIceCandidate?.call(candidate);
  }

  void emitTrack(MediaStreamTrack track, MediaStream stream) {
    onTrack?.call(RTCTrackEvent(streams: <MediaStream>[stream], track: track));
  }

  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async {
    operations.add('addTrack:${track.id}');
    addedTracks.add(track.id);
    addedTrackStreamIds.add(stream?.id);
    return _FakeRtpSender('sender-${track.id}', track);
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    addedCandidates.add(candidate.candidate ?? '');
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    operations.add('createOffer');
    final completer = createOfferCompleter;
    if (completer != null) {
      return completer.future;
    }
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
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

class _FakeRtpSender extends Fake implements RTCRtpSender {
  _FakeRtpSender(this.id, this._track);

  final String id;
  MediaStreamTrack? _track;

  @override
  String get senderId => id;

  @override
  MediaStreamTrack? get track => _track;

  @override
  Future<void> replaceTrack(MediaStreamTrack? track) async {
    _track = track;
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
  _FakeMediaTrack(this._id, {String kind = 'audio'}) : _kind = kind;

  final String _id;
  final String _kind;
  bool stopped = false;
  bool _enabled = true;

  @override
  String? get id => _id;

  @override
  String? get kind => _kind;

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
