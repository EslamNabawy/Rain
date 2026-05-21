import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/infrastructure/services/turn_credential_service.dart';

class TurnFallbackDiagnostics {
  const TurnFallbackDiagnostics({
    required this.stageLabel,
    required this.providerTierLabel,
    required this.providerLabel,
    required this.turnUrlCountLabel,
    required this.userDetail,
    this.lastError,
    this.errorCodeLabel,
    this.connectAttemptId,
    this.attemptIndex = 0,
  });

  final String stageLabel;
  final String providerTierLabel;
  final String providerLabel;
  final String turnUrlCountLabel;
  final String userDetail;
  final String? lastError;
  final String? errorCodeLabel;
  final String? connectAttemptId;
  final int attemptIndex;

  factory TurnFallbackDiagnostics.fromSession(
    Session? session, {
    required TurnCredentialDiagnostics turnDiagnostics,
  }) {
    final provider = turnDiagnostics.provider.trim();
    final detail = session?.detail.trim();
    final sessionError = session?.error?.trim();
    final relayError = turnDiagnostics.lastError?.trim();

    return TurnFallbackDiagnostics(
      stageLabel: session?.iceStage?.label ?? 'Not started',
      providerTierLabel: session?.providerTier?.label ?? 'None',
      providerLabel: provider.isEmpty ? 'unknown' : provider,
      turnUrlCountLabel: _turnUrlCountLabel(turnDiagnostics.turnUrlCount),
      userDetail: detail == null || detail.isEmpty
          ? 'No WebRTC attempt is active.'
          : detail,
      lastError: relayError == null || relayError.isEmpty
          ? (sessionError == null || sessionError.isEmpty ? null : sessionError)
          : relayError,
      errorCodeLabel: turnDiagnostics.errorCode?.label,
      connectAttemptId: session?.connectAttemptId,
      attemptIndex: session?.attemptIndex ?? 0,
    );
  }
}

String _turnUrlCountLabel(int count) {
  if (count == 1) {
    return '1 TURN URL';
  }
  return '$count TURN URLs';
}
