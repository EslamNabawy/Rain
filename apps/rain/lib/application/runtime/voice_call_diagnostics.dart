import 'dart:convert';

class VoiceCallDiagnostics {
  const VoiceCallDiagnostics({
    required this.callId,
    required this.sessionEpoch,
    required this.peerId,
    required this.role,
    required this.mediaMode,
    required this.failureCode,
    required this.userMessage,
    required this.sanitizedUiError,
    required this.nativeError,
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
  });

  final String callId;
  final int sessionEpoch;
  final String peerId;
  final String role;
  final String mediaMode;
  final String failureCode;
  final String userMessage;
  final String sanitizedUiError;
  final String nativeError;
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

  Map<String, Object?> toJson() => <String, Object?>{
    'callId': callId,
    'sessionEpoch': sessionEpoch,
    'peerId': peerId,
    'role': role,
    'mediaMode': mediaMode,
    'failureCode': failureCode,
    'userMessage': userMessage,
    'sanitizedUiError': sanitizedUiError,
    'nativeError': nativeError,
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
    if (mediaStates.isNotEmpty) 'mediaStates': mediaStates,
    if (iceStates.isNotEmpty) 'iceStates': iceStates,
    if (iceStates.isNotEmpty) 'iceStateHistory': iceStates,
    if (connectionStates.isNotEmpty) 'connectionStates': connectionStates,
  };

  @override
  String toString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
