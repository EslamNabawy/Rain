/// # voice_call_media_coordinator.dart
///
/// [VoiceCallMediaCoordinator] coordinates voice/video media lifecycle
/// behavior without owning runtime state. Creates media connections, manages
/// local/remote video renderers, handles camera permission checks, and
/// provides bounded cleanup for media resources.
///
/// **Key types:** [VoiceCallMediaCoordinator]
///
/// **Depends on:** call media session coordinator, video call renderers, voice call state

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:protocol_brain/protocol_brain.dart';

import '../call_media_session_coordinator.dart';
import '../video_call_renderers.dart';
import '../voice_call_state.dart';

typedef VoiceCallMediaEventRecorder =
    void Function({
      required String category,
      required String name,
      String severity,
      String? message,
      Map<String, Object?> context,
    });

typedef VoiceCallMediaErrorRecorder =
    void Function(
      Object error,
      StackTrace? stackTrace, {
      required String source,
      required bool fatal,
      String? flutterLibrary,
      String? flutterContext,
    });

typedef VoiceCallMediaBoundedCleanup =
    Future<bool> Function(
      String step,
      Future<void> Function() cleanup, {
      Map<String, Object?> context,
    });

typedef VoiceCallRuntimeFailureRecorder =
    void Function(
      VoiceCallState state, {
      required String failureCode,
      required String userMessage,
      required String nativeError,
    });

typedef VoiceCallPeerEnder =
    Future<void> Function(
      String peerId, {
      required bool notifyPeer,
      required String detail,
      VoiceCallFailureReason? failureReason,
      String? failureDetail,
    });

/// Coordinates voice/video media lifecycle behavior without owning runtime
/// state.
final class VoiceCallMediaCoordinator {
  const VoiceCallMediaCoordinator();

  static const VoiceCallMediaCoordinator instance = VoiceCallMediaCoordinator();

  Future<VoiceMediaConnection> createVideoVoiceMediaConnection(
    SessionManager manager,
    String peerId, {
    required VideoCallRendererFactory rendererFactory,
    required Duration remoteFirstFrameTimeout,
    required VoiceCallMediaEventRecorder recordRuntimeEvent,
    required void Function(VideoCallRendererState?) setLastRendererState,
    required void Function(String?) setHandledFirstFrameTimeoutCallId,
    required void Function(String?) setLastLoggedRendererSignature,
    required void Function(CallMediaConnection?) setVideoCallMediaConnection,
    required void Function(VideoCallRenderers?) setVideoCallRenderers,
    required void Function(StreamSubscription<VideoCallRendererState>?)
    setVideoCallRendererSubscription,
    required void Function(VideoCallRendererState) handleRendererState,
    required void Function(String peerId, Object error, StackTrace stackTrace)
    handleRendererFailure,
    required VoiceCallMediaErrorRecorder? errorRecorder,
  }) async {
    final media = await manager.createCallMediaConnection(peerId);
    recordRuntimeEvent(
      category: 'call',
      name: 'video_media_connection_created',
      context: <String, Object?>{'peerId': peerId},
    );
    setLastRendererState(null);
    setHandledFirstFrameTimeoutCallId(null);
    setLastLoggedRendererSignature(null);
    setVideoCallMediaConnection(media);
    final renderers = VideoCallRenderers(
      rendererFactory: rendererFactory,
      remoteFirstFrameTimeout: remoteFirstFrameTimeout,
    );
    setVideoCallRenderers(renderers);
    setVideoCallRendererSubscription(
      renderers.onStateChanged.listen(
        handleRendererState,
        onError: (Object error, StackTrace stackTrace) {
          recordRuntimeEvent(
            category: 'call',
            name: 'video_renderer_stream_error',
            severity: 'error',
            message: error.toString(),
            context: <String, Object?>{'peerId': peerId},
          );
          handleRendererFailure(peerId, error, stackTrace);
        },
      ),
    );
    return VideoVoiceMediaConnection(
      media: media,
      renderers: renderers,
      kind: CallMediaKind.video,
      onRemoteTrackError: (Object error, StackTrace stackTrace) {
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'video-call-media',
          fatal: false,
        );
      },
      onRendererError: (Object error, StackTrace stackTrace) {
        handleRendererFailure(peerId, error, stackTrace);
      },
    );
  }

  Future<VoiceMediaConnection> createAudioVoiceMediaConnection(
    SessionManager manager,
    String peerId, {
    required VoiceCallMediaEventRecorder recordRuntimeEvent,
    required VoiceCallMediaErrorRecorder? errorRecorder,
  }) async {
    final media = await manager.createCallMediaConnection(peerId);
    recordRuntimeEvent(
      category: 'call',
      name: 'audio_call_media_connection_created',
      context: <String, Object?>{'peerId': peerId},
    );
    return CallVoiceMediaConnection(
      media: media,
      kind: CallMediaKind.audio,
      onRemoteTrackError: (Object error, StackTrace stackTrace) {
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'voice-call-media',
          fatal: false,
        );
      },
    );
  }

  void handleVideoRendererState(
    VideoCallRendererState rendererState, {
    required VoiceCallState currentState,
    required String? lastLoggedRendererSignature,
    required String? handledFirstFrameTimeoutCallId,
    required void Function(VideoCallRendererState?) setLastRendererState,
    required void Function(String?) setLastLoggedRendererSignature,
    required void Function(String?) setHandledFirstFrameTimeoutCallId,
    required VoiceCallMediaEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(VoiceCallState) eventContext,
    required String? Function(DateTime?) isoTimestamp,
    required void Function(VoiceCallState) setVoiceCallState,
    required int nowMs,
  }) {
    setLastRendererState(rendererState);
    final signature = <Object?>[
      rendererState.hasLocalStream,
      rendererState.hasRemoteStream,
      rendererState.localFirstFrameAt != null,
      rendererState.remoteFirstFrameAt != null,
      rendererState.remoteFirstFrameTimedOut,
    ].join('|');
    if (lastLoggedRendererSignature != signature) {
      setLastLoggedRendererSignature(signature);
      recordRuntimeEvent(
        category: 'call',
        name: 'video_renderer_state',
        context: <String, Object?>{
          ...eventContext(currentState),
          'hasLocalStream': rendererState.hasLocalStream,
          'hasRemoteStream': rendererState.hasRemoteStream,
          'localFirstFrameAt': isoTimestamp(rendererState.localFirstFrameAt),
          'remoteFirstFrameAt': isoTimestamp(rendererState.remoteFirstFrameAt),
          'remoteFirstFrameTimedOut': rendererState.remoteFirstFrameTimedOut,
        },
      );
    }
    final current = currentState;
    if (!current.hasCall || !current.isVideo) {
      return;
    }
    setVoiceCallState(
      current.copyWith(
        hasLocalVideo: rendererState.hasLocalStream,
        hasRemoteVideo: rendererState.hasRemoteStream,
        videoFirstFrameTimedOut: rendererState.remoteFirstFrameTimedOut,
        updatedAt: nowMs,
      ),
    );
    if (rendererState.remoteFirstFrameTimedOut &&
        current.phase == VoiceCallPhase.active &&
        !current.isRemoteCameraMuted &&
        current.callId != null &&
        handledFirstFrameTimeoutCallId != current.callId) {
      setHandledFirstFrameTimeoutCallId(current.callId);
      recordRuntimeEvent(
        category: 'call',
        name: 'video_first_frame_timeout_warning',
        severity: 'warning',
        message: 'Remote video stream attached but no rendered frame arrived.',
        context: eventContext(current),
      );
    }
  }

  void handleVideoRendererFailure(
    String peerId,
    Object error,
    StackTrace stackTrace, {
    required String Function(String) normalizeUsername,
    required VoiceCallState currentState,
    required VoiceCallMediaEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(VoiceCallState) eventContext,
    required VoiceCallMediaErrorRecorder? errorRecorder,
    required VoiceCallRuntimeFailureRecorder recordRuntimeFailure,
    required VoiceCallPeerEnder endVoiceCallForPeer,
    required String rendererFailedReasonCode,
    required String videoFailedMessage,
  }) {
    final normalizedPeerId = normalizeUsername(peerId);
    final current = currentState;
    final isCurrentLiveVideoCall =
        current.peerId == normalizedPeerId &&
        current.isVideo &&
        current.phase != VoiceCallPhase.idle &&
        current.phase != VoiceCallPhase.failed &&
        current.phase != VoiceCallPhase.ending &&
        current.phase != VoiceCallPhase.ended;
    final rendererTarget = error is VideoCallRendererException
        ? error.target.name
        : VideoCallRendererTarget.unknown.name;
    if (!isCurrentLiveVideoCall) {
      recordRuntimeEvent(
        category: 'call',
        name: 'stale_renderer_callback_ignored',
        severity: 'warning',
        message: error.toString(),
        context: <String, Object?>{
          'peerId': normalizedPeerId,
          'rendererTarget': rendererTarget,
          'currentPeerId': current.peerId,
          'currentCallId': current.callId,
          'currentPhase': current.phase.name,
        },
      );
      return;
    }
    recordRuntimeEvent(
      category: 'call',
      name: 'video_renderer_failed',
      severity: 'error',
      message: error.toString(),
      context: <String, Object?>{
        ...eventContext(current),
        'peerId': normalizedPeerId,
        'rendererTarget': rendererTarget,
      },
    );
    errorRecorder?.call(
      error,
      stackTrace,
      source: 'video-call-renderer',
      fatal: false,
    );
    recordRuntimeFailure(
      current,
      failureCode: rendererFailedReasonCode,
      userMessage: videoFailedMessage,
      nativeError: error.toString(),
    );
    if (error is VideoCallRendererException &&
        error.target == VideoCallRendererTarget.local) {
      return;
    }
    unawaited(
      endVoiceCallForPeer(
        normalizedPeerId,
        notifyPeer: true,
        detail: videoFailedMessage,
        failureReason: VoiceCallFailureReason.videoRendererFailed,
        failureDetail: videoFailedMessage,
      ),
    );
  }

  void handleVoiceCallAppLifecycleState(
    AppLifecycleState state, {
    required CallMediaConnection? videoCallMediaConnection,
    required VoiceCallState currentState,
    required VoiceCallMediaEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(VoiceCallState) eventContext,
    required VoiceCallRuntimeFailureRecorder recordRuntimeFailure,
    required VoiceCallPeerEnder endVoiceCallForPeer,
    required String failedReasonCode,
    required String videoBackgroundedMessage,
  }) {
    final interruptionType = switch (state) {
      AppLifecycleState.paused ||
      AppLifecycleState.detached => MediaInterruptionType.appPaused,
      AppLifecycleState.resumed => MediaInterruptionType.appResumed,
      AppLifecycleState.inactive || AppLifecycleState.hidden => null,
    };
    final media = videoCallMediaConnection;
    if (media != null && interruptionType != null) {
      unawaited(
        media.handleMediaInterruption(
          MediaInterruptionEvent(
            type: interruptionType,
            occurredAt: DateTime.now(),
            detail: state.name,
          ),
        ),
      );
    }
    if (state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached) {
      return;
    }
    final current = currentState;
    if (!current.hasCall ||
        !current.isVideo ||
        current.phase == VoiceCallPhase.failed ||
        current.phase == VoiceCallPhase.ending ||
        current.peerId == null ||
        current.callId == null) {
      return;
    }
    recordRuntimeEvent(
      category: 'call',
      name: 'video_call_backgrounded',
      severity: 'warning',
      context: <String, Object?>{
        ...eventContext(current),
        'lifecycleState': state.name,
      },
    );
    recordRuntimeFailure(
      current,
      failureCode: failedReasonCode,
      userMessage: videoBackgroundedMessage,
      nativeError: videoBackgroundedMessage,
    );
    unawaited(
      endVoiceCallForPeer(
        current.peerId!,
        notifyPeer: false,
        detail: videoBackgroundedMessage,
        failureReason: VoiceCallFailureReason.mediaConnectionFailed,
        failureDetail: videoBackgroundedMessage,
      ),
    );
  }

  Future<void> setVideoCallCameraMutedInSignaling(
    bool muted, {
    required VoiceCallState currentState,
    required VoiceSignalingAdapter Function() requireVoiceSignalingAdapter,
    required String username,
    required int updatedAt,
    required void Function(Object error, StackTrace stackTrace)
    recordVoiceSignalingError,
  }) async {
    final callId = currentState.callId;
    if (callId == null) {
      return;
    }
    try {
      await requireVoiceSignalingAdapter().setCameraMuted(
        callId: callId,
        username: username,
        cameraMuted: muted,
        updatedAt: updatedAt,
      );
    } catch (error, stackTrace) {
      recordVoiceSignalingError(error, stackTrace);
    }
  }

  Future<void> disposeVideoCallResources({
    required VideoCallRenderers? renderers,
    required CallMediaConnection? mediaConnection,
    required StreamSubscription<VideoCallRendererState>? rendererSubscription,
    required void Function(VideoCallRenderers?) setVideoCallRenderers,
    required void Function(CallMediaConnection?) setVideoCallMediaConnection,
    required void Function(StreamSubscription<VideoCallRendererState>?)
    setVideoCallRendererSubscription,
    required void Function(String?) setLastLoggedRendererSignature,
    required void Function(VideoCallRendererState?) setLastRendererState,
    required VoiceCallMediaBoundedCleanup runBoundedCleanupStep,
    required VoiceCallMediaEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(VoiceCallState) eventContext,
    required VoiceCallState currentState,
  }) async {
    if (renderers != null || mediaConnection != null) {
      recordRuntimeEvent(
        category: 'call',
        name: 'video_resources_dispose_started',
        context: eventContext(currentState),
      );
    }
    setVideoCallRenderers(null);
    setVideoCallMediaConnection(null);
    setLastLoggedRendererSignature(null);
    setVideoCallRendererSubscription(null);
    if (rendererSubscription != null) {
      await runBoundedCleanupStep(
        'video_renderer_subscription_cancel',
        rendererSubscription.cancel,
        context: eventContext(currentState),
      );
    }
    if (renderers == null) {
      return;
    }
    setLastRendererState(renderers.state);
    final disposed = await runBoundedCleanupStep(
      'video_resources_dispose',
      renderers.dispose,
      context: eventContext(currentState),
    );
    if (disposed) {
      recordRuntimeEvent(
        category: 'call',
        name: 'video_resources_disposed',
        context: eventContext(currentState),
      );
    }
  }
}
