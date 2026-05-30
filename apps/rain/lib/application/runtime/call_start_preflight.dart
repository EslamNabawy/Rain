import 'package:protocol_brain/protocol_brain.dart' show CallMediaMode;

enum CallStartPreflightDecision {
  allowed,
  peerOffline,
  presenceUnknown,
  activeCallExists,
  activeTransferExists,
  localManualDisconnect,
  permissionRequired,
}

final class CallStartPreflightResult {
  const CallStartPreflightResult._({
    required this.decision,
    required this.peerId,
    required this.mediaMode,
    this.blockingPeerId,
    this.userMessage,
    this.diagnostics = const <String, Object?>{},
  });

  const CallStartPreflightResult.allow({
    required String peerId,
    required CallMediaMode mediaMode,
    Map<String, Object?> diagnostics = const <String, Object?>{},
  }) : this._(
         decision: CallStartPreflightDecision.allowed,
         peerId: peerId,
         mediaMode: mediaMode,
         diagnostics: diagnostics,
       );

  const CallStartPreflightResult.deny({
    required CallStartPreflightDecision decision,
    required String peerId,
    required CallMediaMode mediaMode,
    required String userMessage,
    String? blockingPeerId,
    Map<String, Object?> diagnostics = const <String, Object?>{},
  }) : this._(
         decision: decision,
         peerId: peerId,
         mediaMode: mediaMode,
         blockingPeerId: blockingPeerId,
         userMessage: userMessage,
         diagnostics: diagnostics,
       );

  final CallStartPreflightDecision decision;
  final String peerId;
  final CallMediaMode mediaMode;
  final String? blockingPeerId;
  final String? userMessage;
  final Map<String, Object?> diagnostics;

  bool get allowed => decision == CallStartPreflightDecision.allowed;

  void throwIfDenied() {
    if (!allowed) {
      throw StateError(userMessage ?? 'Call cannot start right now.');
    }
  }
}
