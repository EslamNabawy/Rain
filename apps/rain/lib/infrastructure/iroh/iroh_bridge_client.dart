import 'dart:convert';
import 'dart:typed_data';

import 'package:rain/src/rust/api/iroh_transport.dart' as native;
import 'package:rain/src/rust/frb_generated.dart' as frb;

import 'iroh_models.dart';

typedef RustBridgeInitializer = Future<void> Function();

abstract class IrohNativeApi {
  Future<IrohEndpointInfo> startEndpoint({
    required String username,
    required String alpn,
  });

  Future<void> stopEndpoint();

  Future<void> disconnectPeer({required String peerId});

  Future<void> connectPeer({
    required String peerId,
    required String endpointAddr,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  });

  Future<void> acceptPeer({
    required String peerId,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  });

  Future<void> send({
    required String peerId,
    required String channel,
    required Object payload,
  });

  Future<int> bufferedAmount({required String peerId, required String channel});

  Stream<IrohTransportEvent> eventStream();
}

class GeneratedIrohNativeApi implements IrohNativeApi {
  GeneratedIrohNativeApi({RustBridgeInitializer? initialize})
    : _initialize = initialize ?? frb.RustLib.init,
      _usesDefaultInitializer = initialize == null;

  static Future<void>? _defaultInitialization;

  final RustBridgeInitializer _initialize;
  final bool _usesDefaultInitializer;
  Future<void>? _initialization;

  Future<void> _ensureInitialized() {
    if (_usesDefaultInitializer) {
      return _defaultInitialization ??= _initialize();
    }
    return _initialization ??= _initialize();
  }

  @override
  Future<IrohEndpointInfo> startEndpoint({
    required String username,
    required String alpn,
  }) async {
    await _ensureInitialized();
    final info = await native.irohStartEndpoint(username: username, alpn: alpn);
    return IrohEndpointInfo(
      nodeId: info.nodeId,
      endpointAddr: info.endpointAddr,
    );
  }

  @override
  Future<void> stopEndpoint() async {
    if (!_usesDefaultInitializer && _initialization == null) {
      return;
    }
    if (_usesDefaultInitializer && _defaultInitialization == null) {
      return;
    }
    await _ensureInitialized();
    await native.irohStopEndpoint();
  }

  @override
  Future<void> disconnectPeer({required String peerId}) async {
    await _ensureInitialized();
    await native.irohDisconnectPeer(peerId: peerId);
  }

  @override
  Future<void> connectPeer({
    required String peerId,
    required String endpointAddr,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) async {
    await _ensureInitialized();
    await native.irohConnectPeer(
      peerId: peerId,
      endpointAddr: endpointAddr,
      expectedNodeId: expectedNodeId,
      alpn: alpn,
      connectAttemptId: connectAttemptId,
      sessionSecret: sessionSecret,
    );
  }

  @override
  Future<void> acceptPeer({
    required String peerId,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) async {
    await _ensureInitialized();
    await native.irohAcceptPeer(
      peerId: peerId,
      expectedNodeId: expectedNodeId,
      alpn: alpn,
      connectAttemptId: connectAttemptId,
      sessionSecret: sessionSecret,
    );
  }

  @override
  Future<void> send({
    required String peerId,
    required String channel,
    required Object payload,
  }) async {
    await _ensureInitialized();
    await native.irohSend(
      peerId: peerId,
      channel: channel,
      payload: _payloadBytes(payload),
    );
  }

  @override
  Future<int> bufferedAmount({
    required String peerId,
    required String channel,
  }) async {
    await _ensureInitialized();
    final amount = await native.irohBufferedAmount(
      peerId: peerId,
      channel: channel,
    );
    return amount.toInt();
  }

  @override
  Stream<IrohTransportEvent> eventStream() async* {
    await _ensureInitialized();
    yield* native.irohEventStream().map(IrohTransportEvent.fromJsonString);
  }
}

class IrohBridgeClient {
  const IrohBridgeClient(this._native);

  final IrohNativeApi _native;

  Future<IrohEndpointInfo> startEndpoint({
    required String username,
    required String alpn,
  }) {
    return _native.startEndpoint(username: username, alpn: alpn);
  }

  Future<void> stopEndpoint() => _native.stopEndpoint();

  Future<void> disconnectPeer({required String peerId}) {
    return _native.disconnectPeer(peerId: peerId);
  }

  Future<void> connectPeer({
    required String peerId,
    required String endpointAddr,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) {
    return _native.connectPeer(
      peerId: peerId,
      endpointAddr: endpointAddr,
      expectedNodeId: expectedNodeId,
      alpn: alpn,
      connectAttemptId: connectAttemptId,
      sessionSecret: sessionSecret,
    );
  }

  Future<void> acceptPeer({
    required String peerId,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) {
    return _native.acceptPeer(
      peerId: peerId,
      expectedNodeId: expectedNodeId,
      alpn: alpn,
      connectAttemptId: connectAttemptId,
      sessionSecret: sessionSecret,
    );
  }

  Future<void> send({
    required String peerId,
    required String channel,
    required Object payload,
  }) {
    return _native.send(peerId: peerId, channel: channel, payload: payload);
  }

  Future<int> bufferedAmount({
    required String peerId,
    required String channel,
  }) {
    return _native.bufferedAmount(peerId: peerId, channel: channel);
  }

  Stream<IrohTransportEvent> eventStream() => _native.eventStream();
}

List<int> _payloadBytes(Object payload) {
  if (payload is Uint8List) {
    return payload;
  }
  if (payload is List<int>) {
    return Uint8List.fromList(payload);
  }
  if (payload is String) {
    return utf8.encode(payload);
  }
  throw ArgumentError.value(
    payload,
    'payload',
    'Iroh payload must be a String, Uint8List, or List<int>.',
  );
}
