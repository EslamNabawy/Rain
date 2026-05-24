import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models.dart';
import 'voice_media_models.dart';

const Map<String, dynamic> _voiceSdpConstraints = <String, dynamic>{
  'mandatory': <String, dynamic>{
    'OfferToReceiveAudio': true,
    'OfferToReceiveVideo': false,
  },
  'optional': <dynamic>[],
};

abstract class VoiceMediaConnection {
  Stream<VoiceIceCandidate> get onIceCandidate;
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack;
  Stream<VoiceMediaAudioLevel> get onAudioLevelChanged;
  Stream<VoiceMediaState> get onStateChanged;
  VoiceMediaDiagnostics get diagnostics;

  Future<void> startLocalAudio();
  Future<VoiceSessionDescription> createOffer();
  Future<VoiceSessionDescription> acceptOffer(VoiceSessionDescription offer);
  Future<void> applyAnswer(VoiceSessionDescription answer);
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate);
  Future<void> setMuted({required bool muted});
  Future<void> setDeafened({required bool deafened});
  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route);
  Future<void> dispose();
}

class DefaultVoiceMediaConnection implements VoiceMediaConnection {
  DefaultVoiceMediaConnection({
    required PeerConfig config,
    Duration audioLevelSampleInterval = const Duration(milliseconds: 250),
  }) : _config = config,
       _audioLevelSampleInterval = audioLevelSampleInterval;

  final PeerConfig _config;
  final Duration _audioLevelSampleInterval;
  final StreamController<VoiceIceCandidate> _iceController =
      StreamController<VoiceIceCandidate>.broadcast();
  final StreamController<VoiceRemoteAudioTrack> _remoteTrackController =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaAudioLevel> _audioLevelController =
      StreamController<VoiceMediaAudioLevel>.broadcast();
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
  final _VoiceAudioLevelStatsSampler _audioLevelStatsSampler =
      _VoiceAudioLevelStatsSampler();
  Timer? _audioLevelTimer;
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
  bool _deafened = false;
  bool _samplingAudioLevel = false;
  bool _disposed = false;
  bool _controllersClosed = false;

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack =>
      _remoteTrackController.stream;

  @override
  Stream<VoiceMediaAudioLevel> get onAudioLevelChanged =>
      _audioLevelController.stream;

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
      localAudioTrackCount: _localAudioTrack == null ? 0 : 1,
      remoteAudioTrackCount: _remoteAudioTracks.length,
      localVideoTrackCount: 0,
      remoteVideoTrackCount: 0,
      remoteStreamCount: _remoteStreams.length,
      hasLocalAudio: _localStream != null && _localAudioTrack != null,
      hasLocalVideo: false,
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
      final selectedAudioInputDeviceId = await _selectedAudioInputDeviceId();
      _ensureCurrentPeerConnection(
        connection,
        epoch,
        'selecting local audio input',
      );
      final stream = await _config.platform.getUserMedia(
        _localAudioConstraints(selectedAudioInputDeviceId),
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
        final offer = await connection.createOffer(_voiceSdpConstraints);
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
        final answer = await connection.createAnswer(_voiceSdpConstraints);
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
  Future<void> setDeafened({required bool deafened}) async {
    _ensureNotDisposed();
    _deafened = deafened;
    for (final track in _remoteAudioTracks) {
      track.enabled = !deafened;
    }
    _appendDiagnostic(_mediaStates, 'deafened:$deafened');
  }

  @override
  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route) async {
    _ensureNotDisposed();
    try {
      switch (route) {
        case VoiceMediaOutputRoute.systemDefault:
          await _config.platform.setSpeakerphoneOn(false);
          break;
        case VoiceMediaOutputRoute.speaker:
          await _config.platform.setSpeakerphoneOn(true);
          break;
        case VoiceMediaOutputRoute.bluetooth:
          await _config.platform.setSpeakerphoneOnButPreferBluetooth();
          break;
      }
    } catch (error) {
      _appendDiagnostic(
        _mediaStates,
        'audioOutputRoute:${route.name} failed | $error',
      );
      _lastError = error.toString();
      rethrow;
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
    _stopAudioLevelSampler();
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
          .where((device) {
            return device.kind == 'audioinput' &&
                device.deviceId.trim().isNotEmpty;
          })
          .toList(growable: false);
      if (audioInputs.isNotEmpty &&
          !audioInputs.any((device) => device.deviceId == selected)) {
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

  Map<String, dynamic> _localAudioConstraints(String? deviceId) {
    return <String, dynamic>{
      'audio': <String, dynamic>{
        'deviceId': ?deviceId,
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    };
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
    _startAudioLevelSampler();
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
    _stopAudioLevelSampler();
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

  void _startAudioLevelSampler() {
    if (_audioLevelTimer != null ||
        _disposed ||
        _controllersClosed ||
        _audioLevelSampleInterval <= Duration.zero) {
      return;
    }
    final connection = _peerConnection;
    if (connection == null) {
      return;
    }
    final epoch = _connectionEpoch;
    unawaited(_sampleAudioLevel(connection: connection, epoch: epoch));
    _audioLevelTimer = Timer.periodic(_audioLevelSampleInterval, (_) {
      unawaited(_sampleAudioLevel(connection: connection, epoch: epoch));
    });
  }

  void _stopAudioLevelSampler() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
    _samplingAudioLevel = false;
    _audioLevelStatsSampler.reset();
  }

  Future<void> _sampleAudioLevel({
    required RTCPeerConnection connection,
    required int epoch,
  }) async {
    if (_samplingAudioLevel ||
        _disposed ||
        _controllersClosed ||
        !identical(_peerConnection, connection) ||
        _connectionEpoch != epoch ||
        _peerConnectionClosed) {
      return;
    }
    _samplingAudioLevel = true;
    try {
      final reports = await connection.getStats();
      if (_disposed ||
          _controllersClosed ||
          !identical(_peerConnection, connection) ||
          _connectionEpoch != epoch ||
          _peerConnectionClosed) {
        return;
      }
      _emitAudioLevel(
        _audioLevelStatsSampler.sample(
          reports,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (error) {
      if (!_disposed && !_controllersClosed) {
        _appendDiagnostic(_mediaStates, 'audio level stats failed | $error');
        _lastError = error.toString();
        _emitAudioLevel(
          VoiceMediaAudioLevel.unavailable(
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }
    } finally {
      _samplingAudioLevel = false;
    }
  }

  void _emitAudioLevel(VoiceMediaAudioLevel level) {
    if (_controllersClosed) {
      return;
    }
    _audioLevelController.add(level);
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
      _audioLevelController.close(),
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

enum _VoiceAudioLevelSide { local, remote, unknown }

final class _VoiceAudioLevelStatsSampler {
  final Map<String, _VoiceAudioEnergyPoint> _previousEnergy =
      <String, _VoiceAudioEnergyPoint>{};

  VoiceMediaAudioLevel sample(
    Iterable<StatsReport> reports, {
    required int updatedAt,
  }) {
    double? remoteLevel;
    double? localLevel;
    var source = VoiceMediaAudioLevelSource.unavailable;
    final nextEnergy = <String, _VoiceAudioEnergyPoint>{};

    for (final report in reports) {
      if (!_isAudioReport(report)) {
        continue;
      }

      final side = _audioReportSide(report);
      final directLevel = _directAudioLevel(report.values);
      if (directLevel != null) {
        switch (side) {
          case _VoiceAudioLevelSide.remote:
            remoteLevel = _maxLevel(remoteLevel, directLevel);
            source = VoiceMediaAudioLevelSource.audioLevel;
            break;
          case _VoiceAudioLevelSide.local:
            localLevel = _maxLevel(localLevel, directLevel);
            source = VoiceMediaAudioLevelSource.audioLevel;
            break;
          case _VoiceAudioLevelSide.unknown:
            remoteLevel = _maxLevel(remoteLevel, directLevel);
            source = VoiceMediaAudioLevelSource.audioLevel;
            break;
        }
      }

      final energy = _VoiceAudioEnergyPoint.fromStats(report.values);
      if (energy == null) {
        continue;
      }
      if (report.id.isNotEmpty) {
        nextEnergy[report.id] = energy;
      }
      if (directLevel != null) {
        continue;
      }

      final previous = _previousEnergy[report.id];
      final energyLevel = previous == null
          ? null
          : _levelFromEnergyDelta(previous: previous, current: energy);
      if (energyLevel == null) {
        continue;
      }

      switch (side) {
        case _VoiceAudioLevelSide.remote:
          remoteLevel = _maxLevel(remoteLevel, energyLevel);
          if (source == VoiceMediaAudioLevelSource.unavailable) {
            source = VoiceMediaAudioLevelSource.totalAudioEnergy;
          }
          break;
        case _VoiceAudioLevelSide.local:
          localLevel = _maxLevel(localLevel, energyLevel);
          if (source == VoiceMediaAudioLevelSource.unavailable) {
            source = VoiceMediaAudioLevelSource.totalAudioEnergy;
          }
          break;
        case _VoiceAudioLevelSide.unknown:
          remoteLevel = _maxLevel(remoteLevel, energyLevel);
          if (source == VoiceMediaAudioLevelSource.unavailable) {
            source = VoiceMediaAudioLevelSource.totalAudioEnergy;
          }
          break;
      }
    }

    _previousEnergy
      ..clear()
      ..addAll(nextEnergy);

    if (remoteLevel == null && localLevel == null) {
      return VoiceMediaAudioLevel.unavailable(updatedAt: updatedAt);
    }

    return VoiceMediaAudioLevel(
      remoteLevel: remoteLevel ?? 0,
      localLevel: localLevel ?? 0,
      updatedAt: updatedAt,
      source: source,
    );
  }

  void reset() {
    _previousEnergy.clear();
  }
}

final class _VoiceAudioEnergyPoint {
  const _VoiceAudioEnergyPoint({
    required this.totalAudioEnergy,
    required this.totalSamplesDuration,
  });

  final double totalAudioEnergy;
  final double totalSamplesDuration;

  static _VoiceAudioEnergyPoint? fromStats(Map<dynamic, dynamic> values) {
    final energy = _doubleStat(values, const <String>['totalAudioEnergy']);
    final duration = _doubleStat(values, const <String>[
      'totalSamplesDuration',
    ]);
    if (energy == null ||
        duration == null ||
        !energy.isFinite ||
        !duration.isFinite ||
        energy < 0 ||
        duration < 0) {
      return null;
    }
    return _VoiceAudioEnergyPoint(
      totalAudioEnergy: energy,
      totalSamplesDuration: duration,
    );
  }
}

bool _isAudioReport(StatsReport report) {
  final kind = _stringStat(report.values, const <String>[
    'kind',
    'mediaType',
    'googTrackKind',
  ]);
  if (kind != null) {
    return kind.toLowerCase() == 'audio';
  }
  return _hasAnyStat(report.values, const <String>[
    'audioLevel',
    'audioInputLevel',
    'audioOutputLevel',
    'totalAudioEnergy',
    'totalSamplesDuration',
  ]);
}

_VoiceAudioLevelSide _audioReportSide(StatsReport report) {
  final type = report.type.toLowerCase().replaceAll('_', '-');
  final remoteSource = _boolStat(report.values, const <String>['remoteSource']);
  if (remoteSource == true ||
      type.contains('inbound') ||
      type.contains('receiver')) {
    return _VoiceAudioLevelSide.remote;
  }
  if (remoteSource == false ||
      type.contains('outbound') ||
      type.contains('sender') ||
      type == 'media-source') {
    return _VoiceAudioLevelSide.local;
  }
  final id = report.id.toLowerCase();
  if (id.contains('remote')) {
    return _VoiceAudioLevelSide.remote;
  }
  if (id.contains('local')) {
    return _VoiceAudioLevelSide.local;
  }
  return _VoiceAudioLevelSide.unknown;
}

double? _directAudioLevel(Map<dynamic, dynamic> values) {
  final audioLevel = _doubleStat(values, const <String>['audioLevel']);
  if (audioLevel != null) {
    return _clampAudioLevel(audioLevel);
  }
  final legacyLevel = _doubleStat(values, const <String>[
    'audioInputLevel',
    'audioOutputLevel',
  ]);
  if (legacyLevel == null || !legacyLevel.isFinite || legacyLevel <= 0) {
    return null;
  }
  return _clampAudioLevel(legacyLevel / 32768);
}

double? _levelFromEnergyDelta({
  required _VoiceAudioEnergyPoint previous,
  required _VoiceAudioEnergyPoint current,
}) {
  final energyDelta = current.totalAudioEnergy - previous.totalAudioEnergy;
  final durationDelta =
      current.totalSamplesDuration - previous.totalSamplesDuration;
  if (energyDelta < 0 || durationDelta <= 0) {
    return null;
  }
  return _clampAudioLevel(math.sqrt(energyDelta / durationDelta));
}

double _maxLevel(double? current, double next) {
  if (current == null || next > current) {
    return next;
  }
  return current;
}

double _clampAudioLevel(double value) {
  if (value.isNaN || !value.isFinite || value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 1;
  }
  return value;
}

Object? _statValue(Map<dynamic, dynamic> values, Iterable<String> keys) {
  for (final key in keys) {
    if (values.containsKey(key)) {
      return values[key];
    }
  }
  final normalized = <String, Object?>{
    for (final entry in values.entries)
      entry.key.toString().toLowerCase(): entry.value,
  };
  for (final key in keys) {
    final value = normalized[key.toLowerCase()];
    if (value != null) {
      return value;
    }
  }
  return null;
}

bool _hasAnyStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  return _statValue(values, keys) != null;
}

String? _stringStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  final value = _statValue(values, keys);
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _doubleStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  final value = _statValue(values, keys);
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

bool? _boolStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  final value = _statValue(values, keys);
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return null;
}
