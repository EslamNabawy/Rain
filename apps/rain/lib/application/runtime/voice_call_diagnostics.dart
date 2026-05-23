import 'dart:convert';

class VoiceCallDiagnostics {
  const VoiceCallDiagnostics({
    required this.callId,
    required this.peerId,
    required this.role,
    required this.failureCode,
    required this.userMessage,
    required this.nativeError,
    this.iceStates = const <String>[],
    this.connectionStates = const <String>[],
  });

  final String callId;
  final String peerId;
  final String role;
  final String failureCode;
  final String userMessage;
  final String nativeError;
  final List<String> iceStates;
  final List<String> connectionStates;

  Map<String, Object?> toJson() => <String, Object?>{
    'callId': callId,
    'peerId': peerId,
    'role': role,
    'failureCode': failureCode,
    'userMessage': userMessage,
    'nativeError': nativeError,
    if (iceStates.isNotEmpty) 'iceStates': iceStates,
    if (connectionStates.isNotEmpty) 'connectionStates': connectionStates,
  };

  @override
  String toString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
