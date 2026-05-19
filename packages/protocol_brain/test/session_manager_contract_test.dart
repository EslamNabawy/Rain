import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';

void main() {
  test('ConnectionType includes Iroh for fallback transport', () {
    expect(ConnectionType.values, contains(ConnectionType.iroh));
  });

  test('Iroh sessions still use existing Rain channels', () {
    expect(SessionChannel.values, contains(SessionChannel.chat));
    expect(SessionChannel.values, contains(SessionChannel.control));
    expect(SessionChannel.values, contains(SessionChannel.file));
  });
}
