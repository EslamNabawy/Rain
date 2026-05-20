import 'connection_command_models.dart';

class ConnectionFailureMessages {
  const ConnectionFailureMessages._();

  static String userMessage(ConnectionFailureCode code) {
    return switch (code) {
      ConnectionFailureCode.peerOffline => 'Peer is offline.',
      ConnectionFailureCode.notFriends => 'You are not friends.',
      ConnectionFailureCode.blocked => 'Peer is blocked.',
      ConnectionFailureCode.networkOffline => 'Internet connection is offline.',
      ConnectionFailureCode.backendUnavailable =>
        'Rain backend is unreachable.',
      ConnectionFailureCode.signalingPermissionDenied =>
        'Signaling permission denied.',
      ConnectionFailureCode.staleRoomCleanupFailed =>
        'Could not clean stale connection room.',
      ConnectionFailureCode.directPathBlocked => 'Direct path blocked.',
      ConnectionFailureCode.turnCredentialsUnavailable =>
        'Relay credentials unavailable.',
      ConnectionFailureCode.turnProviderTimedOut => 'Relay provider timed out.',
      ConnectionFailureCode.dataChannelTimeout => 'Data channel did not open.',
      ConnectionFailureCode.irohAddressTimeout =>
        'Iroh address exchange timed out.',
      ConnectionFailureCode.irohHandshakeRejected => 'Iroh handshake rejected.',
      ConnectionFailureCode.irohConnectFailed => 'Iroh connection failed.',
      ConnectionFailureCode.globalBudgetExceeded =>
        'All connection routes timed out.',
      ConnectionFailureCode.userCanceled => 'Connection canceled.',
      ConnectionFailureCode.unknown => 'Connection failed.',
    };
  }
}
