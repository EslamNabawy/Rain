import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/security/pair_cipher_resolver.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

class _KeyDirectoryAdapter extends NoopSignalingAdapter {
  final Map<String, String?> keys = <String, String?>{};
  int fetches = 0;

  @override
  Future<BackendIdentity?> fetchIdentity(String username) async {
    fetches += 1;
    if (!keys.containsKey(username)) {
      return null;
    }
    return BackendIdentity(
      username: username,
      uid: 'uid-$username',
      displayName: username,
      gender: null,
      registeredAt: 1,
      lastSeen: 1,
      lastHeartbeat: 1,
      online: true,
      signingPublicKey: keys[username],
    );
  }
}

Future<IdentityKeyRepository> _repo(RainDatabase db) async {
  await db
      .into(db.identityTable)
      .insert(
        IdentityTableCompanion.insert(
          username: 'x',
          displayName: 'x',
          createdAt: 1,
        ),
      );
  final repo = IdentityKeyRepository(db, InMemoryKeyStoreService());
  await repo.ensureKeyPair();
  return repo;
}

void main() {
  late RainDatabase dbA;
  late RainDatabase dbB;
  late IdentityKeyRepository alice;
  late IdentityKeyRepository bob;
  late _KeyDirectoryAdapter directory;

  setUp(() async {
    dbA = RainDatabase(NativeDatabase.memory());
    dbB = RainDatabase(NativeDatabase.memory());
    alice = await _repo(dbA);
    bob = await _repo(dbB);
    directory = _KeyDirectoryAdapter();
    directory.keys['alice'] = await alice.encodedPublicKey();
    directory.keys['bob'] = await bob.encodedPublicKey();
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  test('both users resolve interoperable v=2 ciphers', () async {
    final aliceResolver = buildAppPairCipherResolver(
      adapter: directory,
      identityKeys: alice,
      localUsername: () => 'alice',
    );
    final bobResolver = buildAppPairCipherResolver(
      adapter: directory,
      identityKeys: bob,
      localUsername: () => 'bob',
    );

    final envelope = await (await aliceResolver('bob'))!.encryptPayloadV2(
      roomId: 'call-1',
      purpose: SignalingCipher.offerPurpose,
      timestamp: 5,
      sender: 'alice',
      receiver: 'bob',
      payload: <String, Object?>{'sdp': 'offer'},
    );
    final decrypted = await (await bobResolver('alice'))!.decryptPayloadV2(
      roomId: 'call-1',
      purpose: SignalingCipher.offerPurpose,
      payload: envelope,
      sender: 'alice',
      receiver: 'bob',
    );

    expect(envelope['v'], 2);
    expect(decrypted['sdp'], 'offer');
  });

  test('falls back to v=1 when the peer has no published key', () async {
    directory.keys['bob'] = null;
    final resolver = buildAppPairCipherResolver(
      adapter: directory,
      identityKeys: alice,
      localUsername: () => 'alice',
    );

    expect(await resolver('bob'), isNull);
  });

  test('falls back when this device key is not the published one', () async {
    directory.keys['alice'] = 'B' * 43 + '=';
    final resolver = buildAppPairCipherResolver(
      adapter: directory,
      identityKeys: alice,
      localUsername: () => 'alice',
    );

    expect(await resolver('bob'), isNull);
  });

  test('caches the derived secret per peer', () async {
    final resolver = buildAppPairCipherResolver(
      adapter: directory,
      identityKeys: alice,
      localUsername: () => 'alice',
    );

    await resolver('bob');
    final afterFirst = directory.fetches;
    await resolver('bob');

    expect(directory.fetches, afterFirst);
  });
}
