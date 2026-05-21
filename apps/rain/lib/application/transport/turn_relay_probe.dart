import 'package:protocol_brain/protocol_brain.dart';

typedef RelayProbeConfigCheck =
    Future<void> Function(
      PeerIceTransportPolicy policy,
      List<Map<String, dynamic>> iceServers,
    );

class TurnRelayProbe {
  const TurnRelayProbe({required this.iceServersForAttempt, this.configCheck});

  final Future<List<Map<String, dynamic>>> Function(
    IceAttemptDescriptor attempt,
  )
  iceServersForAttempt;
  final RelayProbeConfigCheck? configCheck;

  Future<TurnRelayProbeResult> run({
    required String peerId,
    required IceAttemptDescriptor attempt,
  }) async {
    try {
      if (attempt.policy != PeerIceTransportPolicy.relayOnly) {
        return TurnRelayProbeResult.failed(
          providerId: attempt.providerId,
          stage: attempt.stage,
          error: 'Relay probe must use relay-only policy.',
        );
      }

      final iceServers = await iceServersForAttempt(attempt);
      final turnUrlCount = _turnUrlCount(iceServers);
      if (turnUrlCount == 0) {
        return TurnRelayProbeResult.failed(
          providerId: attempt.providerId,
          stage: attempt.stage,
          error: 'Relay credentials unavailable.',
        );
      }

      await configCheck?.call(PeerIceTransportPolicy.relayOnly, iceServers);
      return TurnRelayProbeResult.ready(
        providerId: attempt.providerId,
        stage: attempt.stage,
        turnUrlCount: turnUrlCount,
      );
    } catch (error) {
      return TurnRelayProbeResult.failed(
        providerId: attempt.providerId,
        stage: attempt.stage,
        error: _formatRelayProbeError(error),
      );
    }
  }
}

class TurnRelayProbeResult {
  const TurnRelayProbeResult._({
    required this.succeeded,
    required this.providerId,
    required this.stage,
    required this.turnUrlCount,
    this.error,
  });

  factory TurnRelayProbeResult.ready({
    required String providerId,
    required IceAttemptStage stage,
    required int turnUrlCount,
  }) {
    return TurnRelayProbeResult._(
      succeeded: true,
      providerId: providerId,
      stage: stage,
      turnUrlCount: turnUrlCount,
    );
  }

  factory TurnRelayProbeResult.failed({
    required String providerId,
    required IceAttemptStage stage,
    required String error,
  }) {
    return TurnRelayProbeResult._(
      succeeded: false,
      providerId: providerId,
      stage: stage,
      turnUrlCount: 0,
      error: error,
    );
  }

  final bool succeeded;
  final String providerId;
  final IceAttemptStage stage;
  final int turnUrlCount;
  final String? error;

  String get userMessage {
    if (succeeded) {
      return turnUrlCount == 1
          ? 'Relay credentials ready. 1 TURN URL.'
          : 'Relay credentials ready. $turnUrlCount TURN URLs.';
    }
    return error ?? 'Relay credentials unavailable.';
  }
}

int _turnUrlCount(List<Map<String, dynamic>> iceServers) {
  var count = 0;
  for (final server in iceServers) {
    final urls = server['urls'];
    if (urls is Iterable) {
      count += urls
          .where((Object? url) => _isTurnUrl(url?.toString() ?? ''))
          .length;
    } else if (_isTurnUrl(urls?.toString() ?? '')) {
      count += 1;
    }
  }
  return count;
}

bool _isTurnUrl(String url) {
  final normalized = url.trim().toLowerCase();
  return normalized.startsWith('turn:') || normalized.startsWith('turns:');
}

String _formatRelayProbeError(Object error) {
  final raw = error.toString().trim();
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length).trim();
    }
  }
  return raw.isEmpty ? 'Relay credentials unavailable.' : raw;
}
