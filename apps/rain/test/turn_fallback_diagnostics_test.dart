import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/transport/turn_fallback_diagnostics.dart';
import 'package:rain/infrastructure/services/turn_credential_service.dart';

void main() {
  test('primary relay stage maps to visible TURN detail', () {
    final diagnostics = TurnFallbackDiagnostics.fromSession(
      Session(
        peerId: 'bob',
        state: SessionState.reconnecting,
        connectionType: ConnectionType.signaling,
        sender: (_) {},
        phase: SessionPhase.reconnecting,
        detail: 'Direct path blocked. Trying primary TURN relay.',
        iceStage: IceAttemptStage.primaryRelay,
        providerTier: IceProviderTier.primaryRelay,
        providerId: 'primary-relay',
        connectAttemptId: 'attempt-1',
        attemptIndex: 1,
      ),
      turnDiagnostics: const TurnCredentialDiagnostics(
        brokerConfigured: true,
        provider: 'cloudflare',
        turnUrlCount: 3,
      ),
    );

    expect(diagnostics.stageLabel, 'Primary relay');
    expect(diagnostics.providerTierLabel, 'Tier 1');
    expect(diagnostics.providerLabel, 'cloudflare');
    expect(diagnostics.turnUrlCountLabel, '3 TURN URLs');
    expect(diagnostics.userDetail, contains('Trying primary TURN relay'));
    expect(diagnostics.connectAttemptId, 'attempt-1');
    expect(diagnostics.attemptIndex, 1);
  });

  test('relay diagnostic error prefers sanitized credential status', () {
    final diagnostics = TurnFallbackDiagnostics.fromSession(
      Session(
        peerId: 'bob',
        state: SessionState.failed,
        connectionType: ConnectionType.signaling,
        sender: (_) {},
        phase: SessionPhase.failed,
        detail: 'All connection routes failed.',
        error: 'TURN broker returned 401',
        iceStage: IceAttemptStage.primaryRelay,
        providerTier: IceProviderTier.primaryRelay,
        providerId: 'primary-relay',
      ),
      turnDiagnostics: const TurnCredentialDiagnostics(
        brokerConfigured: true,
        provider: 'cloudflare',
        lastError: 'Relay authorization failed. Sign in again.',
        errorCode: TurnCredentialErrorCode.brokerAuthFailed,
      ),
    );

    expect(diagnostics.lastError, 'Relay authorization failed. Sign in again.');
    expect(diagnostics.errorCodeLabel, 'broker-auth-failed');
    expect(diagnostics.lastError, isNot(contains('401')));
  });
}
