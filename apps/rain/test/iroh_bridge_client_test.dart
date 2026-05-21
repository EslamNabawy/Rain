import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/iroh/iroh_bridge_client.dart';
import 'package:rain/infrastructure/iroh/iroh_models.dart';

class FakeIrohNativeApi implements IrohNativeApi {
  var stopped = false;
  var disconnectedPeerId = '';
  var connectedPeerId = '';
  var acceptedPeerId = '';
  var sentPayloads = <Object>[];
  var pendingBytes = 0;
  final events = StreamController<IrohTransportEvent>.broadcast();

  @override
  Future<IrohEndpointInfo> startEndpoint({
    required String username,
    required String alpn,
  }) async {
    return const IrohEndpointInfo(nodeId: 'node-1', endpointAddr: 'endpoint-1');
  }

  @override
  Future<void> stopEndpoint() async {
    stopped = true;
  }

  @override
  Future<void> disconnectPeer({required String peerId}) async {
    disconnectedPeerId = peerId;
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
    connectedPeerId = peerId;
  }

  @override
  Future<void> acceptPeer({
    required String peerId,
    required String expectedNodeId,
    required String alpn,
    required String connectAttemptId,
    required String sessionSecret,
  }) async {
    acceptedPeerId = peerId;
  }

  @override
  Future<void> send({
    required String peerId,
    required String channel,
    required Object payload,
  }) async {
    sentPayloads.add(payload);
  }

  @override
  Future<int> bufferedAmount({
    required String peerId,
    required String channel,
  }) async {
    return pendingBytes;
  }

  @override
  Stream<IrohTransportEvent> eventStream() => events.stream;

  Future<void> close() => events.close();
}

void main() {
  test('bridge client starts and stops endpoint', () async {
    final native = FakeIrohNativeApi();
    final client = IrohBridgeClient(native);

    final info = await client.startEndpoint(
      username: 'alice',
      alpn: 'rain.p2p.quic.v1',
    );
    await client.stopEndpoint();

    expect(info.nodeId, 'node-1');
    expect(info.endpointAddr, 'endpoint-1');
    expect(native.stopped, isTrue);
    await native.close();
  });

  test(
    'bridge client delegates peer connect, send, and buffer queries',
    () async {
      final native = FakeIrohNativeApi()..pendingBytes = 42;
      final client = IrohBridgeClient(native);

      await client.connectPeer(
        peerId: 'bob',
        endpointAddr: 'bob-endpoint',
        expectedNodeId: 'bob-node',
        alpn: 'rain.p2p.quic.v1',
        connectAttemptId: 'attempt-1',
        sessionSecret: 'secret',
      );
      await client.send(peerId: 'bob', channel: 'rain.chat', payload: 'hello');
      await client.disconnectPeer(peerId: 'bob');
      final buffered = await client.bufferedAmount(
        peerId: 'bob',
        channel: 'rain.chat',
      );

      expect(native.connectedPeerId, 'bob');
      expect(native.disconnectedPeerId, 'bob');
      expect(native.sentPayloads, <Object>['hello']);
      expect(buffered, 42);
      await native.close();
    },
  );

  test('bridge client forwards transport events', () async {
    final native = FakeIrohNativeApi();
    final client = IrohBridgeClient(native);
    final eventFuture = client.eventStream().first;

    native.events.add(
      IrohTransportEvent(
        type: IrohTransportEventType.data,
        peerId: 'bob',
        channel: 'rain.chat',
        payload: null,
        receivedAt: DateTime.fromMillisecondsSinceEpoch(1),
      ),
    );

    final event = await eventFuture;
    expect(event.type, IrohTransportEventType.data);
    expect(event.peerId, 'bob');
    await native.close();
  });
}
