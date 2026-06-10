import 'dart:convert';

class VoiceCallDiagnostics {
  const VoiceCallDiagnostics({
    required this.callId,
    required this.sessionEpoch,
    required this.peerId,
    required this.role,
    required this.mediaMode,
    this.caller,
    this.callee,
    required this.failureCode,
    required this.userMessage,
    required this.sanitizedUiError,
    required this.nativeError,
    this.roomStatusTimeline = const <String>[],
    this.iceCandidateWriteCount = 0,
    this.iceCandidateReadCount = 0,
    this.turnReadiness,
    this.relayFallbackAttempted = false,
    this.terminalWriteOutcome,
    this.cleanupOutcome,
    this.presenceAgeAtStartMs,
    this.mediaFailureReason,
    this.failureTaxonomy,
    this.mediaStates = const <String>[],
    this.iceStates = const <String>[],
    this.connectionStates = const <String>[],
    this.localCandidateCount = 0,
    this.remoteCandidateCount = 0,
    this.pendingRemoteCandidateCount = 0,
    this.localAudioTrackCount = 0,
    this.remoteAudioTrackCount = 0,
    this.localVideoTrackCount = 0,
    this.remoteVideoTrackCount = 0,
    this.remoteStreamCount = 0,
    this.firstLocalVideoFrameAt,
    this.firstRemoteVideoFrameAt,
    this.selectedCandidateRoute,
    this.cameraPermissionFailureDetail,
    this.lockClaimResult,
    this.lockPath,
    this.pairId,
    this.callerUserLock,
    this.calleeUserLock,
    this.lockCallId,
    this.lockExpiresAt,
    this.lockWasReclaimed,
    this.terminalRoomWasCleaned,
    this.corruptRoomWasRepaired,
    this.timestampRepair,
  });

  final String callId;
  final int sessionEpoch;
  final String peerId;
  final String role;
  final String mediaMode;
  final String? caller;
  final String? callee;
  final String failureCode;
  final String userMessage;
  final String sanitizedUiError;
  final String nativeError;
  final List<String> roomStatusTimeline;
  final int iceCandidateWriteCount;
  final int iceCandidateReadCount;
  final String? turnReadiness;
  final bool relayFallbackAttempted;
  final String? terminalWriteOutcome;
  final String? cleanupOutcome;
  final int? presenceAgeAtStartMs;
  final String? mediaFailureReason;
  final String? failureTaxonomy;
  final List<String> mediaStates;
  final List<String> iceStates;
  final List<String> connectionStates;
  final int localCandidateCount;
  final int remoteCandidateCount;
  final int pendingRemoteCandidateCount;
  final int localAudioTrackCount;
  final int remoteAudioTrackCount;
  final int localVideoTrackCount;
  final int remoteVideoTrackCount;
  final int remoteStreamCount;
  final String? firstLocalVideoFrameAt;
  final String? firstRemoteVideoFrameAt;
  final String? selectedCandidateRoute;
  final String? cameraPermissionFailureDetail;
  final String? lockClaimResult;
  final String? lockPath;
  final String? pairId;
  final String? callerUserLock;
  final String? calleeUserLock;
  final String? lockCallId;
  final int? lockExpiresAt;
  final bool? lockWasReclaimed;
  final bool? terminalRoomWasCleaned;
  final bool? corruptRoomWasRepaired;
  final bool? timestampRepair;

  Map<String, Object?> toJson() => <String, Object?>{
    'callId': callId,
    'sessionEpoch': sessionEpoch,
    'peerId': peerId,
    'role': role,
    'mediaMode': mediaMode,
    if (caller != null) 'caller': caller,
    if (callee != null) 'callee': callee,
    'failureCode': failureCode,
    'userMessage': userMessage,
    'sanitizedUiError': sanitizedUiError,
    'nativeError': nativeError,
    if (roomStatusTimeline.isNotEmpty) 'roomStatusTimeline': roomStatusTimeline,
    'iceCandidateWriteCount': iceCandidateWriteCount,
    'iceCandidateReadCount': iceCandidateReadCount,
    if (turnReadiness != null) 'turnReadiness': turnReadiness,
    'relayFallbackAttempted': relayFallbackAttempted,
    if (terminalWriteOutcome != null)
      'terminalWriteOutcome': terminalWriteOutcome,
    if (cleanupOutcome != null) 'cleanupOutcome': cleanupOutcome,
    if (presenceAgeAtStartMs != null)
      'presenceAgeAtStartMs': presenceAgeAtStartMs,
    if (mediaFailureReason != null) 'mediaFailureReason': mediaFailureReason,
    if (failureTaxonomy != null) 'failureTaxonomy': failureTaxonomy,
    'localCandidateCount': localCandidateCount,
    'remoteCandidateCount': remoteCandidateCount,
    'pendingRemoteCandidateCount': pendingRemoteCandidateCount,
    'localAudioTrackCount': localAudioTrackCount,
    'remoteAudioTrackCount': remoteAudioTrackCount,
    'localVideoTrackCount': localVideoTrackCount,
    'remoteVideoTrackCount': remoteVideoTrackCount,
    'remoteStreamCount': remoteStreamCount,
    if (firstLocalVideoFrameAt != null)
      'firstLocalVideoFrameAt': firstLocalVideoFrameAt,
    if (firstRemoteVideoFrameAt != null)
      'firstRemoteVideoFrameAt': firstRemoteVideoFrameAt,
    if (selectedCandidateRoute != null)
      'selectedCandidateRoute': selectedCandidateRoute,
    if (cameraPermissionFailureDetail != null)
      'cameraPermissionFailureDetail': cameraPermissionFailureDetail,
    if (lockClaimResult != null) 'lockClaimResult': lockClaimResult,
    if (lockPath != null) 'lockPath': lockPath,
    if (pairId != null) 'pairId': pairId,
    if (callerUserLock != null) 'callerUserLock': callerUserLock,
    if (calleeUserLock != null) 'calleeUserLock': calleeUserLock,
    if (lockCallId != null) 'lockCallId': lockCallId,
    if (lockExpiresAt != null) 'lockExpiresAt': lockExpiresAt,
    if (lockWasReclaimed != null) 'lockWasReclaimed': lockWasReclaimed,
    if (terminalRoomWasCleaned != null)
      'terminalRoomWasCleaned': terminalRoomWasCleaned,
    if (corruptRoomWasRepaired != null)
      'corruptRoomWasRepaired': corruptRoomWasRepaired,
    if (timestampRepair != null) 'timestampRepair': timestampRepair,
    if (mediaStates.isNotEmpty) 'mediaStates': mediaStates,
    if (iceStates.isNotEmpty) 'iceStates': iceStates,
    if (iceStates.isNotEmpty) 'iceStateHistory': iceStates,
    if (connectionStates.isNotEmpty) 'connectionStates': connectionStates,
  };

  @override
  String toString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
