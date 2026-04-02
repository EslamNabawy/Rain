import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  test('username validation matches spec constraints', () {
    expect(RainIdentity.isValidUsername('alice_01'), isTrue);
    expect(RainIdentity.isValidUsername('ALICE'), isFalse);
    expect(RainIdentity.isValidUsername('ab'), isFalse);
  });

  test('displayTime falls back to receipt time when skew is large', () {
    final envelope = MessageEnvelope(
      id: '1',
      from: 'alice',
      to: 'bob',
      content: 'hi',
      sentAt: DateTime.now().subtract(const Duration(minutes: 10)).millisecondsSinceEpoch,
      seq: 1,
      type: MessageType.text,
    );

    final receipt = DateTime.now();
    expect(displayTime(envelope, receipt), receipt);
  });

  test('identity repository preserves gender', () async {
    final database = RainDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    await IdentityRepository(database).saveIdentity(
      const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: RainGender.female,
      ),
    );

    final loaded = await IdentityRepository(database).loadIdentity();
    expect(loaded?.gender, RainGender.female);
  });
}
