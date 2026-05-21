import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  test('IrohAddressPayload round trips through json', () {
    const payload = IrohAddressPayload(
      protocolVersion: 1,
      connectAttemptId: 'attempt-1',
      username: 'alice',
      nodeId: 'node-1',
      endpointAddr: 'endpoint-addr-1',
      sessionSecret: 'secret-1',
      createdAt: 1000,
      expiresAt: 31000,
    );

    expect(IrohAddressPayload.fromJson(payload.toJson()), payload);
  });

  test('IrohAddressPayload rejects expired attempts', () {
    const payload = IrohAddressPayload(
      protocolVersion: 1,
      connectAttemptId: 'attempt-1',
      username: 'alice',
      nodeId: 'node-1',
      endpointAddr: 'endpoint-addr-1',
      sessionSecret: 'secret-1',
      createdAt: 1000,
      expiresAt: 31000,
    );

    expect(payload.isUsableAt(30000), isTrue);
    expect(payload.isUsableAt(31001), isFalse);
  });

  test('IrohAddressPayload rejects mismatched attempt or username', () {
    const payload = IrohAddressPayload(
      protocolVersion: 1,
      connectAttemptId: 'attempt-1',
      username: 'alice',
      nodeId: 'node-1',
      endpointAddr: 'endpoint-addr-1',
      sessionSecret: 'secret-1',
      createdAt: 1000,
      expiresAt: 31000,
    );

    expect(
      payload.matches(username: 'alice', connectAttemptId: 'attempt-1'),
      isTrue,
    );
    expect(
      payload.matches(username: 'bob', connectAttemptId: 'attempt-1'),
      isFalse,
    );
    expect(
      payload.matches(username: 'alice', connectAttemptId: 'attempt-2'),
      isFalse,
    );
  });
}
