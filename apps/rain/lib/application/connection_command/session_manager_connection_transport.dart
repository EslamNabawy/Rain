import 'dart:async';

import 'package:protocol_brain/protocol_brain.dart';

import 'connection_command_models.dart';
import 'connection_command_orchestrator.dart';
import 'connection_run_token.dart';

class SessionManagerConnectionTransport implements ConnectionCommandTransport {
  const SessionManagerConnectionTransport({required this.webRtc, this.iroh});

  final SessionManager webRtc;
  final SessionManager? iroh;

  @override
  Future<ConnectionLayerResult> runLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
    required Duration timeout,
  }) async {
    if (layer == ConnectionLayer.preflight) {
      return const ConnectionLayerResult.succeeded();
    }
    if (token.isCanceled) {
      return const ConnectionLayerResult.failed(
        ConnectionFailureCode.userCanceled,
      );
    }

    final manager = _managerFor(layer);
    if (manager == null) {
      return ConnectionLayerResult.failed(
        _failureForLayer(layer),
        technicalDetail: 'Transport manager is unavailable.',
      );
    }

    try {
      await manager.registerPeer(peerId);
      final session = await manager.connect(peerId).timeout(timeout);
      if (session.state == SessionState.connected) {
        return const ConnectionLayerResult.succeeded();
      }
      return ConnectionLayerResult.failed(
        _failureForLayer(layer),
        technicalDetail: session.error ?? session.detail,
      );
    } on TimeoutException catch (error) {
      return ConnectionLayerResult.failed(
        _timeoutFailureForLayer(layer),
        technicalDetail: error.message ?? 'Timed out after $timeout.',
      );
    } on Object catch (error) {
      return ConnectionLayerResult.failed(
        _failureForLayer(layer),
        technicalDetail: error.toString(),
      );
    }
  }

  @override
  Future<void> cancelLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
  }) async {
    final manager = _managerFor(layer);
    if (manager == null || layer == ConnectionLayer.preflight) {
      return;
    }
    await manager.disconnect(peerId);
    await manager.unregisterPeer(peerId);
  }

  SessionManager? _managerFor(ConnectionLayer layer) {
    return switch (layer) {
      ConnectionLayer.preflight => null,
      ConnectionLayer.iroh => iroh,
      _ => webRtc,
    };
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

  ConnectionFailureCode _timeoutFailureForLayer(ConnectionLayer layer) {
    return switch (layer) {
      ConnectionLayer.webRtcPrimaryRelay || ConnectionLayer.webRtcBackupRelay =>
        ConnectionFailureCode.turnProviderTimedOut,
      ConnectionLayer.iroh => ConnectionFailureCode.irohAddressTimeout,
      _ => _failureForLayer(layer),
    };
  }
}
