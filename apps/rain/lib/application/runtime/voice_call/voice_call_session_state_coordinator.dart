/// # voice_call_session_state_coordinator.dart
///
/// [VoiceCallSessionStateCoordinator] coordinates voice-call session state
/// projection and diagnostics without owning runtime fields. Manages session
/// phase transitions, terminal write outcomes, and diagnostic recording for
/// media and renderer state.
///
/// **Key types:** [VoiceCallSessionStateCoordinator]
///
/// **Depends on:** call media session coordinator, call retry policy, video call renderers, voice call state

import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';

import '../call_media_session_coordinator.dart';
import '../call_retry_policy.dart';
import '../video_call_renderers.dart';
import '../voice_audio_level.dart';
import '../voice_call_state.dart';
import 'voice_call_diagnostics.dart';
import 'voice_call_state_coordinator.dart';
import 'voice_call_terminal_reconciler.dart';

typedef VoiceCallSessionStateEventRecorder =
    void Function({
      required String category,
      required String name,
      String severity,
      String? message,
      Map<String, Object?> context,
    });

typedef VoiceCallSessionStateErrorRecorder =
    void Function(
      Object error,
      StackTrace? stackTrace, {
      required String source,
      required bool fatal,
      String? flutterLibrary,
      String? flutterContext,
    });

typedef VoiceCallTerminalWriteOutcome = ({bool durable, Object? error});

typedef VoiceCallTerminalRoomWriter =
    Future<VoiceCallTerminalWriteOutcome> Function({
      required String callId,
      required VoiceCallSignalingStatus status,
      required String detail,
      String? reasonCode,
    });

typedef VoiceCallSessionDiagnosticsRecorder =
    void Function({
      required String callId,
      required int sessionEpoch,
      required String peerId,
      required bool isOutgoing,
      required CallMediaMode mediaMode,
      required String failureCode,
      required String userMessage,
      required String nativeError,
      VoiceMediaDiagnostics? mediaDiagnostics,
      VideoCallRendererState? rendererState,
      String? cameraPermissionFailureDetail,
      Map<String, Object?> lockDiagnostics,
    });

/// Coordinates voice-call session state projection and diagnostics without
/// owning runtime fields.
final class VoiceCallSessionStateCoordinator {
  const VoiceCallSessionStateCoordinator();

  static const VoiceCallSessionStateCoordinator instance =
      VoiceCallSessionStateCoordinator();

  void applyVoiceSessionState(
    VoiceCallSession session,
    VoiceCallSessionState sessionState, {
    required bool isOutgoing,
    required bool Function(VoiceCallSession session) isLiveVoiceCallSession,
    required bool Function(VoiceCallSession session) isTerminalSessionLatched,
    required VoiceCallState Function() currentState,
    required void Function(VoiceCallSession session, String message)
    recordLateVoiceFrame,
    required VoiceCallFailureReason? Function(Object error)
    localMediaFailureReason,
    required String? Function(Object error) localMediaFailureDetail,
    required String Function(Object error) voiceCallErrorMessage,
    required void Function(VoiceCallState state) setVoiceCallState,
    required Future<void> Function(VoiceCallSession session)
    disposeVoiceCallSession,
    required VoiceSignalingAdapter? voiceSignalingAdapter,
    required String localUsername,
    required String Function(String username) normalizeUsername,
    required void Function(String callId, VoiceCallSignalingStatus status)
    recordRoomStatusTransition,
    required bool Function(Object error) isVoiceTerminalAlreadyClosedError,
    required void Function(
      Object error, {
      required String name,
      required Map<String, Object?> context,
    })
    recordTerminalAlreadyClosed,
    required Map<String, Object?> Function(VoiceCallState state) eventContext,
    required Future<void> Function(
      VoiceCallSession session, {
      required String detail,
      VoiceCallFailureReason? failureReason,
    })
    settleVoiceCallAfterTerminalRace,
    required void Function(Object error, StackTrace stackTrace)
    recordVoiceSignalingError,
    required Future<void> Function(
      VoiceCallSession session,
      VoiceCallSessionState state, {
      required bool isOutgoing,
      required String? detail,
      required VoiceCallFailureReason? failureReason,
    })
    finalizeFailedVoiceCallSession,
  }) {
    if (!isLiveVoiceCallSession(session)) {
      return;
    }
    final terminalDecision = VoiceCallTerminalReconciler.sessionStateDecision(
      terminalLatched: isTerminalSessionLatched(session),
      current: currentState(),
      callId: session.callId,
      sessionEpoch: session.sessionEpoch,
      incomingPhase: sessionState.phase,
    );
    if (!terminalDecision.shouldApply) {
      recordLateVoiceFrame(session, terminalDecision.ignoredReason!);
      return;
    }
    final mappedPhase = VoiceCallStateCoordinator.instance.mapSessionPhase(
      sessionState.phase,
    );
    final current = currentState();
    if (current.phase == VoiceCallPhase.failed &&
        current.callId == session.callId &&
        current.sessionEpoch == session.sessionEpoch &&
        mappedPhase == VoiceCallPhase.active) {
      recordLateVoiceFrame(session, 'ignored active state after failure');
      return;
    }
    final previous = current;
    final isSameCall =
        previous.callId == session.callId &&
        previous.sessionEpoch == session.sessionEpoch;
    final now = sessionState.updatedAt;
    final error = sessionState.error;
    final failureReason = VoiceCallStateCoordinator.instance
        .failureReasonForSessionState(
          sessionState,
          localMediaFailureReason: localMediaFailureReason,
        );
    final detail = VoiceCallStateCoordinator.instance.detailForSessionState(
      sessionState,
      localMediaFailureDetail: localMediaFailureDetail,
      errorMessage: voiceCallErrorMessage,
    );
    final startedAt = mappedPhase == VoiceCallPhase.active
        ? (isSameCall ? previous.startedAt : null) ?? now
        : isSameCall
        ? previous.startedAt
        : null;
    final keepsLocalAudioControls = mappedPhase == VoiceCallPhase.active;
    final mediaReconnecting =
        mappedPhase == VoiceCallPhase.active && sessionState.mediaReconnecting;

    if (mappedPhase == VoiceCallPhase.idle) {
      setVoiceCallState(const VoiceCallState.idle());
      unawaited(disposeVoiceCallSession(session));
      return;
    }

    setVoiceCallState(
      VoiceCallState(
        phase: mappedPhase,
        peerId: session.remotePeerId,
        callId: session.callId,
        sessionEpoch: session.sessionEpoch,
        mediaMode: sessionState.mediaMode,
        isOutgoing: isOutgoing,
        isMuted: isSameCall && previous.isMuted,
        isCameraMuted: isSameCall && previous.isCameraMuted,
        isDeafened:
            isSameCall && keepsLocalAudioControls && previous.isDeafened,
        isRemoteMuted: isSameCall && previous.isRemoteMuted,
        isRemoteCameraMuted: isSameCall && previous.isRemoteCameraMuted,
        hasLocalVideo: isSameCall && previous.hasLocalVideo,
        hasRemoteVideo: isSameCall && previous.hasRemoteVideo,
        videoFirstFrameTimedOut: isSameCall && previous.videoFirstFrameTimedOut,
        mediaReconnecting: mediaReconnecting,
        reconnectingSince: mediaReconnecting
            ? sessionState.reconnectingSince ?? previous.reconnectingSince
            : null,
        outputRoute: isSameCall && keepsLocalAudioControls
            ? previous.outputRoute
            : VoiceCallOutputRoute.systemDefault,
        outputRouteDeviceId: isSameCall && keepsLocalAudioControls
            ? previous.outputRouteDeviceId
            : null,
        outputRouteLabel: isSameCall && keepsLocalAudioControls
            ? previous.outputRouteLabel
            : null,
        outputRouteWarning: isSameCall && keepsLocalAudioControls
            ? previous.outputRouteWarning
            : null,
        startedAt: startedAt,
        updatedAt: now,
        detail: detail,
        error: error,
        failureReason: failureReason,
        audioLevel: VoiceAudioLevel.fromMedia(sessionState.audioLevel),
      ),
    );

    if (mappedPhase == VoiceCallPhase.active) {
      final voiceAdapter = voiceSignalingAdapter;
      if (voiceAdapter != null) {
        unawaited(
          voiceAdapter
              .markConnected(
                callId: session.callId,
                username: normalizeUsername(localUsername),
                connectedAt: now,
              )
              .then((_) {
                recordRoomStatusTransition(
                  session.callId,
                  VoiceCallSignalingStatus.connected,
                );
              })
              .catchError((Object error, StackTrace stackTrace) {
                if (isVoiceTerminalAlreadyClosedError(error)) {
                  recordTerminalAlreadyClosed(
                    error,
                    name: 'voice_mark_connected_after_terminal',
                    context: <String, Object?>{
                      ...eventContext(currentState()),
                      'callId': session.callId,
                      'sessionEpoch': session.sessionEpoch,
                    },
                  );
                  unawaited(
                    settleVoiceCallAfterTerminalRace(
                      session,
                      detail: 'Call ended.',
                    ),
                  );
                  return;
                }
                recordVoiceSignalingError(error, stackTrace);
              }),
        );
      }
    }

    if (mappedPhase == VoiceCallPhase.failed) {
      unawaited(
        finalizeFailedVoiceCallSession(
          session,
          sessionState,
          isOutgoing: isOutgoing,
          detail: detail,
          failureReason: failureReason,
        ),
      );
    }
  }

  Future<void> finalizeFailedVoiceCallSession(
    VoiceCallSession session,
    VoiceCallSessionState sessionState, {
    required bool isOutgoing,
    required String? detail,
    required VoiceCallFailureReason? failureReason,
    required String mediaFailedMessage,
    required String failedReasonCode,
    required String? Function(VoiceCallFailureReason? reason)
    reasonCodeForFailure,
    required VoiceCallTerminalRoomWriter writeTerminalRoomBeforeSessionHangup,
    required void Function(
      VoiceCallSession session,
      VoiceCallSessionState state, {
      required bool isOutgoing,
    })
    recordVoiceCallSessionFailure,
    required VoiceCallSessionStateEventRecorder recordRuntimeEvent,
    required Future<void> Function(VoiceCallSession session)
    disposeVoiceCallSession,
  }) async {
    final terminalDetail = detail ?? sessionState.detail ?? mediaFailedMessage;
    final terminalReasonCode =
        sessionState.reasonCode ??
        reasonCodeForFailure(failureReason) ??
        failedReasonCode;
    final terminalWrite = await writeTerminalRoomBeforeSessionHangup(
      callId: session.callId,
      status: VoiceCallSignalingStatus.failed,
      detail: terminalDetail,
      reasonCode: terminalReasonCode,
    );
    recordVoiceCallSessionFailure(
      session,
      sessionState,
      isOutgoing: isOutgoing,
    );
    if (!terminalWrite.durable) {
      recordRuntimeEvent(
        category: 'call',
        name: 'failed_session_terminal_write_not_durable',
        severity: 'error',
        message: terminalWrite.error?.toString(),
        context: <String, Object?>{
          'peerId': session.remotePeerId,
          'callId': session.callId,
          'sessionEpoch': session.sessionEpoch,
          'mediaMode': session.mediaMode.name,
          'reasonCode': terminalReasonCode,
        },
      );
    }
    await disposeVoiceCallSession(session);
  }

  void recordVoiceCallSessionFailure(
    VoiceCallSession session,
    VoiceCallSessionState state, {
    required bool isOutgoing,
    required VoiceCallFailureReason? Function(Object error)
    localMediaFailureReason,
    required String? Function(Object error) localMediaFailureDetail,
    required String Function(Object error) voiceCallErrorMessage,
    required String mediaFailedMessage,
    required VideoCallRendererState? lastVideoCallRendererState,
    required String? Function(Object? error, String? reasonCode)
    cameraPermissionFailureDetail,
    required VoiceCallSessionDiagnosticsRecorder recordVoiceCallDiagnostics,
  }) {
    final error = state.error;
    final localFailure = error == null ? null : localMediaFailureReason(error);
    if (localFailure == VoiceCallFailureReason.microphoneDenied) {
      return;
    }
    final detail =
        VoiceCallStateCoordinator.instance.detailForSessionState(
          state,
          localMediaFailureDetail: localMediaFailureDetail,
          errorMessage: voiceCallErrorMessage,
        ) ??
        mediaFailedMessage;
    final failureCode =
        state.reasonCode ??
        VoiceCallStateCoordinator.instance
            .failureReasonForSessionState(
              state,
              localMediaFailureReason: localMediaFailureReason,
            )
            ?.name ??
        'unknown';
    recordVoiceCallDiagnostics(
      callId: session.callId,
      sessionEpoch: session.sessionEpoch,
      peerId: session.remotePeerId,
      isOutgoing: isOutgoing,
      mediaMode: state.mediaMode,
      failureCode: failureCode,
      userMessage: detail,
      nativeError:
          error?.toString() ??
          state.mediaDiagnostics?.lastError ??
          state.mediaDiagnostics?.lastDetail ??
          state.detail ??
          'No native error captured.',
      mediaDiagnostics: state.mediaDiagnostics,
      rendererState: state.mediaMode == CallMediaMode.video
          ? lastVideoCallRendererState
          : null,
      cameraPermissionFailureDetail: cameraPermissionFailureDetail(
        error,
        state.reasonCode,
      ),
      lockDiagnostics: const <String, Object?>{},
    );
  }

  void recordVoiceCallRuntimeFailure(
    VoiceCallState state, {
    required String failureCode,
    required String userMessage,
    required String nativeError,
    required CallMediaDiagnostics? callMediaDiagnostics,
    required VoiceMediaDiagnostics? sessionMediaDiagnostics,
    required VideoCallRendererState? lastVideoCallRendererState,
    required VoiceCallSessionDiagnosticsRecorder recordVoiceCallDiagnostics,
  }) {
    final callId = state.callId;
    final peerId = state.peerId;
    final sessionEpoch = state.sessionEpoch;
    if (callId == null || peerId == null || sessionEpoch == null) {
      return;
    }
    recordVoiceCallDiagnostics(
      callId: callId,
      sessionEpoch: sessionEpoch,
      peerId: peerId,
      isOutgoing: state.isOutgoing,
      mediaMode: state.mediaMode,
      failureCode: failureCode,
      userMessage: userMessage,
      nativeError: nativeError,
      mediaDiagnostics: callMediaDiagnostics == null
          ? sessionMediaDiagnostics
          : voiceMediaDiagnosticsForCall(callMediaDiagnostics),
      rendererState: state.isVideo ? lastVideoCallRendererState : null,
      lockDiagnostics: const <String, Object?>{},
    );
  }

  void recordVoiceCallStartFailureDiagnostics({
    required Object error,
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required CallMediaMode mediaMode,
    required VoiceCallFailureReason? Function(CallRetryDecision? decision)
    failureReasonForRetryDecision,
    required String? Function(CallRetryDecision? decision)
    failureDetailForRetryDecision,
    required VoiceCallFailureReason? Function(Object error)
    failureReasonForError,
    required String? Function(Object error) failureDetailForError,
    required VoiceCallFailureReason? Function(Object error)
    localMediaFailureReason,
    required String? Function(Object error) localMediaFailureDetail,
    required String Function(Object error) voiceCallErrorMessage,
    required Map<String, Object?> Function({
      required String peerId,
      required String callId,
      required int sessionEpoch,
      CallRetryDecision? retryDecision,
      CallSignalingFailureSnapshot? retrySnapshot,
    })
    voiceCallLockDiagnostics,
    required VoiceCallSessionDiagnosticsRecorder recordVoiceCallDiagnostics,
    CallRetryDecision? retryDecision,
    CallSignalingFailureSnapshot? retrySnapshot,
  }) {
    final reason =
        failureReasonForRetryDecision(retryDecision) ??
        failureReasonForError(error) ??
        localMediaFailureReason(error);
    final detail =
        failureDetailForRetryDecision(retryDecision) ??
        failureDetailForError(error) ??
        localMediaFailureDetail(error) ??
        voiceCallErrorMessage(error);
    recordVoiceCallDiagnostics(
      callId: callId,
      sessionEpoch: sessionEpoch,
      peerId: peerId,
      isOutgoing: true,
      mediaMode: mediaMode,
      failureCode: reason?.name ?? retryDecision?.kind.name ?? 'unknown',
      userMessage: detail,
      nativeError: error.toString(),
      lockDiagnostics: voiceCallLockDiagnostics(
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        retryDecision: retryDecision,
        retrySnapshot: retrySnapshot,
      ),
    );
  }

  void recordVoiceCallDiagnostics({
    required String callId,
    required int sessionEpoch,
    required String peerId,
    required bool isOutgoing,
    required CallMediaMode mediaMode,
    required String failureCode,
    required String userMessage,
    required String nativeError,
    required String localUsername,
    required String Function(String username) normalizeUsername,
    required VoiceCallSessionStateErrorRecorder? errorRecorder,
    required List<String> Function(String callId) roomStatusTimeline,
    required int iceCandidateWriteCount,
    required String Function({
      required String failureCode,
      required String userMessage,
      required String nativeError,
    })
    failureTaxonomy,
    required String? Function(DateTime? value) isoTimestamp,
    required String? Function(String peerId) selectedCandidateRoute,
    VoiceMediaDiagnostics? mediaDiagnostics,
    VideoCallRendererState? rendererState,
    String? cameraPermissionFailureDetail,
    Map<String, Object?> lockDiagnostics = const <String, Object?>{},
  }) {
    final normalizedLocalUsername = normalizeUsername(localUsername);
    final remoteUsername = normalizeUsername(peerId);
    errorRecorder?.call(
      VoiceCallDiagnostics(
        callId: callId,
        sessionEpoch: sessionEpoch,
        peerId: remoteUsername,
        role: isOutgoing ? 'caller' : 'callee',
        mediaMode: mediaMode.name,
        caller: isOutgoing ? normalizedLocalUsername : remoteUsername,
        callee: isOutgoing ? remoteUsername : normalizedLocalUsername,
        failureCode: failureCode,
        userMessage: userMessage,
        sanitizedUiError: userMessage,
        nativeError: nativeError,
        roomStatusTimeline: roomStatusTimeline(callId),
        iceCandidateWriteCount: iceCandidateWriteCount,
        iceCandidateReadCount: mediaDiagnostics?.remoteCandidateCount ?? 0,
        relayFallbackAttempted:
            lockDiagnostics['relayFallbackAttempted'] == true,
        terminalWriteOutcome: lockDiagnostics['terminalWriteOutcome']
            ?.toString(),
        cleanupOutcome: lockDiagnostics['cleanupOutcome']?.toString(),
        presenceAgeAtStartMs: lockDiagnostics['presenceAgeAtStartMs'] is num
            ? (lockDiagnostics['presenceAgeAtStartMs']! as num).toInt()
            : null,
        mediaFailureReason: mediaDiagnostics?.lastFailureReason ?? failureCode,
        failureTaxonomy: failureTaxonomy(
          failureCode: failureCode,
          userMessage: userMessage,
          nativeError: nativeError,
        ),
        mediaStates: mediaDiagnostics?.mediaStates ?? const <String>[],
        iceStates: mediaDiagnostics?.iceConnectionStates ?? const <String>[],
        connectionStates:
            mediaDiagnostics?.peerConnectionStates ?? const <String>[],
        localCandidateCount: mediaDiagnostics?.localCandidateCount ?? 0,
        remoteCandidateCount: mediaDiagnostics?.remoteCandidateCount ?? 0,
        pendingRemoteCandidateCount:
            mediaDiagnostics?.pendingRemoteCandidateCount ?? 0,
        localAudioTrackCount: mediaDiagnostics?.localAudioTrackCount ?? 0,
        remoteAudioTrackCount: mediaDiagnostics?.remoteAudioTrackCount ?? 0,
        localVideoTrackCount: mediaDiagnostics?.localVideoTrackCount ?? 0,
        remoteVideoTrackCount: mediaDiagnostics?.remoteVideoTrackCount ?? 0,
        remoteStreamCount: mediaDiagnostics?.remoteStreamCount ?? 0,
        firstLocalVideoFrameAt: isoTimestamp(rendererState?.localFirstFrameAt),
        firstRemoteVideoFrameAt: isoTimestamp(
          rendererState?.remoteFirstFrameAt,
        ),
        selectedCandidateRoute: selectedCandidateRoute(peerId),
        cameraPermissionFailureDetail: cameraPermissionFailureDetail,
        lockClaimResult: lockDiagnostics['lockClaimResult']?.toString(),
        lockPath: lockDiagnostics['lockPath']?.toString(),
        pairId: lockDiagnostics['pairId']?.toString(),
        callerUserLock: lockDiagnostics['callerUserLock']?.toString(),
        calleeUserLock: lockDiagnostics['calleeUserLock']?.toString(),
        lockCallId: lockDiagnostics['lockCallId']?.toString(),
        lockExpiresAt: lockDiagnostics['lockExpiresAt'] is num
            ? (lockDiagnostics['lockExpiresAt']! as num).toInt()
            : null,
        lockWasReclaimed: lockDiagnostics['lockWasReclaimed'] is bool
            ? lockDiagnostics['lockWasReclaimed']! as bool
            : null,
        terminalRoomWasCleaned:
            lockDiagnostics['terminalRoomWasCleaned'] is bool
            ? lockDiagnostics['terminalRoomWasCleaned']! as bool
            : null,
        corruptRoomWasRepaired:
            lockDiagnostics['corruptRoomWasRepaired'] is bool
            ? lockDiagnostics['corruptRoomWasRepaired']! as bool
            : null,
        timestampRepair: lockDiagnostics['timestampRepair'] is bool
            ? lockDiagnostics['timestampRepair']! as bool
            : null,
      ),
      StackTrace.current,
      source: 'voice-call-media',
      fatal: false,
    );
  }

  void recordPeerUiStateSplitIfNeeded(
    VoiceCallState state, {
    required Session? Function(String peerId) getSession,
    required String? lastLoggedSignature,
    required void Function(String signature) setLastLoggedSignature,
    required VoiceCallSessionStateEventRecorder recordRuntimeEvent,
  }) {
    final peerId = state.peerId;
    if (peerId == null) {
      return;
    }
    final callSideIsTerminalOrRecovering =
        state.phase == VoiceCallPhase.failed || state.mediaReconnecting;
    if (!callSideIsTerminalOrRecovering) {
      return;
    }
    final session = getSession(peerId);
    if (session == null ||
        (session.state != SessionState.connected &&
            session.state != SessionState.reconnecting)) {
      return;
    }
    final signature = <Object?>[
      peerId,
      state.callId,
      state.sessionEpoch,
      state.phase,
      state.mediaReconnecting,
      state.failureReason,
      session.state,
      session.roomId,
    ].join('|');
    if (lastLoggedSignature == signature) {
      return;
    }
    setLastLoggedSignature(signature);
    recordRuntimeEvent(
      category: 'connection',
      name: 'peer_ui_state_split_detected',
      severity: 'warning',
      message:
          'Call state and peer data-session state require projected UI precedence.',
      context: <String, Object?>{
        'peerId': peerId,
        'callId': state.callId,
        'callPhase': state.phase.name,
        'callMediaReconnecting': state.mediaReconnecting,
        'failureReason': state.failureReason?.name,
        'sessionState': session.state.name,
        'sessionId': session.roomId,
      },
    );
  }
}
