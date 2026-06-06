import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';

import 'video_call_renderers.dart';

final class VideoVoiceMediaConnection implements VoiceMediaConnection {
  VideoVoiceMediaConnection({
    required CallMediaConnection media,
    required VideoCallRenderers renderers,
    required CallMediaKind kind,
    required void Function(Object error, StackTrace stackTrace)
    onRemoteTrackError,
    required void Function(Object error, StackTrace stackTrace) onRendererError,
  }) : _media = media,
       _renderers = renderers,
       _kind = kind,
       _onRemoteTrackError = onRemoteTrackError,
       _onRendererError = onRendererError {
    _remoteTrackSubscription = _media.onRemoteTrack.listen(
      _handleRemoteTrack,
      onError: (Object error, StackTrace stackTrace) {
        _onRemoteTrackError(error, stackTrace);
      },
    );
  }

  final CallMediaConnection _media;
  final VideoCallRenderers _renderers;
  final CallMediaKind _kind;
  final void Function(Object error, StackTrace stackTrace) _onRemoteTrackError;
  final void Function(Object error, StackTrace stackTrace) _onRendererError;
  final StreamController<VoiceRemoteAudioTrack> _remoteAudioController =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaAudioLevel> _audioLevelController =
      StreamController<VoiceMediaAudioLevel>.broadcast();

  late final StreamSubscription<CallRemoteMediaTrack> _remoteTrackSubscription;
  bool _disposed = false;

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _media.onIceCandidate;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack =>
      _remoteAudioController.stream;

  @override
  Stream<VoiceMediaAudioLevel> get onAudioLevelChanged =>
      _audioLevelController.stream;

  @override
  Stream<VoiceMediaState> get onStateChanged {
    return _media.onStateChanged.map(_voiceMediaStateForCall);
  }

  @override
  VoiceMediaDiagnostics get diagnostics {
    return voiceMediaDiagnosticsForCall(_media.diagnostics);
  }

  @override
  Future<void> startLocalAudio() async {
    await _media.startLocalMedia(kind: _kind);
    await _attachLocalVideoStream();
  }

  @override
  Future<VoiceSessionDescription> createOffer({bool iceRestart = false}) async {
    final offer = await _media.createOffer(kind: _kind, iceRestart: iceRestart);
    await _attachLocalVideoStream();
    return offer;
  }

  @override
  Future<VoiceSessionDescription> acceptOffer(
    VoiceSessionDescription offer,
  ) async {
    final answer = await _media.acceptOffer(offer, kind: _kind);
    await _attachLocalVideoStream();
    return answer;
  }

  @override
  Future<void> applyAnswer(VoiceSessionDescription answer) async {
    await _media.applyAnswer(answer);
  }

  @override
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate) {
    return _media.addRemoteCandidate(candidate);
  }

  @override
  Future<void> setMuted({required bool muted}) {
    return _media.setMicrophoneMuted(muted: muted);
  }

  @override
  Future<void> setDeafened({required bool deafened}) {
    return _media.setDeafened(deafened: deafened);
  }

  @override
  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route) {
    return _media.setAudioOutputRoute(route);
  }

  @override
  Future<void> selectAudioOutputDevice(String deviceId) {
    return _media.selectAudioOutputDevice(deviceId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _remoteTrackSubscription.cancel();
    await _media.dispose();
    await _remoteAudioController.close();
    await _audioLevelController.close();
  }

  Future<void> _attachLocalVideoStream() async {
    if (_kind != CallMediaKind.video) {
      return;
    }
    try {
      await _renderers.attachLocalStream(_media.localStream);
    } catch (error, stackTrace) {
      final rendererError = VideoCallRendererException(
        'Video renderer failed while attaching local video stream.',
        error,
        target: VideoCallRendererTarget.local,
      );
      _onRendererError(rendererError, stackTrace);
      Error.throwWithStackTrace(rendererError, stackTrace);
    }
  }

  void _handleRemoteTrack(CallRemoteMediaTrack event) {
    if (_disposed) {
      return;
    }
    if (event.isAudio) {
      _remoteAudioController.add(
        VoiceRemoteAudioTrack(
          track: event.track,
          streams: event.streams,
          receivedAt: event.receivedAt,
        ),
      );
      return;
    }
    if (!event.isVideo) {
      return;
    }
    final stream = event.streams.isEmpty ? null : event.streams.first;
    unawaited(
      Future<void>.sync(() => _renderers.attachRemoteStream(stream)).catchError(
        (Object error, StackTrace stackTrace) {
          _onRendererError(
            VideoCallRendererException(
              'Video renderer failed while attaching remote video stream.',
              error,
              target: VideoCallRendererTarget.remote,
            ),
            stackTrace,
          );
        },
      ),
    );
  }
}

enum VideoCallRendererTarget { local, remote, unknown }

final class VideoCallRendererException implements Exception {
  const VideoCallRendererException(
    this.message,
    this.cause, {
    this.target = VideoCallRendererTarget.unknown,
  });

  final String message;
  final Object cause;
  final VideoCallRendererTarget target;

  @override
  String toString() => '$message $cause';
}

final class CallVoiceMediaConnection implements VoiceMediaConnection {
  CallVoiceMediaConnection({
    required CallMediaConnection media,
    required CallMediaKind kind,
    required void Function(Object error, StackTrace stackTrace)
    onRemoteTrackError,
  }) : _media = media,
       _kind = kind,
       _onRemoteTrackError = onRemoteTrackError {
    _remoteTrackSubscription = _media.onRemoteTrack.listen(
      _handleRemoteTrack,
      onError: (Object error, StackTrace stackTrace) {
        _onRemoteTrackError(error, stackTrace);
      },
    );
  }

  final CallMediaConnection _media;
  final CallMediaKind _kind;
  final void Function(Object error, StackTrace stackTrace) _onRemoteTrackError;
  final StreamController<VoiceRemoteAudioTrack> _remoteAudioController =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaAudioLevel> _audioLevelController =
      StreamController<VoiceMediaAudioLevel>.broadcast();

  late final StreamSubscription<CallRemoteMediaTrack> _remoteTrackSubscription;
  bool _disposed = false;

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _media.onIceCandidate;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack =>
      _remoteAudioController.stream;

  @override
  Stream<VoiceMediaAudioLevel> get onAudioLevelChanged =>
      _audioLevelController.stream;

  @override
  Stream<VoiceMediaState> get onStateChanged {
    return _media.onStateChanged.map(_voiceMediaStateForCall);
  }

  @override
  VoiceMediaDiagnostics get diagnostics {
    return voiceMediaDiagnosticsForCall(_media.diagnostics);
  }

  @override
  Future<void> startLocalAudio() {
    return _media.startLocalMedia(kind: _kind);
  }

  @override
  Future<VoiceSessionDescription> createOffer({bool iceRestart = false}) {
    return _media.createOffer(kind: _kind, iceRestart: iceRestart);
  }

  @override
  Future<VoiceSessionDescription> acceptOffer(VoiceSessionDescription offer) {
    return _media.acceptOffer(offer, kind: _kind);
  }

  @override
  Future<void> applyAnswer(VoiceSessionDescription answer) {
    return _media.applyAnswer(answer);
  }

  @override
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate) {
    return _media.addRemoteCandidate(candidate);
  }

  @override
  Future<void> setMuted({required bool muted}) {
    return _media.setMicrophoneMuted(muted: muted);
  }

  @override
  Future<void> setDeafened({required bool deafened}) {
    return _media.setDeafened(deafened: deafened);
  }

  @override
  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route) {
    return _media.setAudioOutputRoute(route);
  }

  @override
  Future<void> selectAudioOutputDevice(String deviceId) {
    return _media.selectAudioOutputDevice(deviceId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _remoteTrackSubscription.cancel();
    await _media.dispose();
    await _remoteAudioController.close();
    await _audioLevelController.close();
  }

  void _handleRemoteTrack(CallRemoteMediaTrack event) {
    if (_disposed || !event.isAudio) {
      return;
    }
    _remoteAudioController.add(
      VoiceRemoteAudioTrack(
        track: event.track,
        streams: event.streams,
        receivedAt: event.receivedAt,
      ),
    );
  }
}

VoiceMediaState _voiceMediaStateForCall(CallMediaState state) {
  return VoiceMediaState(
    phase: _voiceMediaPhaseForCall(state.phase),
    detail: state.detail,
    error: state.error,
    updatedAt: state.updatedAt,
  );
}

VoiceMediaPhase _voiceMediaPhaseForCall(CallMediaPhase phase) {
  return switch (phase) {
    CallMediaPhase.idle => VoiceMediaPhase.idle,
    CallMediaPhase.startingLocalMedia => VoiceMediaPhase.startingLocalAudio,
    CallMediaPhase.localMediaReady => VoiceMediaPhase.localAudioReady,
    CallMediaPhase.creatingOffer => VoiceMediaPhase.creatingOffer,
    CallMediaPhase.applyingOffer => VoiceMediaPhase.applyingOffer,
    CallMediaPhase.applyingAnswer => VoiceMediaPhase.applyingAnswer,
    CallMediaPhase.connecting => VoiceMediaPhase.connecting,
    CallMediaPhase.connected => VoiceMediaPhase.connected,
    CallMediaPhase.reconnecting => VoiceMediaPhase.reconnecting,
    CallMediaPhase.failed => VoiceMediaPhase.failed,
    CallMediaPhase.disposed => VoiceMediaPhase.disposed,
  };
}

VoiceMediaDiagnostics voiceMediaDiagnosticsForCall(
  CallMediaDiagnostics diagnostics,
) {
  return VoiceMediaDiagnostics(
    mediaStates: <String>[
      ...diagnostics.mediaStates,
      'remoteVideoTrackCount:${diagnostics.remoteVideoTrackCount}',
      'hasLocalVideo:${diagnostics.hasLocalVideo}',
      if (diagnostics.lastFailureReason != null)
        'lastFailureReason:${diagnostics.lastFailureReason!.name}',
    ],
    iceConnectionStates: diagnostics.iceConnectionStates,
    peerConnectionStates: diagnostics.peerConnectionStates,
    localCandidateCount: diagnostics.localCandidateCount,
    remoteCandidateCount: diagnostics.remoteCandidateCount,
    pendingRemoteCandidateCount: diagnostics.pendingRemoteCandidateCount,
    localAudioTrackCount: diagnostics.hasLocalAudio ? 1 : 0,
    remoteAudioTrackCount: diagnostics.remoteAudioTrackCount,
    localVideoTrackCount: diagnostics.hasLocalVideo ? 1 : 0,
    remoteVideoTrackCount: diagnostics.remoteVideoTrackCount,
    remoteStreamCount: diagnostics.remoteStreamCount,
    hasLocalAudio: diagnostics.hasLocalAudio,
    hasLocalVideo: diagnostics.hasLocalVideo,
    peerConnectionClosed: diagnostics.peerConnectionClosed,
    disposed: diagnostics.disposed,
    lastDetail: diagnostics.lastDetail,
    lastError: diagnostics.lastError,
    lastFailureReason: diagnostics.lastFailureReason?.name,
  );
}
