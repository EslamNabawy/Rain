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
  final List<MediaStreamTrack> _remoteAudioTracks = <MediaStreamTrack>[];
  final List<MediaStream> _remoteStreams = <MediaStream>[];

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStreamTrack? _localAudioTrack;
  Future<void>? _localAudioStartFuture;
  Future<void>? _mediaOperation;
  int _localCandidateCount = 0;
  int _remoteCandidateCount = 0;
  int _connectionEpoch = 0;
  String? _lastDetail;
  String? _lastError;
  VoiceMediaPhase _lastPhase = VoiceMediaPhase.idle;
  bool _remoteDescriptionSet = false;
  bool _peerConnectionClosed = false;
  bool _voiceAudioPrepared = false;
  bool _muted = false;
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
      remoteAudioTrackCount: _remoteAudioTracks.length,
      remoteStreamCount: _remoteStreams.length,
      hasLocalAudio: _localStream != null && _localAudioTrack != null,
      peerConnectionClosed: _peerConnectionClosed,
      disposed: _disposed,
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
    final existingStart = _localAudioStartFuture;
    if (existingStart != null) {
      return existingStart;
    }

    final startFuture = _startLocalAudio();
    _localAudioStartFuture = startFuture;
    try {
      await startFuture;
    } finally {
      if (_localStream == null || _localAudioTrack == null) {
        _localAudioStartFuture = null;
      }
    }
  }

  Future<void> _startLocalAudio() async {
    final connection = await _ensurePeerConnection();
    final epoch = _connectionEpoch;
    MediaStream? pendingStream;
    var keepVoiceAudio = false;
    try {
      _emitState(VoiceMediaPhase.startingLocalAudio);
      await _prepareVoiceAudio();
      _ensureCurrentPeerConnection(connection, epoch, 'preparing local audio');
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
      _ensureCurrentPeerConnection(connection, epoch, 'capturing local audio');
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.isEmpty) {
        throw StateError('No microphone audio track was captured.');
      }
      final audioTrack = audioTracks.first;
      await connection.addTrack(audioTrack, stream);
      _ensureCurrentPeerConnection(connection, epoch, 'attaching local audio');
      _localStream = stream;
      _localAudioTrack = audioTrack;
      pendingStream = null;
      keepVoiceAudio = true;
      if (_muted) {
        await _config.platform.setMicrophoneMuted(audioTrack, muted: true);
      }
      _emitState(VoiceMediaPhase.localAudioReady);
    } catch (error) {
      if (pendingStream != null) {
        await _disposeMediaStream(pendingStream);
      }
      if (!keepVoiceAudio) {
        _localStream = null;
        _localAudioTrack = null;
        await _clearVoiceAudioIfPrepared();
      }
      await _closePeerConnection();
      if (!_disposed) {
        _emitState(VoiceMediaPhase.failed, error: error);
      }
      rethrow;
    }
  }

  @override
  Future<VoiceSessionDescription> createOffer() async {
    return _runMediaOperation<VoiceSessionDescription>(
      'create offer',
      () async {
        await startLocalAudio();
        final connection = await _ensurePeerConnection();
        final epoch = _connectionEpoch;
        _emitState(VoiceMediaPhase.creatingOffer);
        final offer = await connection.createOffer(const <String, dynamic>{
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        });
        _ensureCurrentPeerConnection(connection, epoch, 'creating offer');
        await connection.setLocalDescription(offer);
        _ensureCurrentPeerConnection(connection, epoch, 'setting local offer');
        _emitState(VoiceMediaPhase.connecting);
        return VoiceSessionDescription.fromRtc(offer);
      },
    );
  }

  @override
  Future<VoiceSessionDescription> acceptOffer(
    VoiceSessionDescription offer,
  ) async {
    return _runMediaOperation<VoiceSessionDescription>(
      'accept offer',
      () async {
        await startLocalAudio();
        final connection = await _ensurePeerConnection();
        final epoch = _connectionEpoch;
        _emitState(VoiceMediaPhase.applyingOffer);
        await connection.setRemoteDescription(offer.toRtc());
        _ensureCurrentPeerConnection(connection, epoch, 'applying offer');
        _remoteDescriptionSet = true;
        await _flushRemoteCandidates(connection: connection, epoch: epoch);
        final answer = await connection.createAnswer(const <String, dynamic>{
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        });
        _ensureCurrentPeerConnection(connection, epoch, 'creating answer');
        await connection.setLocalDescription(answer);
        _ensureCurrentPeerConnection(connection, epoch, 'setting local answer');
        _emitState(VoiceMediaPhase.connecting);
        return VoiceSessionDescription.fromRtc(answer);
      },
    );
  }

  @override
  Future<void> applyAnswer(VoiceSessionDescription answer) async {
    await _runMediaOperation<void>('apply answer', () async {
      final connection = await _ensurePeerConnection();
      final epoch = _connectionEpoch;
      _emitState(VoiceMediaPhase.applyingAnswer);
      await connection.setRemoteDescription(answer.toRtc());
      _ensureCurrentPeerConnection(connection, epoch, 'applying answer');
      _remoteDescriptionSet = true;
      await _flushRemoteCandidates(connection: connection, epoch: epoch);
      _emitState(VoiceMediaPhase.connecting);
    });
  }

  @override
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate) async {
    _ensureNotDisposed();
    if (_peerConnectionClosed) {
      throw StateError('Voice media peer connection has already been closed.');
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
  Future<void> setMuted({required bool muted}) async {
    _ensureNotDisposed();
    final track = _localAudioTrack;
    if (track == null) {
      throw StateError('Local audio has not been started.');
    }
    _muted = muted;
    await _config.platform.setMicrophoneMuted(track, muted: muted);
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
    try {
      if (stream != null) {
        await _disposeMediaStream(stream);
      }
      await _disposeRemoteMedia();
      await _closePeerConnection();
      await _clearVoiceAudioIfPrepared();
      _emitState(VoiceMediaPhase.disposed);
    } finally {
      await _closeControllers();
    }
  }

  Future<RTCPeerConnection> _ensurePeerConnection() async {
    _ensureNotDisposed();
    if (_peerConnectionClosed) {
      throw StateError('Voice media peer connection has already been closed.');
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
      final voiceCandidate = VoiceIceCandidate.fromRtc(candidate);
      if (voiceCandidate.candidate.trim().isEmpty) {
        return;
      }
      _localCandidateCount += 1;
      _iceController.add(voiceCandidate);
    };
    connection.onTrack = (RTCTrackEvent event) {
      if (_shouldIgnorePeerCallback(connection) ||
          event.track.kind != 'audio') {
        return;
      }
      _retainRemoteAudio(event.track, event.streams);
      _remoteTrackController.add(
        VoiceRemoteAudioTrack(
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
          _emitState(VoiceMediaPhase.connected);
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _emitState(VoiceMediaPhase.failed, detail: state.toString());
          break;
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          if (!_disposed) {
            _emitState(VoiceMediaPhase.failed, detail: state.toString());
          }
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
      if (_shouldIgnorePeerCallback(connection)) {
        return;
      }
      _appendDiagnostic(_peerConnectionStates, state.toString());
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _emitState(VoiceMediaPhase.connected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _emitState(VoiceMediaPhase.failed, detail: state.toString());
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          if (!_disposed) {
            _emitState(VoiceMediaPhase.failed, detail: state.toString());
          }
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

  Future<void> _flushRemoteCandidates({
    required RTCPeerConnection connection,
    required int epoch,
  }) async {
    if (_pendingRemoteCandidates.isEmpty) {
      return;
    }
    final candidates = List<VoiceIceCandidate>.of(_pendingRemoteCandidates);
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
      throw StateError('Voice media negotiation is already running.');
    }
    final operationCompleter = Completer<void>();
    _mediaOperation = operationCompleter.future;
    try {
      return await operation();
    } catch (error) {
      if (!_disposed && _lastPhase != VoiceMediaPhase.failed) {
        _emitState(
          VoiceMediaPhase.failed,
          detail: 'Failed to $operationName.',
          error: error,
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
    if (!_containsTrack(_remoteAudioTracks, track)) {
      _remoteAudioTracks.add(track);
    }
    for (final stream in streams) {
      if (!_containsStream(_remoteStreams, stream)) {
        _remoteStreams.add(stream);
      }
    }
    _appendDiagnostic(
      _mediaStates,
      'remoteAudioReady | tracks=${_remoteAudioTracks.length} '
      'streams=${_remoteStreams.length}',
    );
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
    final remoteTracks = List<MediaStreamTrack>.of(_remoteAudioTracks);
    final remoteStreams = List<MediaStream>.of(_remoteStreams);
    _remoteAudioTracks.clear();
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
      throw StateError('Voice media peer connection changed while $action.');
    }
  }

  void _emitState(VoiceMediaPhase phase, {String? detail, Object? error}) {
    if (_controllersClosed) {
      return;
    }
    _lastPhase = phase;
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
