import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models.dart';
import 'voice_media_models.dart';

abstract class VoiceMediaConnection {
  Stream<VoiceIceCandidate> get onIceCandidate;
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack;
  Stream<VoiceMediaState> get onStateChanged;
  VoiceMediaDiagnostics get diagnostics;

  Future<void> startLocalAudio();
  Future<VoiceSessionDescription> createOffer();
  Future<VoiceSessionDescription> acceptOffer(VoiceSessionDescription offer);
  Future<void> applyAnswer(VoiceSessionDescription answer);
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate);
  Future<void> setMuted({required bool muted});
  Future<void> dispose();
}

class DefaultVoiceMediaConnection implements VoiceMediaConnection {
  DefaultVoiceMediaConnection({required PeerConfig config}) : _config = config;

  final PeerConfig _config;
  final StreamController<VoiceIceCandidate> _iceController =
      StreamController<VoiceIceCandidate>.broadcast();
  final StreamController<VoiceRemoteAudioTrack> _remoteTrackController =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaState> _stateController =
      StreamController<VoiceMediaState>.broadcast();
  final List<VoiceIceCandidate> _pendingRemoteCandidates =
      <VoiceIceCandidate>[];
  final List<String> _mediaStates = <String>[];
  final List<String> _iceConnectionStates = <String>[];
  final List<String> _peerConnectionStates = <String>[];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStreamTrack? _localAudioTrack;
  int _localCandidateCount = 0;
  int _remoteCandidateCount = 0;
  String? _lastDetail;
  String? _lastError;
  bool _remoteDescriptionSet = false;
  bool _disposed = false;
  bool _controllersClosed = false;

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack =>
      _remoteTrackController.stream;

  @override
  Stream<VoiceMediaState> get onStateChanged => _stateController.stream;

  @override
  VoiceMediaDiagnostics get diagnostics {
    return VoiceMediaDiagnostics(
      mediaStates: List<String>.unmodifiable(_mediaStates),
      iceConnectionStates: List<String>.unmodifiable(_iceConnectionStates),
      peerConnectionStates: List<String>.unmodifiable(_peerConnectionStates),
      localCandidateCount: _localCandidateCount,
      remoteCandidateCount: _remoteCandidateCount,
      pendingRemoteCandidateCount: _pendingRemoteCandidates.length,
      lastDetail: _lastDetail,
      lastError: _lastError,
    );
  }

  @override
  Future<void> startLocalAudio() async {
    _ensureNotDisposed();
    if (_localStream != null && _localAudioTrack != null) {
      return;
    }

    final connection = await _ensurePeerConnection();
    MediaStream? pendingStream;
    try {
      _emitState(VoiceMediaPhase.startingLocalAudio);
      await _config.platform.prepareVoiceAudio();
      final stream = await _config.platform.getUserMedia(
        const <String, dynamic>{
          'audio': <String, dynamic>{
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        },
      );
      pendingStream = stream;
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isEmpty) {
        throw StateError('No microphone audio track was captured.');
      }
      final audioTrack = audioTracks.first;
      await connection.addTrack(audioTrack, stream);
      _localStream = stream;
      _localAudioTrack = audioTrack;
      pendingStream = null;
      _emitState(VoiceMediaPhase.localAudioReady);
    } catch (error) {
      if (pendingStream != null) {
        await _disposeMediaStream(pendingStream);
      }
      await _config.platform.clearVoiceAudio();
      await _closePeerConnection();
      _emitState(VoiceMediaPhase.failed, error: error);
      rethrow;
    }
  }

  @override
  Future<VoiceSessionDescription> createOffer() async {
    _ensureNotDisposed();
    await startLocalAudio();
    final connection = await _ensurePeerConnection();
    _emitState(VoiceMediaPhase.creatingOffer);
    final offer = await connection.createOffer(const <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await connection.setLocalDescription(offer);
    _emitState(VoiceMediaPhase.connecting);
    return VoiceSessionDescription.fromRtc(offer);
  }

  @override
  Future<VoiceSessionDescription> acceptOffer(
    VoiceSessionDescription offer,
  ) async {
    _ensureNotDisposed();
    await startLocalAudio();
    final connection = await _ensurePeerConnection();
    _emitState(VoiceMediaPhase.applyingOffer);
    await connection.setRemoteDescription(offer.toRtc());
    _remoteDescriptionSet = true;
    await _flushRemoteCandidates();
    final answer = await connection.createAnswer(const <String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await connection.setLocalDescription(answer);
    _emitState(VoiceMediaPhase.connecting);
    return VoiceSessionDescription.fromRtc(answer);
  }

  @override
  Future<void> applyAnswer(VoiceSessionDescription answer) async {
    _ensureNotDisposed();
    final connection = await _ensurePeerConnection();
    _emitState(VoiceMediaPhase.applyingAnswer);
    await connection.setRemoteDescription(answer.toRtc());
    _remoteDescriptionSet = true;
    await _flushRemoteCandidates();
    _emitState(VoiceMediaPhase.connecting);
  }

  @override
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate) async {
    _ensureNotDisposed();
    _remoteCandidateCount += 1;
    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    final connection = await _ensurePeerConnection();
    await connection.addCandidate(candidate.toRtc());
  }

  @override
  Future<void> setMuted({required bool muted}) async {
    _ensureNotDisposed();
    final track = _localAudioTrack;
    if (track == null) {
      throw StateError('Local audio has not been started.');
    }
    await _config.platform.setMicrophoneMuted(track, muted: muted);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final stream = _localStream;
    _localStream = null;
    _localAudioTrack = null;
    try {
      if (stream != null) {
        await _disposeMediaStream(stream);
      }
      await _closePeerConnection();
      await _config.platform.clearVoiceAudio();
      _emitState(VoiceMediaPhase.disposed);
    } finally {
      await _closeControllers();
    }
  }

  Future<RTCPeerConnection> _ensurePeerConnection() async {
    final existing = _peerConnection;
    if (existing != null) {
      return existing;
    }
    final connection = await _config.platform.createPeerConnection(
      _config.toRtcConfiguration(),
    );
    _peerConnection = connection;
    _wirePeerConnection(connection);
    return connection;
  }

  void _wirePeerConnection(RTCPeerConnection connection) {
    connection.onIceCandidate = (RTCIceCandidate candidate) {
      if (_disposed || _controllersClosed) {
        return;
      }
      final voiceCandidate = VoiceIceCandidate.fromRtc(candidate);
      if (voiceCandidate.candidate.trim().isEmpty) {
        return;
      }
      _localCandidateCount += 1;
      _iceController.add(voiceCandidate);
    };
    connection.onTrack = (RTCTrackEvent event) {
      if (_disposed || _controllersClosed || event.track.kind != 'audio') {
        return;
      }
      _remoteTrackController.add(
        VoiceRemoteAudioTrack(
          track: event.track,
          streams: List<MediaStream>.unmodifiable(event.streams),
          receivedAt: DateTime.now(),
        ),
      );
    };
    connection.onIceConnectionState = (RTCIceConnectionState state) {
      _appendDiagnostic(_iceConnectionStates, state.toString());
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _emitState(VoiceMediaPhase.connected);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          _emitState(VoiceMediaPhase.failed, detail: state.toString());
          break;
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          _emitState(VoiceMediaPhase.connecting);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateNew:
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        case RTCIceConnectionState.RTCIceConnectionStateCount:
          break;
      }
    };
    connection.onConnectionState = (RTCPeerConnectionState state) {
      _appendDiagnostic(_peerConnectionStates, state.toString());
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _emitState(VoiceMediaPhase.connected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _emitState(VoiceMediaPhase.failed, detail: state.toString());
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _emitState(VoiceMediaPhase.connecting);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          break;
      }
    };
  }

  Future<void> _flushRemoteCandidates() async {
    if (_pendingRemoteCandidates.isEmpty) {
      return;
    }
    final connection = await _ensurePeerConnection();
    final candidates = List<VoiceIceCandidate>.of(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in candidates) {
      await connection.addCandidate(candidate.toRtc());
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
    await stream.dispose();
  }

  Future<void> _closePeerConnection() async {
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }
    _peerConnection = null;
    try {
      await connection.close();
    } finally {
      await connection.dispose();
    }
  }

  void _emitState(VoiceMediaPhase phase, {String? detail, Object? error}) {
    if (_controllersClosed) {
      return;
    }
    _lastDetail = detail ?? _lastDetail;
    _lastError = error?.toString() ?? _lastError;
    _appendDiagnostic(
      _mediaStates,
      <String>[
        phase.name,
        if (detail != null && detail.trim().isNotEmpty) detail.trim(),
        if (error != null) error.toString(),
      ].join(' | '),
    );
    _stateController.add(
      VoiceMediaState(
        phase: phase,
        detail: detail,
        error: error,
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
      throw StateError('Voice media connection has been disposed.');
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
