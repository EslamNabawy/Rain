import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/transport/fallback_session_manager.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'connection_command_models.dart';
import 'connection_command_orchestrator.dart';
import 'connection_run_token.dart';

class RuntimeConnectionCommandTransport implements ConnectionCommandTransport {
  const RuntimeConnectionCommandTransport({
    required this.runtime,
    required this.delegate,
  });

  final RainRuntimeController runtime;
  final ConnectionCommandTransport delegate;

  @override
  Future<ConnectionLayerResult> runLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
    required Duration timeout,
  }) async {
    if (layer != ConnectionLayer.preflight) {
      final brain = runtime.brain;
      if (brain is FallbackSessionManager) {
        return _runFallbackManagerLayer(
          manager: brain,
          peerId: peerId,
          layer: layer,
          timeout: timeout,
        );
      }
      return delegate.runLayer(
        peerId: peerId,
        layer: layer,
        token: token,
        timeout: timeout,
      );
    }
    if (token.isCanceled) {
      return const ConnectionLayerResult.failed(
        ConnectionFailureCode.userCanceled,
      );
    }
    try {
      await runtime.preparePeerConnection(peerId, interactive: true);
      return const ConnectionLayerResult.succeeded();
    } on Object catch (error) {
      return ConnectionLayerResult.failed(
        _failureCodeFor(error),
        technicalDetail: error.toString(),
      );
    }
  }

  @override
  Future<void> cancelLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
  }) {
    final brain = runtime.brain;
    if (brain is FallbackSessionManager) {
      return () async {
        await brain.disconnect(peerId);
        await brain.unregisterPeer(peerId);
      }();
    }
    return delegate.cancelLayer(peerId: peerId, layer: layer, token: token);
  }

  Future<ConnectionLayerResult> _runFallbackManagerLayer({
    required FallbackSessionManager manager,
    required String peerId,
    required ConnectionLayer layer,
    required Duration timeout,
  }) async {
    try {
      final session = switch (layer) {
        ConnectionLayer.iroh => await manager.connectIrohOnly(
          peerId,
          timeout: timeout,
        ),
        ConnectionLayer.preflight => throw StateError(
          'Preflight should be handled before transport execution.',
        ),
        _ => await manager.connectWebRtcOnly(peerId, timeout: timeout),
      };
      if (session.state == SessionState.connected) {
        return const ConnectionLayerResult.succeeded();
      }
      return ConnectionLayerResult.failed(
        _failureForLayer(layer),
        technicalDetail: session.error ?? session.detail,
      );
    } on Object catch (error) {
      return ConnectionLayerResult.failed(
        _failureForLayer(layer),
        technicalDetail: error.toString(),
      );
    }
  }

  ConnectionFailureCode _failureForLayer(ConnectionLayer layer) {
    return switch (layer) {
      ConnectionLayer.preflight => ConnectionFailureCode.unknown,
      ConnectionLayer.webRtcDirect => ConnectionFailureCode.directPathBlocked,
      ConnectionLayer.webRtcPrimaryRelay || ConnectionLayer.webRtcBackupRelay =>
        ConnectionFailureCode.turnProviderTimedOut,
      ConnectionLayer.webRtcFullRestart =>
        ConnectionFailureCode.dataChannelTimeout,
      ConnectionLayer.iroh => ConnectionFailureCode.irohConnectFailed,
    };
  }

  ConnectionFailureCode _failureCodeFor(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('offline')) {
      return ConnectionFailureCode.peerOffline;
    }
    if (message.contains('blocked') || message.contains('unblock')) {
      return ConnectionFailureCode.blocked;
    }
    if (message.contains('friend') ||
        message.contains('accept') ||
        message.contains('friends list')) {
      return ConnectionFailureCode.notFriends;
    }
    if (message.contains('backend')) {
      return ConnectionFailureCode.backendUnavailable;
    }
    return ConnectionFailureCode.unknown;
  }
}
