import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models.dart';
import 'call_media_models.dart';

const Map<String, dynamic> _audioSdpConstraints = <String, dynamic>{
  'mandatory': <String, dynamic>{
    'OfferToReceiveAudio': true,
    'OfferToReceiveVideo': false,
  },
  'optional': <dynamic>[],
};

const Map<String, dynamic> _videoSdpConstraints = <String, dynamic>{
  'mandatory': <String, dynamic>{
    'OfferToReceiveAudio': true,
    'OfferToReceiveVideo': true,
  },
  'optional': <dynamic>[],
};

abstract class CallMediaConnection {
  Stream<CallIceCandidate> get onIceCandidate;
  Stream<CallRemoteMediaTrack> get onRemoteTrack;
  Stream<CallMediaState> get onStateChanged;
  CallMediaDiagnostics get diagnostics;
  MediaStream? get localStream;
  MediaStreamTrack? get localVideoTrack;

  Future<void> startLocalMedia({required CallMediaKind kind});
  Future<CallSessionDescription> createOffer({required CallMediaKind kind});
  Future<CallSessionDescription> acceptOffer(
    CallSessionDescription offer, {
    required CallMediaKind kind,
  });
  Future<void> applyAnswer(CallSessionDescription answer);
  Future<void> addRemoteCandidate(CallIceCandidate candidate);
  Future<void> setMicrophoneMuted({required bool muted});
  Future<void> setCameraMuted({required bool muted});
  Future<void> switchCamera();
  Future<void> setDeafened({required bool deafened});
  Future<void> setAudioOutputRoute(CallMediaOutputRoute route);
  Future<void> dispose();
}

class DefaultCallMediaConnection implements CallMediaConnection {
  DefaultCallMediaConnection({required PeerConfig config}) : _config = config;

  final PeerConfig _config;
  final StreamController<CallIceCandidate> _iceController =
      StreamController<CallIceCandidate>.broadcast();
  final StreamController<CallRemoteMediaTrack> _remoteTrackController =
      StreamController<CallRemoteMediaTrack>.broadcast();
  final StreamController<CallMediaState> _stateController =
      StreamController<CallMediaState>.broadcast();
  final List<CallIceCandidate> _pendingRemoteCandidates = <CallIceCandidate>[];
  final List<String> _mediaStates = <String>[];
  final List<String> _iceConnectionStates = <String>[];
  final List<String> _peerConnectionStates = <String>[];
  final List<MediaStreamTrack> _remoteAudioTracks = <MediaStreamTrack>[];
  final List<MediaStreamTrack> _remoteVideoTracks = <MediaStreamTrack>[];
  final List<MediaStream> _remoteStreams = <MediaStream>[];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStreamTrack? _localAudioTrack;
  MediaStreamTrack? _localVideoTrack;
  Future<void>? _localMediaStartFuture;
  Future<void>? _mediaOperation;
  int _localCandidateCount = 0;
  int _remoteCandidateCount = 0;
  int _connectionEpoch = 0;
  String? _lastDetail;
  String? _lastError;
  CallMediaFailureReason? _lastFailureReason;
  CallMediaPhase _lastPhase = CallMediaPhase.idle;
  bool _remoteDescriptionSet = false;
  bool _peerConnectionClosed = false;
  bool _voiceAudioPrepared = false;
  bool _microphoneMuted = false;
  bool _cameraMuted = false;
  bool _deafened = false;
  bool _disposed = false;
  bool _controllersClosed = false;

  @override
  Stream<CallIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<CallRemoteMediaTrack> get onRemoteTrack =>
      _remoteTrackController.stream;

  @override
  Stream<CallMediaState> get onStateChanged => _stateController.stream;

  @override
  MediaStream? get localStream => _localStream;

  @override
  MediaStreamTrack? get localVideoTrack => _localVideoTrack;

  @override
  CallMediaDiagnostics get diagnostics {
    return CallMediaDiagnostics(
      mediaStates: List<String>.unmodifiable(_mediaStates),
      iceConnectionStates: List<String>.unmodifiable(_iceConnectionStates),
      peerConnectionStates: List<String>.unmodifiable(_peerConnectionStates),
      localCandidateCount: _localCandidateCount,
      remoteCandidateCount: _remoteCandidateCount,
      pendingRemoteCandidateCount: _pendingRemoteCandidates.length,
      remoteAudioTrackCount: _remoteAudioTracks.length,
      remoteVideoTrackCount: _remoteVideoTracks.length,
      remoteStreamCount: _remoteStreams.length,
      hasLocalAudio: _localAudioTrack != null,
      hasLocalVideo: _localVideoTrack != null,
      peerConnectionClosed: _peerConnectionClosed,
      disposed: _disposed,
      lastDetail: _lastDetail,
      lastError: _lastError,
      lastFailureReason: _lastFailureReason,
    );
  }

  @override
  Future<void> startLocalMedia({required CallMediaKind kind}) async {
    _ensureNotDisposed();
    if (_hasLocalMediaFor(kind)) {
      return;
    }
    final existingStart = _localMediaStartFuture;
    if (existingStart != null) {
      await existingStart;
      if (_hasLocalMediaFor(kind)) {
        return;
      }
    }

    final startFuture = _startLocalMedia(kind);
    _localMediaStartFuture = startFuture;
    try {
      await startFuture;
    } finally {
      if (!_hasLocalMediaFor(kind)) {
        _localMediaStartFuture = null;
      }
    }
  }

  Future<void> _startLocalMedia(CallMediaKind kind) async {
    final connection = await _ensurePeerConnection();
    final epoch = _connectionEpoch;
    MediaStream? pendingStream;
    var keepVoiceAudio = false;
    try {
      _emitState(CallMediaPhase.startingLocalMedia);
      await _prepareVoiceAudio();
      _ensureCurrentPeerConnection(connection, epoch, 'preparing local media');
      final selectedAudioInputDeviceId = await _selectedAudioInputDeviceId();
      _ensureCurrentPeerConnection(
        connection,
        epoch,
        'selecting local audio input',
      );
      final selectedVideoInputDeviceId = kind == CallMediaKind.video
          ? await _selectedVideoInputDeviceId()
          : null;
      _ensureCurrentPeerConnection(
        connection,
        epoch,
        'selecting local video input',
      );
      final stream = await _captureLocalMedia(
        kind,
        selectedAudioInputDeviceId,
        selectedVideoInputDeviceId,
      );
      pendingStream = stream;
      _ensureCurrentPeerConnection(connection, epoch, 'capturing local media');
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isEmpty) {
        throw const CallMediaException(
          CallMediaFailureReason.microphoneDenied,
          'No microphone audio track was captured.',
        );
      }
      final videoTracks = stream.getVideoTracks();
      if (kind == CallMediaKind.video && videoTracks.isEmpty) {
        throw const CallMediaException(
          CallMediaFailureReason.cameraUnavailable,
          'No camera video track was captured.',
        );
      }

      final audioTrack = audioTracks.first;
      await connection.addTrack(audioTrack, stream);
      _ensureCurrentPeerConnection(connection, epoch, 'attaching local audio');
      final videoTrack = kind == CallMediaKind.video ? videoTracks.first : null;
      if (videoTrack != null) {
        await connection.addTrack(videoTrack, stream);
        _ensureCurrentPeerConnection(
          connection,
          epoch,
          'attaching local video',
        );
      }
      _localStream = stream;
      _localAudioTrack = audioTrack;
      _localVideoTrack = videoTrack;
      pendingStream = null;
      keepVoiceAudio = true;
      if (_microphoneMuted) {
        await _config.platform.setMicrophoneMuted(audioTrack, muted: true);
      }
      if (_cameraMuted && videoTrack != null) {
        videoTrack.enabled = false;
      }
      _emitState(CallMediaPhase.localMediaReady);
    } catch (error) {
      if (pendingStream != null) {
        await _disposeMediaStream(pendingStream);
      }
      if (!keepVoiceAudio) {
        _localStream = null;
        _localAudioTrack = null;
        _localVideoTrack = null;
        await _clearVoiceAudioIfPrepared();
      }
      await _closePeerConnection();
      if (!_disposed) {
        _emitFailed(error, fallback: CallMediaFailureReason.mediaCaptureFailed);
      }
      rethrow;
    }
  }

  Future<MediaStream> _captureLocalMedia(
    CallMediaKind kind,
    String? selectedAudioInputDeviceId,
    String? selectedVideoInputDeviceId,
  ) async {
    try {
      return await _config.platform.getUserMedia(
        _localMediaConstraints(
          kind,
          audioDeviceId: selectedAudioInputDeviceId,
          videoDeviceId: selectedVideoInputDeviceId,
        ),
      );
    } catch (error) {
      if (error is CallMediaException) {
        rethrow;
      }
      throw CallMediaException(
        kind == CallMediaKind.video
            ? CallMediaFailureReason.cameraDenied
            : CallMediaFailureReason.microphoneDenied,
        kind == CallMediaKind.video
            ? 'Camera permission is required.'
            : 'Microphone permission is required.',
        error,
      );
    }
  }

  @override
  Future<CallSessionDescription> createOffer({
    required CallMediaKind kind,
  }) async {
    return _runMediaOperation<CallSessionDescription>('create offer', () async {
      await startLocalMedia(kind: kind);
      final connection = await _ensurePeerConnection();
      final epoch = _connectionEpoch;
      _emitState(CallMediaPhase.creatingOffer);
      final offer = await connection.createOffer(_sdpConstraints(kind));
      _ensureCurrentPeerConnection(connection, epoch, 'creating offer');
      await connection.setLocalDescription(offer);
      _ensureCurrentPeerConnection(connection, epoch, 'setting local offer');
      _emitState(CallMediaPhase.connecting);
      return CallSessionDescription.fromRtc(offer);
    });
  }

  @override
  Future<CallSessionDescription> acceptOffer(
    CallSessionDescription offer, {
    required CallMediaKind kind,
  }) async {
    return _runMediaOperation<CallSessionDescription>('accept offer', () async {
      await startLocalMedia(kind: kind);
      final connection = await _ensurePeerConnection();
      final epoch = _connectionEpoch;
      _emitState(CallMediaPhase.applyingOffer);
      await connection.setRemoteDescription(offer.toRtc());
      _ensureCurrentPeerConnection(connection, epoch, 'applying offer');
      _remoteDescriptionSet = true;
      await _flushRemoteCandidates(connection: connection, epoch: epoch);
      final answer = await connection.createAnswer(_sdpConstraints(kind));
      _ensureCurrentPeerConnection(connection, epoch, 'creating answer');
      await connection.setLocalDescription(answer);
      _ensureCurrentPeerConnection(connection, epoch, 'setting local answer');
      _emitState(CallMediaPhase.connecting);
      return CallSessionDescription.fromRtc(answer);
    });
  }

  @override
  Future<void> applyAnswer(CallSessionDescription answer) async {
    await _runMediaOperation<void>('apply answer', () async {
      final connection = await _ensurePeerConnection();
      final epoch = _connectionEpoch;
      _emitState(CallMediaPhase.applyingAnswer);
      await connection.setRemoteDescription(answer.toRtc());
      _ensureCurrentPeerConnection(connection, epoch, 'applying answer');
      _remoteDescriptionSet = true;
      await _flushRemoteCandidates(connection: connection, epoch: epoch);
      _emitState(CallMediaPhase.connecting);
    });
  }

  @override
  Future<void> addRemoteCandidate(CallIceCandidate candidate) async {
    _ensureNotDisposed();
    if (_peerConnectionClosed) {
      throw StateError('Call media peer connection has already been closed.');
    }
    _remoteCandidateCount += 1;
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    final connection = await _ensurePeerConnection();
    final epoch = _connectionEpoch;
    await connection.addCandidate(candidate.toRtc());
    _ensureCurrentPeerConnection(connection, epoch, 'adding remote candidate');
  }

  @override
  Future<void> setMicrophoneMuted({required bool muted}) async {
    _ensureNotDisposed();
    final track = _localAudioTrack;
    if (track == null) {
      throw StateError('Local audio has not been started.');
    }
    _microphoneMuted = muted;
    await _config.platform.setMicrophoneMuted(track, muted: muted);
  }

  @override
  Future<void> setCameraMuted({required bool muted}) async {
    _ensureNotDisposed();
    final track = _localVideoTrack;
    if (track == null) {
      throw StateError('Local video has not been started.');
    }
    _cameraMuted = muted;
    track.enabled = !muted;
    _appendDiagnostic(_mediaStates, 'cameraMuted:$muted');
  }

  @override
  Future<void> switchCamera() async {
    _ensureNotDisposed();
    final track = _localVideoTrack;
    if (track == null) {
      throw StateError('Local video has not been started.');
    }
    await _config.platform.switchCamera(track);
    _appendDiagnostic(_mediaStates, 'switchCamera');
  }

  @override
  Future<void> setDeafened({required bool deafened}) async {
    _ensureNotDisposed();
    _deafened = deafened;
    for (final track in _remoteAudioTracks) {
      track.enabled = !deafened;
    }
    _appendDiagnostic(_mediaStates, 'deafened:$deafened');
  }

  @override
  Future<void> setAudioOutputRoute(CallMediaOutputRoute route) async {
    _ensureNotDisposed();
    switch (route) {
      case CallMediaOutputRoute.systemDefault:
        await _config.platform.setSpeakerphoneOn(false);
        break;
      case CallMediaOutputRoute.speaker:
        await _config.platform.setSpeakerphoneOn(true);
        break;
      case CallMediaOutputRoute.bluetooth:
        await _config.platform.setSpeakerphoneOnButPreferBluetooth();
        break;
    }
    _appendDiagnostic(_mediaStates, 'audioOutputRoute:${route.name}');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _connectionEpoch += 1;
    _pendingRemoteCandidates.clear();
    _remoteDescriptionSet = false;
    _mediaOperation = null;
    final stream = _localStream;
    _localStream = null;
    _localAudioTrack = null;
    _localVideoTrack = null;
    try {
      if (stream != null) {
        await _disposeMediaStream(stream);
      }
      await _disposeRemoteMedia();
      await _closePeerConnection();
      await _clearVoiceAudioIfPrepared();
      _emitState(CallMediaPhase.disposed);
    } finally {
      await _closeControllers();
    }
  }

  bool _hasLocalMediaFor(CallMediaKind kind) {
    return _localStream != null &&
        _localAudioTrack != null &&
        (kind == CallMediaKind.audio || _localVideoTrack != null);
  }

  Map<String, dynamic> _sdpConstraints(CallMediaKind kind) {
    return kind == CallMediaKind.video
        ? _videoSdpConstraints
        : _audioSdpConstraints;
  }

  Map<String, dynamic> _localMediaConstraints(
    CallMediaKind kind, {
    required String? audioDeviceId,
    required String? videoDeviceId,
  }) {
    return <String, dynamic>{
      'audio': <String, dynamic>{
        'deviceId': ?audioDeviceId,
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': switch (kind) {
        CallMediaKind.audio => false,
        CallMediaKind.video => _localVideoConstraints(videoDeviceId),
      },
    };
  }

  Map<String, dynamic> _localVideoConstraints(String? deviceId) {
    return <String, dynamic>{
      if (deviceId == null) 'facingMode': 'user' else 'deviceId': deviceId,
      'mandatory': <String, dynamic>{
        'minWidth': '320',
        'minHeight': '240',
        'maxWidth': '640',
        'maxHeight': '480',
        'minFrameRate': '15',
        'maxFrameRate': '30',
      },
      'optional': <dynamic>[],
    };
  }

  Future<RTCPeerConnection> _ensurePeerConnection() async {
    _ensureNotDisposed();
    if (_peerConnectionClosed) {
      throw StateError('Call media peer connection has already been closed.');
    }
    final existing = _peerConnection;
    if (existing != null) {
      return existing;
    }
    final connection = await _config.platform.createPeerConnection(
      _config.toRtcConfiguration(),
    );
    if (_disposed) {
      try {
        await connection.close();
      } finally {
        await connection.dispose();
      }
      _ensureNotDisposed();
    }
    _peerConnection = connection;
    _connectionEpoch += 1;
    _wirePeerConnection(connection);
    return connection;
  }

  void _wirePeerConnection(RTCPeerConnection connection) {
    connection.onIceCandidate = (RTCIceCandidate candidate) {
      if (_shouldIgnorePeerCallback(connection)) {
        return;
      }
      final callCandidate = CallIceCandidate.fromRtc(candidate);
      if (callCandidate.candidate.trim().isEmpty) {
        return;
      }
      _localCandidateCount += 1;
      _iceController.add(callCandidate);
    };
    connection.onTrack = (RTCTrackEvent event) {
      if (_shouldIgnorePeerCallback(connection)) {
        return;
      }
      switch (event.track.kind) {
        case 'audio':
          _retainRemoteAudio(event.track, event.streams);
          break;
        case 'video':
          _retainRemoteVideo(event.track, event.streams);
          break;
        default:
          return;
      }
      _remoteTrackController.add(
        CallRemoteMediaTrack(
          track: event.track,
          streams: List<MediaStream>.unmodifiable(event.streams),
          receivedAt: DateTime.now(),
        ),
      );
    };
    connection.onIceConnectionState = (RTCIceConnectionState state) {
      if (_shouldIgnorePeerCallback(connection)) {
        return;
      }
      _appendDiagnostic(_iceConnectionStates, state.toString());
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _emitState(CallMediaPhase.connected);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _emitState(
            CallMediaPhase.failed,
            detail: state.toString(),
            failureReason: CallMediaFailureReason.negotiationFailed,
          );
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          if (!_disposed) {
            _emitState(
              CallMediaPhase.failed,
              detail: state.toString(),
              failureReason: CallMediaFailureReason.negotiationFailed,
            );
          }
          break;
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          _emitState(CallMediaPhase.connecting);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateNew:
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        case RTCIceConnectionState.RTCIceConnectionStateCount:
          break;
      }
    };
    connection.onConnectionState = (RTCPeerConnectionState state) {
      if (_shouldIgnorePeerCallback(connection)) {
        return;
      }
      _appendDiagnostic(_peerConnectionStates, state.toString());
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _emitState(CallMediaPhase.connected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _emitState(
            CallMediaPhase.failed,
            detail: state.toString(),
            failureReason: CallMediaFailureReason.negotiationFailed,
          );
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          if (!_disposed) {
            _emitState(
              CallMediaPhase.failed,
              detail: state.toString(),
              failureReason: CallMediaFailureReason.negotiationFailed,
            );
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _emitState(CallMediaPhase.connecting);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          break;
      }
    };
  }

  Future<void> _flushRemoteCandidates({
    required RTCPeerConnection connection,
    required int epoch,
  }) async {
    if (_pendingRemoteCandidates.isEmpty) {
      return;
    }
    final candidates = List<CallIceCandidate>.of(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in candidates) {
      await connection.addCandidate(candidate.toRtc());
      _ensureCurrentPeerConnection(
        connection,
        epoch,
        'flushing remote candidates',
      );
    }
  }

  Future<T> _runMediaOperation<T>(
    String operationName,
    Future<T> Function() operation,
  ) async {
    _ensureNotDisposed();
    if (_mediaOperation != null) {
      throw StateError('Call media negotiation is already running.');
    }
    final operationCompleter = Completer<void>();
    _mediaOperation = operationCompleter.future;
    try {
      return await operation();
    } catch (error) {
      if (!_disposed && _lastPhase != CallMediaPhase.failed) {
        _emitFailed(
          error,
          detail: 'Failed to $operationName.',
          fallback: CallMediaFailureReason.negotiationFailed,
        );
      }
      rethrow;
    } finally {
      if (_mediaOperation == operationCompleter.future) {
        _mediaOperation = null;
      }
      operationCompleter.complete();
    }
  }

  Future<void> _prepareVoiceAudio() async {
    await _config.platform.prepareVoiceAudio();
    _voiceAudioPrepared = true;
  }

  Future<String?> _selectedAudioInputDeviceId() async {
    final provider = _config.selectedAudioInputDeviceIdProvider;
    String? selected;
    try {
      selected = (await provider?.call())?.trim();
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'selectedAudioInputLoad failed | $error');
      _lastError = error.toString();
      return null;
    }
    if (selected == null || selected.isEmpty) {
      return null;
    }

    try {
      final devices = await _config.platform.enumerateMediaDevices();
      final audioInputs = devices
          .where(
            (MediaDeviceInfo device) =>
                device.kind == 'audioinput' &&
                device.deviceId.trim().isNotEmpty,
          )
          .toList(growable: false);
      if (audioInputs.isNotEmpty &&
          !audioInputs.any(
            (MediaDeviceInfo device) => device.deviceId == selected,
          )) {
        _appendDiagnostic(_mediaStates, 'selectedAudioInputMissing');
        return null;
      }
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'enumerateMediaDevices failed | $error');
      _lastError = error.toString();
    }

    try {
      await _config.platform.selectAudioInput(selected);
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'selectAudioInput failed | $error');
      _lastError = error.toString();
    }
    return selected;
  }

  Future<String?> _selectedVideoInputDeviceId() async {
    final provider = _config.selectedVideoInputDeviceIdProvider;
    String? selected;
    try {
      selected = (await provider?.call())?.trim();
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'selectedVideoInputLoad failed | $error');
      _lastError = error.toString();
      return null;
    }
    if (selected == null || selected.isEmpty) {
      return null;
    }

    try {
      final devices = await _config.platform.enumerateMediaDevices();
      final videoInputs = devices
          .where(
            (MediaDeviceInfo device) =>
                device.kind == 'videoinput' &&
                device.deviceId.trim().isNotEmpty,
          )
          .toList(growable: false);
      if (videoInputs.isNotEmpty &&
          !videoInputs.any(
            (MediaDeviceInfo device) => device.deviceId == selected,
          )) {
        _appendDiagnostic(_mediaStates, 'selectedVideoInputMissing');
        return null;
      }
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'enumerateMediaDevices failed | $error');
      _lastError = error.toString();
    }

    return selected;
  }

  Future<void> _clearVoiceAudioIfPrepared() async {
    if (!_voiceAudioPrepared) {
      return;
    }
    _voiceAudioPrepared = false;
    try {
      await _config.platform.clearVoiceAudio();
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'clearVoiceAudio failed | $error');
      _lastError = error.toString();
    }
  }

  void _retainRemoteAudio(MediaStreamTrack track, List<MediaStream> streams) {
    track.enabled = !_deafened;
    if (!_containsTrack(_remoteAudioTracks, track)) {
      _remoteAudioTracks.add(track);
    }
    _retainRemoteStreams(streams);
    _appendDiagnostic(_mediaStates, 'remoteAudioReady');
  }

  void _retainRemoteVideo(MediaStreamTrack track, List<MediaStream> streams) {
    if (!_containsTrack(_remoteVideoTracks, track)) {
      _remoteVideoTracks.add(track);
    }
    _retainRemoteStreams(streams);
    _appendDiagnostic(_mediaStates, 'remoteVideoReady');
  }

  void _retainRemoteStreams(List<MediaStream> streams) {
    for (final stream in streams) {
      if (!_containsStream(_remoteStreams, stream)) {
        _remoteStreams.add(stream);
      }
    }
  }

  bool _containsTrack(List<MediaStreamTrack> tracks, MediaStreamTrack track) {
    final trackId = track.id;
    return tracks.any((MediaStreamTrack existing) {
      final existingId = existing.id;
      return identical(existing, track) ||
          (trackId != null && existingId != null && existingId == trackId);
    });
  }

  bool _containsStream(List<MediaStream> streams, MediaStream stream) {
    final streamId = stream.id;
    return streams.any((MediaStream existing) {
      return identical(existing, stream) || existing.id == streamId;
    });
  }

  Future<void> _disposeRemoteMedia() async {
    final remoteTracks = <MediaStreamTrack>[
      ..._remoteAudioTracks,
      ..._remoteVideoTracks,
    ];
    final remoteStreams = List<MediaStream>.of(_remoteStreams);
    _remoteAudioTracks.clear();
    _remoteVideoTracks.clear();
    _remoteStreams.clear();
    for (final track in remoteTracks) {
      try {
        await track.stop();
      } catch (error) {
        _appendDiagnostic(_mediaStates, 'remote track stop failed | $error');
      }
    }
    for (final stream in remoteStreams) {
      try {
        await stream.dispose();
      } catch (error) {
        _appendDiagnostic(
          _mediaStates,
          'remote stream dispose failed | $error',
        );
      }
    }
  }

  Future<void> _disposeMediaStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {
        // Best-effort media device release.
      }
    }
    try {
      await stream.dispose();
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'local stream dispose failed | $error');
      _lastError = error.toString();
    }
  }

  Future<void> _closePeerConnection() async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }
    _peerConnection = null;
    _peerConnectionClosed = true;
    _connectionEpoch += 1;
    _remoteDescriptionSet = false;
    _pendingRemoteCandidates.clear();
    connection.onIceCandidate = null;
    connection.onTrack = null;
    connection.onIceConnectionState = null;
    connection.onConnectionState = null;
    try {
      await connection.close();
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'peer close failed | $error');
      _lastError = error.toString();
    }
    try {
      await connection.dispose();
    } catch (error) {
      _appendDiagnostic(_mediaStates, 'peer dispose failed | $error');
      _lastError = error.toString();
    }
  }

  bool _shouldIgnorePeerCallback(RTCPeerConnection connection) {
    return _disposed ||
        _controllersClosed ||
        !identical(_peerConnection, connection) ||
        _peerConnectionClosed;
  }

  void _ensureCurrentPeerConnection(
    RTCPeerConnection connection,
    int epoch,
    String action,
  ) {
    _ensureNotDisposed();
    if (!identical(_peerConnection, connection) ||
        _connectionEpoch != epoch ||
        _peerConnectionClosed) {
      throw StateError('Call media peer connection changed while $action.');
    }
  }

  void _emitFailed(
    Object error, {
    String? detail,
    required CallMediaFailureReason fallback,
  }) {
    final reason = error is CallMediaException ? error.reason : fallback;
    _emitState(
      CallMediaPhase.failed,
      detail: detail,
      error: error,
      failureReason: reason,
    );
  }

  void _emitState(
    CallMediaPhase phase, {
    String? detail,
    Object? error,
    CallMediaFailureReason? failureReason,
  }) {
    if (_controllersClosed) {
      return;
    }
    _lastPhase = phase;
    _lastDetail = detail ?? _lastDetail;
    _lastError = error?.toString() ?? _lastError;
    _lastFailureReason = failureReason ?? _lastFailureReason;
    _appendDiagnostic(
      _mediaStates,
      <String>[
        phase.name,
        if (detail != null && detail.trim().isNotEmpty) detail.trim(),
        if (failureReason != null) failureReason.name,
        if (error != null) error.toString(),
      ].join(' | '),
    );
    _stateController.add(
      CallMediaState(
        phase: phase,
        detail: detail,
        error: error,
        failureReason: failureReason,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> _closeControllers() async {
    if (_controllersClosed) {
      return;
    }
    _controllersClosed = true;
    await Future.wait(<Future<void>>[
      _iceController.close(),
      _remoteTrackController.close(),
      _stateController.close(),
    ]);
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Call media connection has been disposed.');
    }
  }

  void _appendDiagnostic(List<String> target, String value) {
    const maxDiagnostics = 40;
    target.add(value);
    if (target.length > maxDiagnostics) {
      target.removeRange(0, target.length - maxDiagnostics);
    }
  }
}
