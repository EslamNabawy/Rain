import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

/// Builds the app's per-pair (`v=2`) cipher resolver.
///
/// A pair secret is only returned when both sides can decrypt it: the peer must
/// have published a key and this device's own key must be the one published for
/// the account. Anything else resolves to null so callers use the `v=1` cipher.
/// Secrets are cached for [cacheTtl] because every signaling frame asks.
SignalingCipherResolver buildAppPairCipherResolver({
  required SignalingAdapter adapter,
  required IdentityKeyRepository identityKeys,
  required String? Function() localUsername,
  Duration cacheTtl = const Duration(minutes: 2),
  DateTime Function() now = DateTime.now,
}) {
  final cache = <String, ({List<int>? secret, DateTime at})>{};

  Future<List<int>?> derive(String peer) async {
    final cached = cache[peer];
    if (cached != null && now().difference(cached.at) < cacheTtl) {
      return cached.secret;
    }
    final secret = await _deriveUncached(
      adapter: adapter,
      identityKeys: identityKeys,
      local: localUsername(),
      peer: peer,
    );
    cache[peer] = (secret: secret, at: now());
    return secret;
  }

  return buildPairCipherResolver(
    localUsername: localUsername,
    deriveSharedSecret: derive,
  );
}

Future<List<int>?> _deriveUncached({
  required SignalingAdapter adapter,
  required IdentityKeyRepository identityKeys,
  required String? local,
  required String peer,
}) async {
  if (local == null || local.isEmpty) {
    return null;
  }
  final localKey = await identityKeys.encodedPublicKey();
  if (localKey == null) {
    return null;
  }
  final published = (await adapter.fetchIdentity(local))?.signingPublicKey;
  if (published != localKey) {
    return null;
  }
  final peerKey = (await adapter.fetchIdentity(peer))?.signingPublicKey;
  if (peerKey == null || peerKey.isEmpty) {
    return null;
  }
  return identityKeys.deriveSharedSecretFromEncodedKey(peerKey);
}
