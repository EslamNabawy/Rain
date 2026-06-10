import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';

import '../call_retry_policy.dart';
import '../call_terminal_write_policy.dart';
import '../voice_call_state.dart';
import 'voice_call_room_coordinator.dart';

typedef VoiceCallSignalingEventRecorder =
    void Function({
      required String category,
      required String name,
      String severity,
      String? message,
      Map<String, Object?> context,
    });

typedef VoiceCallSignalingErrorRecorder =
    void Function(
      Object error,
      StackTrace? stackTrace, {
      required String source,
      required bool fatal,
      String? flutterLibrary,
      String? flutterContext,
    });

typedef VoiceCallSignalingBoundedCleanup =
    Future<bool> Function(
      String step,
      Future<void> Function() cleanup, {
      Map<String, Object?> context,
    });

typedef VoiceIceCandidateWriteFailureRecorder =
    void Function(
      Object error,
      StackTrace stackTrace, {
      required String peerId,
      required String callId,
      required int sessionEpoch,
      required VoiceCallRole role,
      required int batchSize,
    });

typedef VoiceCallSignalingPeerEnder =
    Future<void> Function(
      String peerId, {
      required bool notifyPeer,
      required String detail,
      VoiceCallFailureReason? failureReason,
      String? failureDetail,
    });

typedef VoiceCallSignalingRuntimeFailureRecorder =
    void Function(
      VoiceCallState state, {
      required String failureCode,
      required String userMessage,
      required String nativeError,
    });

typedef VoiceCallLockDiagnosticsBuilder =
    Map<String, Object?> Function({
      required String peerId,
      required String callId,
      required int sessionEpoch,
      CallRetryDecision? retryDecision,
      CallSignalingFailureSnapshot? retrySnapshot,
      String? lockClaimResult,
    });

typedef VoiceFrameEncryptor =
    Future<VoiceSignalingEnvelope> Function(
      VoiceCallFrame frame, {
      required String purpose,
      required int maxCiphertextLength,
    });

final class VoiceCallSignalingTerminalWriteOutcome {
  const VoiceCallSignalingTerminalWriteOutcome._({
    required this.durable,
    this.error,
  });

  const VoiceCallSignalingTerminalWriteOutcome.durable()
    : this._(durable: true);

  const VoiceCallSignalingTerminalWriteOutcome.failed(Object? error)
    : this._(durable: false, error: error);

  final bool durable;
  final Object? error;
}

/// Coordinates signaling cleanup, terminal writes, and cleanup diagnostics
/// without owning runtime state.
final class VoiceCallSignalingCleanupCoordinator {
  const VoiceCallSignalingCleanupCoordinator();

  static const VoiceCallSignalingCleanupCoordinator instance =
      VoiceCallSignalingCleanupCoordinator();

  Future<void> cleanupStaleVoiceCallArtifacts(
    String reason, {
    required VoiceSignalingAdapter? voiceSignalingAdapter,
    required bool runtimeShutDown,
    required String username,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required VoiceCallSignalingErrorRecorder? errorRecorder,
  }) async {
    final voiceAdapter = voiceSignalingAdapter;
    if (voiceAdapter == null || runtimeShutDown) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final summary = await voiceAdapter.cleanupStaleVoiceCallArtifacts(
        username: username,
        now: now,
      );
      recordRuntimeEvent(
        category: 'call',
        name: 'voice_call_cleanup_janitor_completed',
        severity: summary.cleanedAny ? 'warning' : 'info',
        context: <String, Object?>{'reason': reason, ...summary.toJson()},
      );
    } catch (error, stackTrace) {
      recordRuntimeEvent(
        category: 'call',
        name: 'voice_call_cleanup_janitor_failed',
        severity: 'warning',
        message: error.toString(),
        context: <String, Object?>{'reason': reason},
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'voice-call-cleanup',
        fatal: false,
      );
    }
  }

  Future<void> watchFirebaseVoiceCall({
    required VoiceCallSession session,
    required String peerId,
    required bool isOutgoing,
    required VoiceSignalingAdapter Function() requireVoiceSignalingAdapter,
    required SignalingAdapter adapter,
    required String selfUsername,
    required List<StreamSubscription<dynamic>> subscriptions,
    required bool Function(VoiceCallSession session) isLiveVoiceCallSession,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required Future<void> Function({
      required VoiceCallSession session,
      required VoiceCallRoom room,
      required String peerId,
      required bool isOutgoing,
    })
    handleFirebaseVoiceRoomUpdate,
    required Future<void> Function({
      required VoiceCallSession session,
      required String peerId,
      required VoiceSignalingEnvelope envelope,
      required String purpose,
    })
    handleFirebaseVoiceEnvelope,
    required void Function(
      VoiceCallSession session,
      String peerId,
      Object error,
      StackTrace stackTrace,
    )
    handleVoiceSignalingStreamError,
    required String Function(VoiceCallRole role) voiceIcePurpose,
  }) async {
    final voiceAdapter = requireVoiceSignalingAdapter();
    final remoteRole = isOutgoing ? VoiceCallRole.callee : VoiceCallRole.caller;
    await adapter.ensureSignedInAs(selfUsername);
    recordRuntimeEvent(
      category: 'call',
      name: 'firebase_watch_started',
      context: <String, Object?>{
        'peerId': peerId,
        'callId': session.callId,
        'sessionEpoch': session.sessionEpoch,
        'isOutgoing': isOutgoing,
        'remoteRole': remoteRole.name,
      },
    );

    subscriptions.add(
      voiceAdapter
          .watchCall(session.callId)
          .listen(
            (VoiceCallRoom? room) async {
              if (room == null || !isLiveVoiceCallSession(session)) {
                return;
              }
              recordRuntimeEvent(
                category: 'call',
                name: 'firebase_room_update',
                context: <String, Object?>{
                  'peerId': peerId,
                  'callId': room.callId,
                  'sessionEpoch': session.sessionEpoch,
                  'status': room.status.name,
                  'reasonCode': room.reasonCode,
                  'endedBy': room.endedBy,
                  'mediaMode': room.mediaMode.name,
                },
              );
              await handleFirebaseVoiceRoomUpdate(
                session: session,
                room: room,
                peerId: peerId,
                isOutgoing: isOutgoing,
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              handleVoiceSignalingStreamError(
                session,
                peerId,
                error,
                stackTrace,
              );
            },
          ),
    );
    subscriptions.add(
      voiceAdapter
          .watchVoiceOffer(session.callId)
          .listen(
            (VoiceSignalingEnvelope envelope) async {
              await handleFirebaseVoiceEnvelope(
                session: session,
                peerId: peerId,
                envelope: envelope,
                purpose: SignalingCipher.offerPurpose,
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              handleVoiceSignalingStreamError(
                session,
                peerId,
                error,
                stackTrace,
              );
            },
          ),
    );
    subscriptions.add(
      voiceAdapter
          .watchVoiceAnswer(session.callId)
          .listen(
            (VoiceSignalingEnvelope envelope) async {
              await handleFirebaseVoiceEnvelope(
                session: session,
                peerId: peerId,
                envelope: envelope,
                purpose: SignalingCipher.answerPurpose,
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              handleVoiceSignalingStreamError(
                session,
                peerId,
                error,
                stackTrace,
              );
            },
          ),
    );
    subscriptions.add(
      voiceAdapter
          .watchIceCandidates(callId: session.callId, role: remoteRole)
          .listen(
            (VoiceCallIceCandidateRecord record) async {
              await handleFirebaseVoiceEnvelope(
                session: session,
                peerId: peerId,
                envelope: record.envelope,
                purpose: voiceIcePurpose(remoteRole),
              );
            },
            onError: (Object error, StackTrace stackTrace) {
              handleVoiceSignalingStreamError(
                session,
                peerId,
                error,
                stackTrace,
              );
            },
          ),
    );
  }

  void handleVoiceSignalingStreamError(
    VoiceCallSession session,
    String peerId,
    Object error,
    StackTrace stackTrace, {
    required void Function(Object error, StackTrace stackTrace)
    recordVoiceSignalingError,
    required bool Function(VoiceCallSession session) isLiveVoiceCallSession,
    required bool Function(VoiceCallSession session) isTerminalSessionLatched,
    required VoiceCallState currentState,
    required VoiceCallSignalingPeerEnder endVoiceCallForPeer,
    required String signalingFailedMessage,
  }) {
    recordVoiceSignalingError(error, stackTrace);
    if (!isLiveVoiceCallSession(session) || isTerminalSessionLatched(session)) {
      return;
    }
    final current = currentState;
    if (current.callId != session.callId ||
        current.sessionEpoch != session.sessionEpoch ||
        current.phase == VoiceCallPhase.idle ||
        current.phase == VoiceCallPhase.failed ||
        current.phase == VoiceCallPhase.ending) {
      return;
    }
    unawaited(
      endVoiceCallForPeer(
        peerId,
        notifyPeer: false,
        detail: signalingFailedMessage,
        failureReason: VoiceCallFailureReason.signalingFailed,
        failureDetail: signalingFailedMessage,
      ),
    );
  }

  Future<void> handleFirebaseVoiceRoomUpdate({
    required VoiceCallSession session,
    required VoiceCallRoom room,
    required String peerId,
    required bool isOutgoing,
    required bool Function(VoiceCallSession session) isLiveVoiceCallSession,
    required void Function(VoiceCallSession session, String message)
    recordLateVoiceFrame,
    required void Function(String callId, VoiceCallSignalingStatus status)
    recordRoomStatusTransition,
    required String localUsername,
    required String Function(String username) normalizeUsername,
    required VoiceCallState Function() currentState,
    required void Function(VoiceCallState state) setVoiceCallState,
    required Future<void> Function({
      required VoiceCallSession session,
      required VoiceCallRoom room,
      required String peerId,
    })
    reconcileTerminalVoiceRoom,
  }) async {
    if (!isLiveVoiceCallSession(session) || room.callId != session.callId) {
      return;
    }
    if (room.createdAt != session.sessionEpoch) {
      recordLateVoiceFrame(
        session,
        'ignored room update for stale epoch ${room.createdAt}',
      );
      return;
    }
    recordRoomStatusTransition(room.callId, room.status);
    final normalizedLocalUsername = normalizeUsername(localUsername);
    final remoteMuted = room.muted[peerId];
    if (remoteMuted != null && currentState().isRemoteMuted != remoteMuted) {
      setVoiceCallState(
        currentState().copyWith(
          isRemoteMuted: remoteMuted,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    final remoteCameraMuted = room.cameraMuted[peerId];
    if (remoteCameraMuted != null &&
        currentState().isRemoteCameraMuted != remoteCameraMuted) {
      setVoiceCallState(
        currentState().copyWith(
          isRemoteCameraMuted: remoteCameraMuted,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }

    switch (room.status) {
      case VoiceCallSignalingStatus.ringing:
      case VoiceCallSignalingStatus.negotiating:
      case VoiceCallSignalingStatus.connected:
        break;
      case VoiceCallSignalingStatus.accepted:
        if (isOutgoing) {
          await session.handleFrame(
            VoiceCallFrame(
              type: VoiceCallFrameType.accept,
              callId: room.callId,
              from: peerId,
              to: normalizedLocalUsername,
              sentAt: room.acceptedAt ?? room.updatedAt,
              seq: 1,
              sessionEpoch: room.createdAt,
            ),
          );
        }
        break;
      case VoiceCallSignalingStatus.ended:
      case VoiceCallSignalingStatus.failed:
      case VoiceCallSignalingStatus.expired:
        await reconcileTerminalVoiceRoom(
          session: session,
          room: room,
          peerId: peerId,
        );
        break;
    }
  }

  Future<void> reconcileTerminalVoiceRoom({
    required VoiceCallSession session,
    required VoiceCallRoom room,
    required String peerId,
    required bool Function(VoiceCallSession session) isLiveVoiceCallSession,
    required void Function(VoiceCallSession session) latchTerminalSession,
    required bool Function(VoiceCallSession session) isTerminalSessionLatched,
    required VoiceCallState currentState,
    required String localUsername,
    required String Function(String username) normalizeUsername,
    required String Function(VoiceCallRoom room, String localUser)
    terminalRoomDetail,
    required VoiceCallFailureReason? Function(VoiceCallRoom room)
    terminalRoomFailureReason,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(VoiceCallState state) eventContext,
    required String? Function(VoiceCallFailureReason? reason)
    reasonCodeForFailure,
    required String failedReasonCode,
    required VoiceCallSignalingRuntimeFailureRecorder recordRuntimeFailure,
    required Future<void> Function(
      VoiceCallSession session, {
      required String detail,
      VoiceCallFailureReason? failureReason,
    })
    settleVoiceCallAfterTerminalRace,
  }) async {
    if (!room.status.isTerminal || !isLiveVoiceCallSession(session)) {
      return;
    }
    latchTerminalSession(session);
    final current = currentState;
    if (current.callId != room.callId ||
        current.sessionEpoch != room.createdAt ||
        current.phase == VoiceCallPhase.idle ||
        current.phase == VoiceCallPhase.failed) {
      return;
    }
    final normalizedLocalUsername = normalizeUsername(localUsername);
    final endedByLocal = room.endedBy == normalizedLocalUsername;
    final detail = terminalRoomDetail(room, normalizedLocalUsername);
    final failureReason = terminalRoomFailureReason(room);
    if (endedByLocal &&
        isTerminalSessionLatched(session) &&
        (current.phase == VoiceCallPhase.ending ||
            current.phase == VoiceCallPhase.ended)) {
      recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_room_local_echo_ignored',
        severity: 'info',
        message: 'Local terminal Firebase room echoed during local hangup.',
        context: <String, Object?>{
          ...eventContext(current),
          'status': room.status.name,
          'endedBy': room.endedBy,
          'reasonCode': room.reasonCode,
        },
      );
      return;
    }
    recordRuntimeEvent(
      category: 'call',
      name: endedByLocal
          ? 'voice_terminal_room_forced_reconcile'
          : 'voice_remote_terminal_room_reconciled',
      severity: endedByLocal ? 'warning' : 'info',
      message: endedByLocal
          ? 'Terminal Firebase room left the local voice session live.'
          : 'Remote terminal Firebase room ended the local voice session.',
      context: <String, Object?>{
        ...eventContext(current),
        'status': room.status.name,
        'endedBy': room.endedBy,
        'reasonCode': room.reasonCode,
      },
    );
    if (failureReason != null) {
      recordRuntimeFailure(
        current,
        failureCode:
            reasonCodeForFailure(failureReason) ??
            room.reasonCode ??
            failedReasonCode,
        userMessage: detail,
        nativeError: room.reason ?? detail,
      );
    }
    await settleVoiceCallAfterTerminalRace(
      session,
      detail: detail,
      failureReason: failureReason,
    );
  }

  Future<void> handleFirebaseVoiceEnvelope({
    required VoiceCallSession session,
    required String peerId,
    required VoiceSignalingEnvelope envelope,
    required String purpose,
    required bool Function(VoiceCallSession session) isLiveVoiceCallSession,
    required Future<VoiceCallFrame> Function({
      required String callId,
      required VoiceSignalingEnvelope envelope,
      required String purpose,
    })
    decryptVoiceFrame,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(String peerId, VoiceCallFrame frame)
    frameEventContext,
    required void Function(VoiceCallSession session, String message)
    recordLateVoiceFrame,
    required String Function(String username) normalizeUsername,
    required String localUsername,
    required void Function(Object error, StackTrace stackTrace)
    recordVoiceSignalingError,
    required Future<void> Function(
      Object error, {
      VoiceCallFailureReason? failureReason,
      String? detail,
    })
    failVoiceCall,
    required String mediaFailedMessage,
  }) async {
    if (!isLiveVoiceCallSession(session)) {
      return;
    }
    try {
      final frame = await decryptVoiceFrame(
        callId: session.callId,
        envelope: envelope,
        purpose: purpose,
      );
      recordRuntimeEvent(
        category: 'call',
        name: 'firebase_frame_received',
        context: <String, Object?>{
          ...frameEventContext(peerId, frame),
          'purpose': purpose,
        },
      );
      if (!isLiveVoiceCallSession(session)) {
        recordLateVoiceFrame(
          session,
          'late decrypted ${frame.type.name} frame after call moved on',
        );
        return;
      }
      if (frame.callId != session.callId ||
          frame.sessionEpoch != session.sessionEpoch) {
        recordLateVoiceFrame(
          session,
          'late ${frame.type.name} frame for '
          '${frame.callId}/${frame.sessionEpoch}',
        );
        return;
      }
      if (normalizeUsername(frame.from) == normalizeUsername(localUsername)) {
        return;
      }
      if (normalizeUsername(frame.from) != normalizeUsername(peerId)) {
        return;
      }
      await session.handleFrame(frame);
    } catch (error, stackTrace) {
      recordRuntimeEvent(
        category: 'call',
        name: 'firebase_frame_failed',
        severity: 'error',
        message: error.toString(),
        context: <String, Object?>{
          'peerId': peerId,
          'callId': session.callId,
          'sessionEpoch': session.sessionEpoch,
          'purpose': purpose,
        },
      );
      recordVoiceSignalingError(error, stackTrace);
      if (!isLiveVoiceCallSession(session)) {
        recordLateVoiceFrame(
          session,
          'ignored signaling error after call moved on: $error',
        );
        return;
      }
      await failVoiceCall(
        error,
        failureReason: VoiceCallFailureReason.mediaConnectionFailed,
        detail: mediaFailedMessage,
      );
    }
  }

  Future<void> sendVoiceFrameObject(
    String peerId,
    VoiceCallFrame frame, {
    required VoiceSignalingAdapter Function() requireVoiceSignalingAdapter,
    required String localUsername,
    required String Function(String username) normalizeUsername,
    required Duration voiceCallExpiry,
    required Duration transientCreateRetryDelay,
    required String busyReasonCode,
    required String rejectedReasonCode,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(String peerId, VoiceCallFrame frame)
    frameEventContext,
    required Future<bool> Function({
      required VoiceSignalingAdapter voiceAdapter,
      required String peerId,
      required VoiceCallFrame frame,
    })
    shouldSkipTerminalSensitiveVoiceFrame,
    required VoiceCallLockDiagnosticsBuilder voiceCallLockDiagnostics,
    required CallSignalingFailureSnapshot? Function(
      Object error, {
      String? peerId,
    })
    signalingFailureSnapshotForError,
    required bool Function(Object error, CallRetryDecision? decision)
    shouldRetryTransientCreateFailure,
    required void Function(String callId, VoiceCallSignalingStatus status)
    recordRoomStatusTransition,
    required VoiceFrameEncryptor encryptVoiceFrame,
    required Future<void> Function({
      required VoiceSignalingAdapter voiceAdapter,
      required String peerId,
      required VoiceCallFrame frame,
    })
    queueVoiceIceCandidate,
  }) async {
    final voiceAdapter = requireVoiceSignalingAdapter();
    final normalizedLocalUsername = normalizeUsername(localUsername);
    final now = DateTime.now().millisecondsSinceEpoch;
    recordRuntimeEvent(
      category: 'call',
      name: 'firebase_frame_send_started',
      context: frameEventContext(peerId, frame),
    );
    if (await shouldSkipTerminalSensitiveVoiceFrame(
      voiceAdapter: voiceAdapter,
      peerId: peerId,
      frame: frame,
    )) {
      return;
    }
    switch (frame.type) {
      case VoiceCallFrameType.invite:
        final callee = normalizeUsername(peerId);
        final lockContext = voiceCallLockDiagnostics(
          peerId: callee,
          callId: frame.callId,
          sessionEpoch: frame.sessionEpoch,
          lockClaimResult: 'started',
        );
        Future<void> createOutgoingRoom() async {
          final room = await voiceAdapter.createOutgoingCall(
            callId: frame.callId,
            caller: normalizedLocalUsername,
            callee: callee,
            createdAt: frame.sessionEpoch,
            expiresAt: frame.sessionEpoch + voiceCallExpiry.inMilliseconds,
            mediaMode: frame.mediaMode,
          );
          recordRoomStatusTransition(frame.callId, room.status);
        }

        recordRuntimeEvent(
          category: 'call',
          name: 'voice_lock_claim_started',
          context: <String, Object?>{
            ...frameEventContext(peerId, frame),
            ...lockContext,
          },
        );
        try {
          await createOutgoingRoom();
        } catch (error) {
          final retrySnapshot = signalingFailureSnapshotForError(
            error,
            peerId: callee,
          );
          final retryDecision = retrySnapshot == null
              ? null
              : CallRetryPolicy.classifySignalingFailure(retrySnapshot);
          final failedLockContext = voiceCallLockDiagnostics(
            peerId: callee,
            callId: frame.callId,
            sessionEpoch: frame.sessionEpoch,
            retryDecision: retryDecision,
            retrySnapshot: retrySnapshot,
          );
          final eventContext = <String, Object?>{
            ...frameEventContext(peerId, frame),
            ...failedLockContext,
            if (retryDecision != null)
              'canRetryImmediately': retryDecision.canRetryImmediately,
          };
          if (retryDecision?.kind == CallRetryDecisionKind.cleanedStaleState) {
            recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_reclaim_completed',
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: eventContext,
            );
            recordRuntimeEvent(
              category: 'call',
              name: 'stale_voice_lock_repaired',
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: eventContext,
            );
            if (failedLockContext['timestampRepair'] == true) {
              recordRuntimeEvent(
                category: 'call',
                name: 'voice_room_timestamp_repaired',
                severity: 'warning',
                message: retryDecision?.userMessage,
                context: eventContext,
              );
            }
            if (retryDecision?.canRetryImmediately == true) {
              try {
                await createOutgoingRoom();
                recordRuntimeEvent(
                  category: 'call',
                  name: 'voice_lock_claim_retried',
                  severity: 'info',
                  message: retryDecision?.userMessage,
                  context: <String, Object?>{
                    ...eventContext,
                    'retryResult': 'claimed',
                  },
                );
                return;
              } catch (retryError, retryStackTrace) {
                recordRuntimeEvent(
                  category: 'call',
                  name: 'voice_lock_claim_retry_failed',
                  severity: 'warning',
                  message: retryError.toString(),
                  context: <String, Object?>{
                    ...eventContext,
                    'retryResult': 'failed',
                  },
                );
                Error.throwWithStackTrace(retryError, retryStackTrace);
              }
            }
          } else if (shouldRetryTransientCreateFailure(error, retryDecision)) {
            recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_claim_transient_retry_started',
              severity: 'warning',
              message: retryDecision?.userMessage ?? error.toString(),
              context: <String, Object?>{
                ...eventContext,
                'retryDelayMs': transientCreateRetryDelay.inMilliseconds,
              },
            );
            await Future<void>.delayed(transientCreateRetryDelay);
            try {
              await createOutgoingRoom();
              recordRuntimeEvent(
                category: 'call',
                name: 'voice_lock_claim_retried',
                severity: 'info',
                message: retryDecision?.userMessage,
                context: <String, Object?>{
                  ...eventContext,
                  'retryResult': 'claimed',
                  'retryReason': 'transientFirebaseCreateFailure',
                },
              );
              return;
            } catch (retryError, retryStackTrace) {
              recordRuntimeEvent(
                category: 'call',
                name: 'voice_lock_claim_retry_failed',
                severity: 'warning',
                message: retryError.toString(),
                context: <String, Object?>{
                  ...eventContext,
                  'retryResult': 'failed',
                  'retryReason': 'transientFirebaseCreateFailure',
                },
              );
              Error.throwWithStackTrace(retryError, retryStackTrace);
            }
          } else if (retryDecision?.kind ==
              CallRetryDecisionKind.cleanupInProgress) {
            recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_reclaim_started',
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: eventContext,
            );
          } else if (retryDecision?.kind == CallRetryDecisionKind.peerOffline) {
            final presenceMessage =
                (retryDecision?.userMessage ?? error.toString()).toLowerCase();
            final presenceEventName =
                presenceMessage.contains('could not confirm') ||
                    presenceMessage.contains('presence unknown')
                ? 'call_start_presence_unknown'
                : 'call_start_blocked_offline';
            recordRuntimeEvent(
              category: 'call',
              name: presenceEventName,
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: <String, Object?>{
                ...eventContext,
                'presenceSource': 'signaling',
              },
            );
            recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_claim_blocked',
              severity: 'warning',
              message: retryDecision?.userMessage ?? error.toString(),
              context: eventContext,
            );
          } else if (retryDecision?.kind == CallRetryDecisionKind.peerBusy) {
            recordRuntimeEvent(
              category: 'call',
              name: 'voice_real_busy_lock',
              severity: 'warning',
              message: retryDecision?.userMessage,
              context: eventContext,
            );
            recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_claim_blocked',
              severity: 'warning',
              message: retryDecision?.userMessage ?? error.toString(),
              context: eventContext,
            );
          } else {
            recordRuntimeEvent(
              category: 'call',
              name: 'voice_lock_claim_blocked',
              severity: 'warning',
              message: retryDecision?.userMessage ?? error.toString(),
              context: eventContext,
            );
          }
          rethrow;
        }
        break;
      case VoiceCallFrameType.accept:
        await voiceAdapter.acceptCall(
          callId: frame.callId,
          callee: normalizedLocalUsername,
          acceptedAt: now,
        );
        recordRoomStatusTransition(
          frame.callId,
          VoiceCallSignalingStatus.accepted,
        );
        break;
      case VoiceCallFrameType.reject:
      case VoiceCallFrameType.busy:
        await voiceAdapter.endCall(
          callId: frame.callId,
          username: normalizedLocalUsername,
          status: VoiceCallSignalingStatus.failed,
          endedAt: now,
          reasonCode:
              frame.reasonCode ??
              (frame.type == VoiceCallFrameType.busy
                  ? busyReasonCode
                  : rejectedReasonCode),
          reason: frame.reason,
        );
        recordRoomStatusTransition(
          frame.callId,
          VoiceCallSignalingStatus.failed,
        );
        break;
      case VoiceCallFrameType.hangup:
        final existingRoom = await voiceAdapter.fetchCall(frame.callId);
        if (existingRoom?.status.isTerminal == true) {
          recordRuntimeEvent(
            category: 'call',
            name: 'voice_late_hangup_frame_ignored',
            severity: 'info',
            message: 'Late hangup frame ignored after terminal room state.',
            context: <String, Object?>{
              ...frameEventContext(peerId, frame),
              'status': existingRoom?.status.name,
              'endedBy': existingRoom?.endedBy,
            },
          );
          break;
        }
        await voiceAdapter.endCall(
          callId: frame.callId,
          username: normalizedLocalUsername,
          status: frame.reasonCode == null
              ? VoiceCallSignalingStatus.ended
              : VoiceCallSignalingStatus.failed,
          endedAt: now,
          reasonCode: frame.reasonCode,
          reason: frame.reason,
        );
        recordRoomStatusTransition(
          frame.callId,
          frame.reasonCode == null
              ? VoiceCallSignalingStatus.ended
              : VoiceCallSignalingStatus.failed,
        );
        break;
      case VoiceCallFrameType.offer:
        await voiceAdapter.writeVoiceOffer(
          callId: frame.callId,
          caller: normalizedLocalUsername,
          offer: await encryptVoiceFrame(
            frame,
            purpose: SignalingCipher.offerPurpose,
            maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
          ),
          updatedAt: now,
        );
        break;
      case VoiceCallFrameType.answer:
        await voiceAdapter.writeVoiceAnswer(
          callId: frame.callId,
          callee: normalizedLocalUsername,
          answer: await encryptVoiceFrame(
            frame,
            purpose: SignalingCipher.answerPurpose,
            maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
          ),
          updatedAt: now,
        );
        break;
      case VoiceCallFrameType.candidate:
        await queueVoiceIceCandidate(
          voiceAdapter: voiceAdapter,
          peerId: peerId,
          frame: frame,
        );
        break;
      case VoiceCallFrameType.mute:
        if (frame.muted != null) {
          await voiceAdapter.setMuted(
            callId: frame.callId,
            username: normalizedLocalUsername,
            muted: frame.muted!,
            updatedAt: now,
          );
        }
        if (frame.cameraMuted != null) {
          await voiceAdapter.setCameraMuted(
            callId: frame.callId,
            username: normalizedLocalUsername,
            cameraMuted: frame.cameraMuted!,
            updatedAt: now,
          );
        }
        break;
    }
    recordRuntimeEvent(
      category: 'call',
      name: 'firebase_frame_send_completed',
      context: frameEventContext(peerId, frame),
    );
  }

  Future<bool> shouldSkipTerminalSensitiveVoiceFrame({
    required VoiceSignalingAdapter voiceAdapter,
    required String peerId,
    required VoiceCallFrame frame,
    required VoiceCallSession? currentSession,
    required bool Function(VoiceCallSession session) isTerminalSessionLatched,
    required void Function(VoiceCallSession session, String message)
    recordLateVoiceFrame,
    required bool Function(VoiceCallFrameType type)
    requiresTerminalVoiceRoomPreflight,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required Map<String, Object?> Function(String peerId, VoiceCallFrame frame)
    frameEventContext,
    required Future<void> Function({
      required VoiceCallSession session,
      required VoiceCallRoom room,
      required String peerId,
    })
    reconcileTerminalVoiceRoom,
  }) async {
    final session = currentSession;
    if (session != null &&
        session.callId == frame.callId &&
        session.sessionEpoch == frame.sessionEpoch &&
        isTerminalSessionLatched(session)) {
      recordLateVoiceFrame(
        session,
        'ignored ${frame.type.name} send after terminal room latch',
      );
      return true;
    }

    if (!requiresTerminalVoiceRoomPreflight(frame.type)) {
      return false;
    }

    final room = await voiceAdapter.fetchCall(frame.callId);
    if (room == null) {
      recordRuntimeEvent(
        category: 'call',
        name: 'voice_late_media_frame_ignored_after_terminal',
        severity: 'info',
        message: 'Voice media signaling frame ignored after room cleanup.',
        context: <String, Object?>{
          ...frameEventContext(peerId, frame),
          'roomStatus': 'missing',
        },
      );
      return true;
    }
    if (!room.status.isTerminal) {
      return false;
    }

    recordRuntimeEvent(
      category: 'call',
      name: 'voice_late_media_frame_ignored_after_terminal',
      severity: 'info',
      message: 'Voice media signaling frame ignored after terminal room state.',
      context: <String, Object?>{
        ...frameEventContext(peerId, frame),
        'roomStatus': room.status.name,
        'endedBy': room.endedBy,
        'reasonCode': room.reasonCode,
      },
    );
    if (session != null &&
        session.callId == frame.callId &&
        session.sessionEpoch == frame.sessionEpoch) {
      await reconcileTerminalVoiceRoom(
        session: session,
        room: room,
        peerId: peerId,
      );
    }
    return true;
  }

  bool requiresTerminalVoiceRoomPreflight(VoiceCallFrameType type) {
    return switch (type) {
      VoiceCallFrameType.accept ||
      VoiceCallFrameType.offer ||
      VoiceCallFrameType.answer ||
      VoiceCallFrameType.mute => true,
      VoiceCallFrameType.invite ||
      VoiceCallFrameType.reject ||
      VoiceCallFrameType.busy ||
      VoiceCallFrameType.hangup ||
      VoiceCallFrameType.candidate => false,
    };
  }

  Future<void> queueVoiceIceCandidate({
    required VoiceSignalingAdapter voiceAdapter,
    required String peerId,
    required VoiceCallFrame frame,
    required VoiceCallRole localRole,
    required int localIceCandidateCount,
    required int maxIceCandidatesPerRole,
    required void Function(int count) setLocalIceCandidateCount,
    required void Function({
      required String peerId,
      required String callId,
      required int sessionEpoch,
      required VoiceCallRole role,
      required int requestedCount,
      required int droppedCount,
      Object? error,
    })
    recordIceCandidateBudgetExceeded,
    required VoiceFrameEncryptor encryptVoiceFrame,
    required String Function(VoiceCallRole role) voiceIcePurpose,
    required VoiceIceCandidateWriteFailureRecorder
    recordVoiceIceCandidateWriteFailed,
    required IceCandidateBatcher<VoiceSignalingEnvelope>? batcher,
    required Future<void> Function({
      required VoiceSignalingAdapter voiceAdapter,
      required String peerId,
      required String callId,
      required int sessionEpoch,
      required VoiceCallRole role,
      required List<VoiceSignalingEnvelope> candidates,
    })
    flushVoiceIceCandidateBatch,
  }) async {
    if (localIceCandidateCount >= maxIceCandidatesPerRole) {
      recordIceCandidateBudgetExceeded(
        peerId: peerId,
        callId: frame.callId,
        sessionEpoch: frame.sessionEpoch,
        role: localRole,
        requestedCount: 1,
        droppedCount: 1,
      );
      return;
    }

    final VoiceSignalingEnvelope envelope;
    try {
      envelope = await encryptVoiceFrame(
        frame,
        purpose: voiceIcePurpose(localRole),
        maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength,
      );
    } catch (error, stackTrace) {
      recordVoiceIceCandidateWriteFailed(
        error,
        stackTrace,
        peerId: peerId,
        callId: frame.callId,
        sessionEpoch: frame.sessionEpoch,
        role: localRole,
        batchSize: 1,
      );
      return;
    }

    setLocalIceCandidateCount(localIceCandidateCount + 1);
    if (batcher == null) {
      await flushVoiceIceCandidateBatch(
        voiceAdapter: voiceAdapter,
        peerId: peerId,
        callId: frame.callId,
        sessionEpoch: frame.sessionEpoch,
        role: localRole,
        candidates: <VoiceSignalingEnvelope>[envelope],
      );
      return;
    }

    try {
      await batcher.add(envelope);
    } catch (error, stackTrace) {
      recordVoiceIceCandidateWriteFailed(
        error,
        stackTrace,
        peerId: peerId,
        callId: frame.callId,
        sessionEpoch: frame.sessionEpoch,
        role: localRole,
        batchSize: batcher.pendingCount,
      );
    }
  }

  Future<void> flushVoiceIceCandidateBatch({
    required VoiceSignalingAdapter voiceAdapter,
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required VoiceCallRole role,
    required List<VoiceSignalingEnvelope> candidates,
    required String username,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required void Function({
      required String peerId,
      required String callId,
      required int sessionEpoch,
      required VoiceCallRole role,
      required int requestedCount,
      required int droppedCount,
      Object? error,
    })
    recordIceCandidateBudgetExceeded,
    required VoiceIceCandidateWriteFailureRecorder
    recordVoiceIceCandidateWriteFailed,
  }) async {
    if (candidates.isEmpty) {
      return;
    }
    try {
      final candidateIds = await voiceAdapter.writeIceCandidates(
        callId: callId,
        username: username,
        role: role,
        candidates: candidates,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      final droppedCount = candidates.length - candidateIds.length;
      recordRuntimeEvent(
        category: 'call',
        name: 'ice_candidate_batch_flushed',
        context: <String, Object?>{
          'peerId': peerId,
          'callId': callId,
          'sessionEpoch': sessionEpoch,
          'role': role.name,
          'batchSize': candidates.length,
          'writtenCount': candidateIds.length,
          'droppedCount': droppedCount,
        },
      );
      if (droppedCount > 0) {
        recordIceCandidateBudgetExceeded(
          peerId: peerId,
          callId: callId,
          sessionEpoch: sessionEpoch,
          role: role,
          requestedCount: candidates.length,
          droppedCount: droppedCount,
        );
      }
    } on SignalingCostBudgetExceeded catch (error, stackTrace) {
      recordIceCandidateBudgetExceeded(
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        role: role,
        requestedCount: candidates.length,
        droppedCount: candidates.length,
        error: error,
      );
      recordVoiceIceCandidateWriteFailed(
        error,
        stackTrace,
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        role: role,
        batchSize: candidates.length,
      );
    } catch (error, stackTrace) {
      recordVoiceIceCandidateWriteFailed(
        error,
        stackTrace,
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        role: role,
        batchSize: candidates.length,
      );
    }
  }

  void recordIceCandidateBudgetExceeded({
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required VoiceCallRole role,
    required int requestedCount,
    required int droppedCount,
    required int maxIceCandidatesPerRole,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    Object? error,
  }) {
    final context = <String, Object?>{
      'peerId': peerId,
      'callId': callId,
      'sessionEpoch': sessionEpoch,
      'role': role.name,
      'requestedCount': requestedCount,
      'droppedCount': droppedCount,
      'limit': maxIceCandidatesPerRole,
    };
    recordRuntimeEvent(
      category: 'call',
      name: 'ice_candidate_batch_dropped_limit',
      severity: 'warning',
      message: error?.toString(),
      context: context,
    );
    recordRuntimeEvent(
      category: 'call',
      name: 'signaling_cost_budget_exceeded',
      severity: 'warning',
      message: error?.toString(),
      context: context,
    );
  }

  void recordVoiceIceCandidateWriteFailed(
    Object error,
    StackTrace stackTrace, {
    required String peerId,
    required String callId,
    required int sessionEpoch,
    required VoiceCallRole role,
    required int batchSize,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required VoiceCallSignalingErrorRecorder? errorRecorder,
  }) {
    recordRuntimeEvent(
      category: 'call',
      name: 'ice_candidate_write_failed',
      severity: 'warning',
      message: error.toString(),
      context: <String, Object?>{
        'peerId': peerId,
        'callId': callId,
        'sessionEpoch': sessionEpoch,
        'role': role.name,
        'batchSize': batchSize,
      },
    );
    errorRecorder?.call(
      error,
      stackTrace,
      source: 'voice-ice-candidate-write',
      fatal: false,
    );
  }

  void recordVoiceSignalingError(
    Object error,
    StackTrace stackTrace, {
    required bool Function(Object error) isVoiceTerminalAlreadyClosedError,
    required void Function(
      Object error, {
      required String name,
      required Map<String, Object?> context,
    })
    recordTerminalAlreadyClosed,
    required Map<String, Object?> context,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required VoiceCallSignalingErrorRecorder? errorRecorder,
  }) {
    if (isVoiceTerminalAlreadyClosedError(error)) {
      recordTerminalAlreadyClosed(
        error,
        name: 'voice_cleanup_already_completed',
        context: context,
      );
      return;
    }
    recordRuntimeEvent(
      category: 'call',
      name: 'signaling_error',
      severity: 'error',
      message: error.toString(),
      context: context,
    );
    errorRecorder?.call(
      error,
      stackTrace,
      source: 'voice-call-signaling',
      fatal: false,
    );
  }

  Future<void> cancelVoiceSignalingSubscriptions({
    required List<StreamSubscription<dynamic>> subscriptions,
    required VoiceCallSignalingBoundedCleanup runBoundedCleanupStep,
  }) async {
    final copiedSubscriptions = List<StreamSubscription<dynamic>>.of(
      subscriptions,
    );
    subscriptions.clear();
    for (var index = 0; index < copiedSubscriptions.length; index += 1) {
      await runBoundedCleanupStep(
        'voice_signaling_subscription_cancel',
        copiedSubscriptions[index].cancel,
        context: <String, Object?>{
          'subscriptionIndex': index,
          'subscriptionCount': copiedSubscriptions.length,
        },
      );
    }
  }

  Future<void> endVoiceCallInSignaling({
    required String callId,
    required VoiceCallSignalingStatus status,
    required VoiceSignalingAdapter Function() requireVoiceSignalingAdapter,
    required String username,
    required void Function(String callId, VoiceCallSignalingStatus status)
    recordRoomStatusTransition,
    required bool Function(Object error) isDurableTerminalStateError,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    String? reason,
    String? reasonCode,
    bool bestEffort = false,
  }) async {
    final cleanupContext = <String, Object?>{
      'callId': callId,
      'status': status.name,
      'reason': reason,
      'reasonCode': reasonCode,
      'bestEffort': bestEffort,
    };
    try {
      recordRuntimeEvent(
        category: 'call',
        name: 'signaling_end_call_started',
        context: cleanupContext,
      );
      recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_cleanup_started',
        context: cleanupContext,
      );
      await requireVoiceSignalingAdapter().endCall(
        callId: callId,
        username: username,
        status: status,
        endedAt: DateTime.now().millisecondsSinceEpoch,
        reason: reason,
        reasonCode: reasonCode,
      );
      recordRoomStatusTransition(callId, status);
      recordRuntimeEvent(
        category: 'call',
        name: 'signaling_end_call_completed',
        context: <String, Object?>{
          'callId': callId,
          'status': status.name,
          'reasonCode': reasonCode,
        },
      );
      recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_cleanup_completed',
        context: cleanupContext,
      );
    } catch (error) {
      if (isDurableTerminalStateError(error)) {
        recordRuntimeEvent(
          category: 'call',
          name: 'voice_cleanup_already_completed',
          severity: 'info',
          message: error.toString(),
          context: cleanupContext,
        );
        recordRuntimeEvent(
          category: 'call',
          name: 'voice_terminal_cleanup_completed',
          context: <String, Object?>{
            ...cleanupContext,
            'cleanupResult': 'alreadyCompleted',
          },
        );
        return;
      }
      recordRuntimeEvent(
        category: 'call',
        name: 'signaling_end_call_failed',
        severity: bestEffort ? 'warning' : 'error',
        message: error.toString(),
        context: <String, Object?>{
          'callId': callId,
          'status': status.name,
          'reasonCode': reasonCode,
          'bestEffort': bestEffort,
        },
      );
      recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_cleanup_failed',
        severity: bestEffort ? 'warning' : 'error',
        message: error.toString(),
        context: cleanupContext,
      );
      if (!bestEffort) {
        rethrow;
      }
    }
  }

  void recordVoiceRoomStatusTransition(
    Map<String, List<String>> roomStatusTimelineByCall,
    Map<String, VoiceCallSignalingStatus> roomSignalingStatusByCall,
    String callId,
    VoiceCallSignalingStatus status,
  ) {
    final timeline = roomStatusTimelineByCall.putIfAbsent(
      callId,
      () => <String>[],
    );
    final value = status.name;
    if (timeline.isEmpty || timeline.last != value) {
      timeline.add(value);
    }
    while (timeline.length > 16) {
      timeline.removeAt(0);
    }
    VoiceCallRoomCoordinator.instance.recordRoomStatusTransition(
      roomSignalingStatusByCall,
      callId,
      status,
    );
  }

  List<String> voiceRoomStatusTimeline(
    Map<String, List<String>> roomStatusTimelineByCall,
    String callId,
  ) {
    return List<String>.unmodifiable(
      roomStatusTimelineByCall[callId] ?? const <String>[],
    );
  }

  bool isDurableVoiceCallTerminalStateError(
    Object error, {
    required String Function(Object error) normalizeErrorText,
  }) {
    final normalized = normalizeErrorText(error).toLowerCase();
    return normalized.contains('unknown voice call') ||
        normalized.contains('already ended');
  }

  bool isVoiceTerminalAlreadyClosedError(
    Object error, {
    required String Function(Object error) normalizeErrorText,
  }) {
    return isVoiceTerminalAlreadyClosedMessage(normalizeErrorText(error));
  }

  bool isVoiceTerminalAlreadyClosedMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('unknown voice call') ||
        normalized.contains('already ended') ||
        normalized.contains('failed to send hangup');
  }

  void recordTerminalAlreadyClosed(
    Object error, {
    required String name,
    required Map<String, Object?> context,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
  }) {
    recordRuntimeEvent(
      category: 'call',
      name: name,
      severity: 'info',
      message: error.toString(),
      context: <String, Object?>{
        ...context,
        'cleanupResult': 'alreadyCompleted',
      },
    );
  }

  Future<void> disposeCurrentVoiceCallSession({
    required void Function() cancelReconnectGrace,
    required Future<void> Function() disposeVoiceIceCandidateBatcher,
    required Future<void> Function() cancelVoiceSignalingSubscriptions,
    required VoiceCallSession? currentSession,
    required StreamSubscription<VoiceCallSessionState>? sessionSubscription,
    required void Function(StreamSubscription<VoiceCallSessionState>?)
    setSessionSubscription,
    required VoiceCallSignalingBoundedCleanup runBoundedCleanupStep,
    required Future<void> Function(VoiceCallSession session)
    disposeVoiceCallSession,
  }) async {
    cancelReconnectGrace();
    await disposeVoiceIceCandidateBatcher();
    await cancelVoiceSignalingSubscriptions();
    final session = currentSession;
    if (session == null) {
      final subscription = sessionSubscription;
      setSessionSubscription(null);
      if (subscription != null) {
        await runBoundedCleanupStep(
          'voice_call_session_subscription_cancel',
          subscription.cancel,
        );
      }
      return;
    }
    await disposeVoiceCallSession(session);
  }

  Future<void> disposeVoiceCallSession(
    VoiceCallSession session, {
    required VoiceCallSession? currentSession,
    required void Function(VoiceCallSession?) setCurrentSession,
    required void Function() cancelReconnectGrace,
    required Future<void> Function() disposeVoiceIceCandidateBatcher,
    required Future<void> Function() cancelVoiceSignalingSubscriptions,
    required StreamSubscription<VoiceCallSessionState>? sessionSubscription,
    required void Function(StreamSubscription<VoiceCallSessionState>?)
    setSessionSubscription,
    required Future<void> Function() disposeVideoCallResources,
    required void Function(String callId, int sessionEpoch)
    removeTerminalSessionKey,
    required void Function(String callId) removeRoomStatusTimeline,
    required VoiceCallSignalingBoundedCleanup runBoundedCleanupStep,
  }) async {
    var ownsRuntimeResources = false;
    if (currentSession == session) {
      ownsRuntimeResources = true;
      setCurrentSession(null);
      cancelReconnectGrace();
      await disposeVoiceIceCandidateBatcher();
      await cancelVoiceSignalingSubscriptions();
      final subscription = sessionSubscription;
      setSessionSubscription(null);
      if (subscription != null) {
        await runBoundedCleanupStep(
          'voice_call_session_subscription_cancel',
          subscription.cancel,
          context: <String, Object?>{
            'peerId': session.remotePeerId,
            'callId': session.callId,
            'sessionEpoch': session.sessionEpoch,
          },
        );
      }
      await disposeVideoCallResources();
      removeTerminalSessionKey(session.callId, session.sessionEpoch);
      removeRoomStatusTimeline(session.callId);
    }
    await runBoundedCleanupStep(
      'voice_call_session_dispose',
      session.dispose,
      context: <String, Object?>{
        'peerId': session.remotePeerId,
        'callId': session.callId,
        'sessionEpoch': session.sessionEpoch,
        'ownsRuntimeResources': ownsRuntimeResources,
      },
    );
  }

  Future<bool> runBoundedVoiceCleanupStep(
    String step,
    Future<void> Function() cleanup, {
    required Duration cleanupStepTimeout,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required VoiceCallSignalingErrorRecorder? errorRecorder,
    Map<String, Object?> context = const <String, Object?>{},
  }) async {
    var completed = true;
    try {
      await cleanup().timeout(
        cleanupStepTimeout,
        onTimeout: () {
          completed = false;
          recordRuntimeEvent(
            category: 'call',
            name: '${step}_timeout',
            severity: 'warning',
            message: 'Voice call cleanup step timed out.',
            context: <String, Object?>{
              ...context,
              'timeoutMs': cleanupStepTimeout.inMilliseconds,
            },
          );
        },
      );
    } catch (error, stackTrace) {
      completed = false;
      recordRuntimeEvent(
        category: 'call',
        name: '${step}_failed',
        severity: 'warning',
        message: error.toString(),
        context: context,
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'voice-call-cleanup',
        fatal: false,
      );
    }
    return completed;
  }

  Future<void> disposeVoiceIceCandidateBatcher({
    required IceCandidateBatcher<VoiceSignalingEnvelope>? batcher,
    required void Function(IceCandidateBatcher<VoiceSignalingEnvelope>?)
    setBatcher,
    required void Function(int count) setLocalIceCandidateCount,
    required Duration cleanupStepTimeout,
    required VoiceCallState currentState,
    required Map<String, Object?> Function(VoiceCallState state) eventContext,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required VoiceIceCandidateWriteFailureRecorder
    recordVoiceIceCandidateWriteFailed,
    required VoiceCallRole localVoiceCallRole,
  }) async {
    setBatcher(null);
    setLocalIceCandidateCount(0);
    if (batcher == null) {
      return;
    }
    try {
      await batcher.dispose().timeout(
        cleanupStepTimeout,
        onTimeout: () {
          recordRuntimeEvent(
            category: 'call',
            name: 'voice_ice_candidate_batcher_dispose_timeout',
            severity: 'warning',
            message: 'Voice call ICE candidate cleanup timed out.',
            context: eventContext(currentState),
          );
        },
      );
    } catch (error, stackTrace) {
      final peerId = currentState.peerId;
      final callId = currentState.callId;
      final sessionEpoch = currentState.sessionEpoch;
      if (peerId == null || callId == null || sessionEpoch == null) {
        return;
      }
      recordVoiceIceCandidateWriteFailed(
        error,
        stackTrace,
        peerId: peerId,
        callId: callId,
        sessionEpoch: sessionEpoch,
        role: localVoiceCallRole,
        batchSize: 0,
      );
    }
  }

  Future<VoiceCallSignalingTerminalWriteOutcome>
  writeTerminalRoomBeforeSessionHangup({
    required String callId,
    required VoiceCallSignalingStatus status,
    required String detail,
    required CallTerminalWritePolicy terminalWritePolicy,
    required Future<void> Function({
      required String callId,
      required VoiceCallSignalingStatus status,
      String? reason,
      String? reasonCode,
      bool bestEffort,
    })
    endVoiceCallInSignaling,
    required bool Function(Object error) isDurableTerminalStateError,
    required VoiceCallSignalingEventRecorder recordRuntimeEvent,
    required VoiceCallSignalingErrorRecorder? errorRecorder,
    String? reasonCode,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (
      var attempt = 1;
      attempt <= terminalWritePolicy.maxAttempts;
      attempt += 1
    ) {
      final context = <String, Object?>{
        'callId': callId,
        'status': status.name,
        'reasonCode': reasonCode,
        'attempt': attempt,
        'maxAttempts': terminalWritePolicy.maxAttempts,
      };
      recordRuntimeEvent(
        category: 'call',
        name: 'voice_terminal_write_before_session_hangup',
        context: context,
      );
      try {
        await endVoiceCallInSignaling(
          callId: callId,
          status: status,
          reason: detail,
          reasonCode: reasonCode,
        );
        recordRuntimeEvent(
          category: 'call',
          name: 'voice_terminal_write_durable',
          context: context,
        );
        return const VoiceCallSignalingTerminalWriteOutcome.durable();
      } catch (error, stackTrace) {
        if (isDurableTerminalStateError(error)) {
          recordRuntimeEvent(
            category: 'call',
            name: 'voice_terminal_write_durable',
            context: <String, Object?>{
              ...context,
              'cleanupResult': 'alreadyCompleted',
            },
          );
          return const VoiceCallSignalingTerminalWriteOutcome.durable();
        }
        lastError = error;
        lastStackTrace = stackTrace;
        if (!terminalWritePolicy.canRetryAfterAttempt(attempt)) {
          break;
        }
        final delay = terminalWritePolicy.retryDelayAfterAttempt(attempt);
        recordRuntimeEvent(
          category: 'call',
          name: 'voice_terminal_write_retry',
          severity: 'warning',
          message: error.toString(),
          context: <String, Object?>{
            ...context,
            'nextAttempt': attempt + 1,
            'retryDelayMs': delay.inMilliseconds,
          },
        );
        await Future<void>.delayed(delay);
      }
    }
    recordRuntimeEvent(
      category: 'call',
      name: 'voice_terminal_write_failed',
      severity: 'error',
      message: lastError?.toString(),
      context: <String, Object?>{
        'callId': callId,
        'status': status.name,
        'reasonCode': reasonCode,
        'maxAttempts': terminalWritePolicy.maxAttempts,
      },
    );
    if (lastError != null) {
      errorRecorder?.call(
        lastError,
        lastStackTrace,
        source: 'voice-terminal-write',
        fatal: false,
      );
    }
    return VoiceCallSignalingTerminalWriteOutcome.failed(lastError);
  }
}
