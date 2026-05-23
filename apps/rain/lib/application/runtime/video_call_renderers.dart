import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

abstract class VideoCallRendererHandle {
  Future<void> initialize();
  MediaStream? get srcObject;
  set srcObject(MediaStream? stream);
  int? get textureId;
  set onFirstFrameRendered(void Function()? callback);
  Future<void> dispose();
}

abstract class VideoCallRendererFactory {
  VideoCallRendererHandle create();
}

final class RtcVideoCallRendererFactory implements VideoCallRendererFactory {
  const RtcVideoCallRendererFactory();

  @override
  VideoCallRendererHandle create() {
    return RtcVideoCallRendererHandle(RTCVideoRenderer());
  }
}

final class RtcVideoCallRendererHandle implements VideoCallRendererHandle {
  RtcVideoCallRendererHandle(this.renderer);

  final RTCVideoRenderer renderer;

  @override
  Future<void> initialize() => renderer.initialize();

  @override
  MediaStream? get srcObject => renderer.srcObject;

  @override
  set srcObject(MediaStream? stream) {
    renderer.srcObject = stream;
  }

  @override
  int? get textureId => renderer.textureId;

  @override
  set onFirstFrameRendered(void Function()? callback) {
    renderer.onFirstFrameRendered = callback;
  }

  @override
  Future<void> dispose() => renderer.dispose();
}

final class VideoCallRendererState {
  const VideoCallRendererState({
    this.localInitialized = false,
    this.remoteInitialized = false,
    this.hasLocalStream = false,
    this.hasRemoteStream = false,
    this.localFirstFrameRendered = false,
    this.remoteFirstFrameRendered = false,
    this.remoteFirstFrameTimedOut = false,
    this.localFirstFrameAt,
    this.remoteFirstFrameAt,
    this.remoteFirstFrameTimeoutAt,
  });

  final bool localInitialized;
  final bool remoteInitialized;
  final bool hasLocalStream;
  final bool hasRemoteStream;
  final bool localFirstFrameRendered;
  final bool remoteFirstFrameRendered;
  final bool remoteFirstFrameTimedOut;
  final DateTime? localFirstFrameAt;
  final DateTime? remoteFirstFrameAt;
  final DateTime? remoteFirstFrameTimeoutAt;

  VideoCallRendererState copyWith({
    bool? localInitialized,
    bool? remoteInitialized,
    bool? hasLocalStream,
    bool? hasRemoteStream,
    bool? localFirstFrameRendered,
    bool? remoteFirstFrameRendered,
    bool? remoteFirstFrameTimedOut,
    DateTime? localFirstFrameAt,
    DateTime? remoteFirstFrameAt,
    DateTime? remoteFirstFrameTimeoutAt,
    bool clearLocalFirstFrameAt = false,
    bool clearRemoteFirstFrameAt = false,
    bool clearRemoteFirstFrameTimeoutAt = false,
  }) {
    return VideoCallRendererState(
      localInitialized: localInitialized ?? this.localInitialized,
      remoteInitialized: remoteInitialized ?? this.remoteInitialized,
      hasLocalStream: hasLocalStream ?? this.hasLocalStream,
      hasRemoteStream: hasRemoteStream ?? this.hasRemoteStream,
      localFirstFrameRendered:
          localFirstFrameRendered ?? this.localFirstFrameRendered,
      remoteFirstFrameRendered:
          remoteFirstFrameRendered ?? this.remoteFirstFrameRendered,
      remoteFirstFrameTimedOut:
          remoteFirstFrameTimedOut ?? this.remoteFirstFrameTimedOut,
      localFirstFrameAt: clearLocalFirstFrameAt
          ? null
          : localFirstFrameAt ?? this.localFirstFrameAt,
      remoteFirstFrameAt: clearRemoteFirstFrameAt
          ? null
          : remoteFirstFrameAt ?? this.remoteFirstFrameAt,
      remoteFirstFrameTimeoutAt: clearRemoteFirstFrameTimeoutAt
          ? null
          : remoteFirstFrameTimeoutAt ?? this.remoteFirstFrameTimeoutAt,
    );
  }
}

final class VideoCallRenderers {
  VideoCallRenderers({
    VideoCallRendererFactory rendererFactory =
        const RtcVideoCallRendererFactory(),
    Duration remoteFirstFrameTimeout = const Duration(seconds: 8),
  }) : _rendererFactory = rendererFactory,
       _remoteFirstFrameTimeout = remoteFirstFrameTimeout;

  final VideoCallRendererFactory _rendererFactory;
  final Duration _remoteFirstFrameTimeout;
  final StreamController<VideoCallRendererState> _stateController =
      StreamController<VideoCallRendererState>.broadcast();

  VideoCallRendererHandle? _localRenderer;
  VideoCallRendererHandle? _remoteRenderer;
  VideoCallRendererState _state = const VideoCallRendererState();
  Timer? _remoteFirstFrameTimer;
  bool _initializing = false;
  bool _disposed = false;
  bool _stateClosed = false;

  Stream<VideoCallRendererState> get onStateChanged => _stateController.stream;

  VideoCallRendererState get state => _state;
  VideoCallRendererHandle? get localRenderer => _localRenderer;
  VideoCallRendererHandle? get remoteRenderer => _remoteRenderer;

  Future<void> ensureInitialized() async {
    _ensureNotDisposed();
    if (_state.localInitialized && _state.remoteInitialized) {
      return;
    }
    if (_initializing) {
      while (_initializing) {
        await Future<void>.delayed(Duration.zero);
      }
      _ensureNotDisposed();
      return;
    }
    _initializing = true;
    try {
      final local = _localRenderer ??= _rendererFactory.create();
      final remote = _remoteRenderer ??= _rendererFactory.create();
      await local.initialize();
      await remote.initialize();
      local.onFirstFrameRendered = _markLocalFirstFrameRendered;
      remote.onFirstFrameRendered = _markRemoteFirstFrameRendered;
      _setState(
        _state.copyWith(localInitialized: true, remoteInitialized: true),
      );
    } finally {
      _initializing = false;
    }
  }

  Future<void> attachLocalStream(MediaStream? stream) async {
    await ensureInitialized();
    _localRenderer!.srcObject = stream;
    _setState(
      _state.copyWith(
        hasLocalStream: stream != null,
        localFirstFrameRendered: false,
        clearLocalFirstFrameAt: true,
      ),
    );
  }

  Future<void> attachRemoteStream(MediaStream? stream) async {
    await ensureInitialized();
    _remoteFirstFrameTimer?.cancel();
    _remoteFirstFrameTimer = null;
    _remoteRenderer!.srcObject = stream;
    _setState(
      _state.copyWith(
        hasRemoteStream: stream != null,
        remoteFirstFrameRendered: false,
        remoteFirstFrameTimedOut: false,
        clearRemoteFirstFrameAt: true,
        clearRemoteFirstFrameTimeoutAt: true,
      ),
    );
    if (stream != null) {
      _remoteFirstFrameTimer = Timer(
        _remoteFirstFrameTimeout,
        _markRemoteFirstFrameTimedOut,
      );
    }
  }

  Future<void> clear() async {
    _remoteFirstFrameTimer?.cancel();
    _remoteFirstFrameTimer = null;
    _localRenderer?.srcObject = null;
    _remoteRenderer?.srcObject = null;
    _setState(
      _state.copyWith(
        hasLocalStream: false,
        hasRemoteStream: false,
        localFirstFrameRendered: false,
        remoteFirstFrameRendered: false,
        remoteFirstFrameTimedOut: false,
        clearLocalFirstFrameAt: true,
        clearRemoteFirstFrameAt: true,
        clearRemoteFirstFrameTimeoutAt: true,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await clear();
    final local = _localRenderer;
    final remote = _remoteRenderer;
    _localRenderer = null;
    _remoteRenderer = null;
    local?.onFirstFrameRendered = null;
    remote?.onFirstFrameRendered = null;
    await Future.wait(<Future<void>>[
      if (local != null) local.dispose(),
      if (remote != null) remote.dispose(),
    ]);
    if (!_stateClosed) {
      _stateClosed = true;
      await _stateController.close();
    }
  }

  void _markLocalFirstFrameRendered() {
    if (_disposed) {
      return;
    }
    _setState(
      _state.copyWith(
        localFirstFrameRendered: true,
        localFirstFrameAt: DateTime.now(),
      ),
    );
  }

  void _markRemoteFirstFrameRendered() {
    if (_disposed) {
      return;
    }
    _remoteFirstFrameTimer?.cancel();
    _remoteFirstFrameTimer = null;
    _setState(
      _state.copyWith(
        remoteFirstFrameRendered: true,
        remoteFirstFrameTimedOut: false,
        remoteFirstFrameAt: DateTime.now(),
        clearRemoteFirstFrameTimeoutAt: true,
      ),
    );
  }

  void _markRemoteFirstFrameTimedOut() {
    if (_disposed ||
        _state.remoteFirstFrameRendered ||
        !_state.hasRemoteStream) {
      return;
    }
    _setState(
      _state.copyWith(
        remoteFirstFrameTimedOut: true,
        remoteFirstFrameTimeoutAt: DateTime.now(),
      ),
    );
  }

  void _setState(VideoCallRendererState next) {
    _state = next;
    if (!_stateClosed) {
      _stateController.add(next);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Video call renderers have been disposed.');
    }
  }
}
