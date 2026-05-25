import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart';

void main() {
  test('audio mode requests audio only and receive-video false', () async {
    final platform = _FakeCallPlatformBridge();
    final connection = _connection(platform);

    final offer = await connection.createOffer(kind: CallMediaKind.audio);

    expect(offer.type, 'offer');
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
    expect(platform.createdConnections.single.createOfferConstraints.single, {
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
      'optional': [],
    });

    await connection.dispose();
  });

  test('video mode captures camera and adds video before offer', () async {
    final platform = _FakeCallPlatformBridge();
    final connection = _connection(platform);

    await connection.createOffer(kind: CallMediaKind.video);

    expect(platform.userMediaConstraints.single, <String, dynamic>{
      'audio': <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': <String, dynamic>{
        'facingMode': 'user',
        'mandatory': <String, dynamic>{
          'minWidth': '320',
          'minHeight': '240',
          'maxWidth': '640',
          'maxHeight': '480',
          'minFrameRate': '15',
          'maxFrameRate': '30',
        },
        'optional': <dynamic>[],
      },
    });
    expect(platform.createdConnections.single.operations, <String>[
      'addTrack:audio-1',
      'addTrack:video-1',
      'createOffer',
      'setLocalDescription:offer',
    ]);
    expect(platform.createdConnections.single.createOfferConstraints.single, {
      'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
      'optional': [],
    });
    expect(connection.diagnostics.hasLocalVideo, isTrue);

    await connection.dispose();
  });

  test('video mode uses selected camera device id when available', () async {
    final platform = _FakeCallPlatformBridge()
      ..devices = <MediaDeviceInfo>[
        MediaDeviceInfo(
          deviceId: 'audio-1',
          label: 'Built-in microphone',
          kind: 'audioinput',
        ),
        MediaDeviceInfo(
          deviceId: 'front-camera',
          label: 'Front Camera',
          kind: 'videoinput',
        ),
        MediaDeviceInfo(
          deviceId: 'rear-camera',
          label: 'Back Camera',
          kind: 'videoinput',
        ),
      ];
    final connection = _connection(
      platform,
      selectedVideoInputDeviceIdProvider: () async => 'rear-camera',
    );

    await connection.createOffer(kind: CallMediaKind.video);

    expect(platform.userMediaConstraints.single['video'], <String, dynamic>{
      'deviceId': 'rear-camera',
      'mandatory': <String, dynamic>{
        'minWidth': '320',
        'minHeight': '240',
        'maxWidth': '640',
        'maxHeight': '480',
        'minFrameRate': '15',
        'maxFrameRate': '30',
      },
      'optional': <dynamic>[],
    });
    expect(
      platform.userMediaConstraints.single['video'],
      isNot(containsPair('facingMode', 'user')),
    );

    await connection.dispose();
  });

  test('camera denied fails before offer', () async {
    final platform = _FakeCallPlatformBridge()
      ..getUserMediaError = StateError('camera denied');
    final connection = _connection(platform);
    final states = <CallMediaState>[];
    connection.onStateChanged.listen(states.add);

    await expectLater(
      connection.createOffer(kind: CallMediaKind.video),
      throwsA(
        isA<CallMediaException>().having(
          (CallMediaException error) => error.reason,
          'reason',
          CallMediaFailureReason.cameraDenied,
        ),
      ),
    );
    await pumpEventQueue();

    expect(platform.createdConnections.single.operations, isEmpty);
    expect(states.last.phase, CallMediaPhase.failed);
    expect(states.last.failureReason, CallMediaFailureReason.cameraDenied);
  });

  test('missing camera track gives typed camera failure', () async {
    final platform = _FakeCallPlatformBridge()..omitVideoTrack = true;
    final connection = _connection(platform);

    await expectLater(
      connection.createOffer(kind: CallMediaKind.video),
      throwsA(
        isA<CallMediaException>().having(
          (CallMediaException error) => error.reason,
          'reason',
          CallMediaFailureReason.cameraUnavailable,
        ),
      ),
    );
  });

  test('remote video track emits event', () async {
    final platform = _FakeCallPlatformBridge();
    final connection = _connection(platform);
    final remoteTracks = <CallRemoteMediaTrack>[];
    final subscription = connection.onRemoteTrack.listen(remoteTracks.add);

    await connection.startLocalMedia(kind: CallMediaKind.video);
    platform.createdConnections.single.emitTrack(
      _FakeMediaTrack('remote-video-1', kind: 'video'),
      _FakeMediaStream('remote-stream', audioTrack: null, videoTrack: null),
    );
    await pumpEventQueue();

    expect(remoteTracks, hasLength(1));
    expect(remoteTracks.single.isVideo, isTrue);
    expect(connection.diagnostics.remoteVideoTrackCount, 1);

    await subscription.cancel();
    await connection.dispose();
  });

  test('remote candidates buffer before remote SDP', () async {
    final platform = _FakeCallPlatformBridge();
    final connection = _connection(platform);

    await connection.startLocalMedia(kind: CallMediaKind.video);
    await connection.addRemoteCandidate(
      const CallIceCandidate(
        candidate: 'candidate:1',
        sdpMid: '0',
        sdpMLineIndex: 0,
      ),
    );

    expect(platform.createdConnections.single.addedCandidates, isEmpty);

    await connection.acceptOffer(
      const CallSessionDescription(sdp: 'remote-offer-sdp', type: 'offer'),
      kind: CallMediaKind.video,
    );

    expect(platform.createdConnections.single.addedCandidates, <String>[
      'candidate:1',
    ]);

    await connection.dispose();
  });

  test('camera mute disables video track without renegotiation', () async {
    final platform = _FakeCallPlatformBridge();
    final connection = _connection(platform);

    await connection.startLocalMedia(kind: CallMediaKind.video);
    final pc = platform.createdConnections.single;
    final operationsBeforeMute = List<String>.of(pc.operations);

    await connection.setCameraMuted(muted: true);
    expect(platform.videoStream.videoTrack!.enabled, isFalse);
    expect(pc.operations, operationsBeforeMute);

    await connection.setCameraMuted(muted: false);
    expect(platform.videoStream.videoTrack!.enabled, isTrue);

    await connection.dispose();
  });

  test('mic mute uses platform helper', () async {
    final platform = _FakeCallPlatformBridge();
    final connection = _connection(platform);

    await connection.startLocalMedia(kind: CallMediaKind.video);
    await connection.setMicrophoneMuted(muted: true);

    expect(platform.microphoneMuteCalls, <bool>[true]);
    expect(platform.videoStream.audioTrack!.enabled, isFalse);

    await connection.dispose();
  });

  test('switch camera calls platform bridge', () async {
    final platform = _FakeCallPlatformBridge();
    final connection = _connection(platform);

    await connection.startLocalMedia(kind: CallMediaKind.video);
    await connection.switchCamera();

    expect(platform.switchCameraTrackIds, <String?>['video-1']);

    await connection.dispose();
  });

  test('switch camera failure leaves active local media intact', () async {
    final platform = _FakeCallPlatformBridge()
      ..switchCameraError = StateError('camera switch unavailable');
    final connection = _connection(platform);

    await connection.startLocalMedia(kind: CallMediaKind.video);

    await expectLater(connection.switchCamera(), throwsA(isA<StateError>()));

    expect(connection.diagnostics.hasLocalVideo, isTrue);
    expect(connection.diagnostics.disposed, isFalse);
    expect(platform.videoStream.videoTrack!.stopped, isFalse);

    await connection.dispose();
  });

  test(
    'dispose stops tracks, closes peer, and later calls use fresh PC',
    () async {
      final platform = _FakeCallPlatformBridge();
      final first = _connection(platform);

      await first.startLocalMedia(kind: CallMediaKind.video);
      await first.dispose();

      expect(platform.videoStream.audioTrack!.stopped, isTrue);
      expect(platform.videoStream.videoTrack!.stopped, isTrue);
      expect(platform.videoStream.disposed, isTrue);
      expect(platform.createdConnections.single.closeCalls, 1);
      expect(platform.createdConnections.single.disposeCalls, 1);

      platform.videoStream = _FakeMediaStream(
        'local-video-2',
        audioTrack: _FakeMediaTrack('audio-2'),
        videoTrack: _FakeMediaTrack('video-2', kind: 'video'),
      );
      final second = _connection(platform);
      await second.startLocalMedia(kind: CallMediaKind.video);

      expect(platform.createdConnections, hasLength(2));
      expect(platform.createdConnections.last.addedTracks, <String?>[
        'audio-2',
        'video-2',
      ]);

      await second.dispose();
    },
  );
}

DefaultCallMediaConnection _connection(
  _FakeCallPlatformBridge platform, {
  Future<String?> Function()? selectedVideoInputDeviceIdProvider,
}) {
  return DefaultCallMediaConnection(
    config: PeerConfig(
      iceServers: const <Map<String, dynamic>>[],
      platform: platform,
      selectedVideoInputDeviceIdProvider: selectedVideoInputDeviceIdProvider,
    ),
  );
}

class _FakeCallPlatformBridge implements PlatformBridge {
  final List<_FakeCallPeerConnection> createdConnections =
      <_FakeCallPeerConnection>[];
  _FakeMediaStream audioStream = _FakeMediaStream(
    'local-audio',
    audioTrack: _FakeMediaTrack('audio-1'),
    videoTrack: null,
  );
  _FakeMediaStream videoStream = _FakeMediaStream(
    'local-video',
    audioTrack: _FakeMediaTrack('audio-1'),
    videoTrack: _FakeMediaTrack('video-1', kind: 'video'),
  );
  final List<Map<String, dynamic>> userMediaConstraints =
      <Map<String, dynamic>>[];
  final List<bool> microphoneMuteCalls = <bool>[];
  final List<String?> switchCameraTrackIds = <String?>[];
  List<MediaDeviceInfo> devices = <MediaDeviceInfo>[
    MediaDeviceInfo(
      deviceId: 'audio-1',
      label: 'Built-in microphone',
      kind: 'audioinput',
    ),
  ];
  Object? getUserMediaError;
  Object? switchCameraError;
  bool omitVideoTrack = false;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> config,
  ) async {
    final connection = _FakeCallPeerConnection();
    createdConnections.add(connection);
    return connection;
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    RTCPeerConnection pc,
    String label,
    RTCDataChannelInit opts,
  ) {
    throw UnimplementedError('Call media tests do not use data channels.');
  }

  @override
  Future<void> clearVoiceAudio() async {}

  @override
  Future<List<MediaDeviceInfo>> enumerateMediaDevices() async {
    return devices;
  }

  @override
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) async {
    userMediaConstraints.add(constraints);
    final error = getUserMediaError;
    if (error != null) {
      throw error;
    }
    if (constraints['video'] == false) {
      return audioStream;
    }
    if (omitVideoTrack) {
      return _FakeMediaStream(
        'local-video-missing',
        audioTrack: _FakeMediaTrack('audio-missing-video'),
        videoTrack: null,
      );
    }
    return videoStream;
  }

  @override
  StorageBackend getLocalStorage() => MemoryStorageBackend();

  @override
  Future<void> prepareVoiceAudio() async {}

  @override
  Future<void> selectAudioInput(String deviceId) async {}

  @override
  Future<void> selectAudioOutput(String deviceId) async {}

  @override
  Future<void> setMicrophoneMuted(
    MediaStreamTrack track, {
    required bool muted,
  }) async {
    microphoneMuteCalls.add(muted);
    track.enabled = !muted;
  }

  @override
  Future<void> setSpeakerphoneOn(bool enabled) async {}

  @override
  Future<void> setSpeakerphoneOnButPreferBluetooth() async {}

  @override
  Future<void> switchCamera(MediaStreamTrack track) async {
    final error = switchCameraError;
    if (error != null) {
      throw error;
    }
    switchCameraTrackIds.add(track.id);
  }
}

class _FakeCallPeerConnection extends Fake implements RTCPeerConnection {
  final List<String?> addedTracks = <String?>[];
  final List<String> addedCandidates = <String>[];
  final List<String> operations = <String>[];
  final List<Map<String, dynamic>?> createOfferConstraints =
      <Map<String, dynamic>?>[];
  final List<Map<String, dynamic>?> createAnswerConstraints =
      <Map<String, dynamic>?>[];
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
    createOfferConstraints.add(constraints);
    return RTCSessionDescription('offer-sdp', 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async {
    operations.add('createAnswer');
    createAnswerConstraints.add(constraints);
    return RTCSessionDescription('answer-sdp', 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    operations.add('setLocalDescription:${description.type}');
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    operations.add('setRemoteDescription:${description.type}');
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
  _FakeMediaStream(this._id, {this.audioTrack, this.videoTrack});

  final String _id;
  final _FakeMediaTrack? audioTrack;
  final _FakeMediaTrack? videoTrack;
  bool disposed = false;

  @override
  String get id => _id;

  @override
  List<MediaStreamTrack> getAudioTracks() {
    final track = audioTrack;
    return track == null
        ? const <MediaStreamTrack>[]
        : <MediaStreamTrack>[track];
  }

  @override
  List<MediaStreamTrack> getVideoTracks() {
    final track = videoTrack;
    return track == null
        ? const <MediaStreamTrack>[]
        : <MediaStreamTrack>[track];
  }

  @override
  List<MediaStreamTrack> getTracks() {
    return <MediaStreamTrack>[?audioTrack, ?videoTrack];
  }

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
