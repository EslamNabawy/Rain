import 'dart:convert';

class VoiceCallDiagnostics {
  const VoiceCallDiagnostics({
    required this.callId,
    required this.sessionEpoch,
    required this.peerId,
    required this.role,
    required this.failureCode,
    required this.userMessage,
    required this.nativeError,
    this.mediaStates = const <String>[],
    this.iceStates = const <String>[],
    this.connectionStates = const <String>[],
    this.localCandidateCount = 0,
    this.remoteCandidateCount = 0,
    this.pendingRemoteCandidateCount = 0,
  });

  final String callId;
  final int sessionEpoch;
  final String peerId;
  final String role;
  final String failureCode;
  final String userMessage;
  final String nativeError;
  final List<String> mediaStates;
  final List<String> iceStates;
  final List<String> connectionStates;
  final int localCandidateCount;
  final int remoteCandidateCount;
  final int pendingRemoteCandidateCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'callId': callId,
    'sessionEpoch': sessionEpoch,
    'peerId': peerId,
    'role': role,
    'failureCode': failureCode,
    'userMessage': userMessage,
    'nativeError': nativeError,
    'localCandidateCount': localCandidateCount,
    'remoteCandidateCount': remoteCandidateCount,
    'pendingRemoteCandidateCount': pendingRemoteCandidateCount,
    if (mediaStates.isNotEmpty) 'mediaStates': mediaStates,
    if (iceStates.isNotEmpty) 'iceStates': iceStates,
    if (connectionStates.isNotEmpty) 'connectionStates': connectionStates,
  };

  @override
  String toString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
