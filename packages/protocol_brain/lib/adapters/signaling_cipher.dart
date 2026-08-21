import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Resolves a per-pair [SignalingCipher] for a given peer.
///
/// F-015 (Phase 1 wiring): the adapter calls this to obtain a per-pair cipher
/// keyed to the remote peer's X25519 public key (via ECDH). Returns `null` if
/// no per-pair key can be derived (e.g. the peer hasn't published a signing
/// key yet); callers fall back to the v=1 shared-key cipher in that case.
typedef SignalingCipherResolver =
    Future<SignalingCipher?> Function(String peerUsername);

class SignalingCipher {
  SignalingCipher.fromKeyMaterial(String keyMaterial)
    : this._(rootKey: SecretKey(utf8.encode(keyMaterial.trim())));

  SignalingCipher._({
    required SecretKey rootKey,
    String? pairFrom,
    String? pairTo,
    String? sessionId,
    bool isDemo = false,
  }) : _rootKey = rootKey,
       _pairFrom = pairFrom,
       _pairTo = pairTo,
       _sessionId = sessionId,
       _isDemo = isDemo;

  /// TASK-001 (crypto core, additive): per-pair cipher.
  ///
  /// Derives keys from `pairKeyMaterial` bound to the `from`/`to`/`sessionId`
  /// context via HKDF, with a random per-envelope salt (see `encryptPayloadV2`).
  /// Does NOT change the `v=1` shared-root path; the adapter wiring + `v=1`
  /// fallback window are deferred (need emulator verification).
  ///
  /// C-03 fix: `pairKeyMaterial` is the base64-encoded raw ECDH shared secret
  /// from `IdentityKeyRepository.derivePairKeyMaterial`. We decode the base64
  /// to raw bytes before using it as the HKDF root key, so `forPair` and
  /// `forPairRootKey` derive the same key for the same secret (previously
  /// `forPair` used `utf8.encode(base64String)` → 44 bytes vs 32 raw).
  factory SignalingCipher.forPair({
    required String pairKeyMaterial,
    required String from,
    required String to,
    String? sessionId,
  }) {
    final trimmed = pairKeyMaterial.trim();
    List<int> raw;
    try {
      raw = base64Decode(trimmed);
    } catch (_) {
      // Fallback: also accept base64Url (KeyEncoding uses standard base64,
      // but be permissive). If neither decodes, treat as raw material
      // to preserve backward compat with any test that passed a non-base64
      // string (e.g. "pair-secret").
      try {
        raw = base64Url.decode(trimmed);
      } catch (_) {
        raw = utf8.encode(trimmed);
      }
    }
    // If decoded bytes look like UTF-8 of base64 (should not happen), guard
    // against empty.
    if (raw.isEmpty) {
      raw = utf8.encode(trimmed);
    }
    return SignalingCipher._(
      rootKey: SecretKey(raw),
      pairFrom: from,
      pairTo: to,
      sessionId: sessionId,
    );
  }

  /// F-015 (Phase 1 wiring): per-pair cipher from raw ECDH shared secret bytes.
  ///
  /// [IdentityKeyRepository.derivePairKeyMaterial] returns a base64-encoded
  /// raw ECDH shared secret. This factory accepts the raw bytes directly so
  /// the adapter doesn't need to re-encode. The bytes are used verbatim as
  /// the HKDF root key material.
  factory SignalingCipher.forPairRootKey({
    required List<int> rootKeyBytes,
    required String from,
    required String to,
    String? sessionId,
  }) {
    return SignalingCipher._(
      rootKey: SecretKey(rootKeyBytes),
      pairFrom: from,
      pairTo: to,
      sessionId: sessionId,
    );
  }

  factory SignalingCipher.demo() {
    return SignalingCipher._(
      rootKey: SecretKey(utf8.encode(demoKeyMaterial)),
      isDemo: true,
    );
  }

  /// F-015 / MED-5 (Phase 1): `true` when this cipher was created via
  /// [SignalingCipher.demo()]. Release guards use this to block shipping
  /// production builds that haven't wired per-pair E2E.
  bool get isDemo => _isDemo;
  final bool _isDemo;

  static const String demoKeyMaterial =
      'rain-demo-signaling-encryption-key-v1-change-me';
  static const int envelopeVersion = 1;
  static const int envelopeVersionV2 = 2;
  static const String algorithmName = 'A256GCM-HKDF-SHA256';
  static const String offerPurpose = 'offer';
  static const String answerPurpose = 'answer';
  static const String callerIcePurpose = 'callerICE';
  static const String calleeIcePurpose = 'calleeICE';

  static const List<int> _salt = <int>[
    114,
    97,
    105,
    110,
    45,
    115,
    105,
    103,
    110,
    97,
    108,
    105,
    110,
    103,
    45,
    118,
    49,
  ];

  /// Random salt length (bytes) for `v=2` per-envelope key derivation.
  static const int _v2SaltLength = 16;

  final SecretKey _rootKey;
  final String? _pairFrom;
  final String? _pairTo;
  final String? _sessionId;
  final AesGcm _cipher = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Future<Map<String, Object?>> encryptPayload({
    required String roomId,
    required String purpose,
    required int timestamp,
    required String sender,
    required String receiver,
    required Map<String, Object?> payload,
  }) async {
    final normalizedSender = _normalizeContextPeer('sender', sender);
    final normalizedReceiver = _normalizeContextPeer('receiver', receiver);
    final secretKey = await _deriveRoomKey(roomId: roomId, purpose: purpose);
    final clearText = utf8.encode(jsonEncode(payload));
    final secretBox = await _cipher.encrypt(
      clearText,
      secretKey: secretKey,
      aad: _aad(
        roomId: roomId,
        purpose: purpose,
        timestamp: timestamp,
        sender: normalizedSender,
        receiver: normalizedReceiver,
      ),
    );

    return <String, Object?>{
      'v': envelopeVersion,
      'alg': algorithmName,
      'ts': timestamp,
      'from': normalizedSender,
      'to': normalizedReceiver,
      'nonce': base64Url.encode(secretBox.nonce),
      'ciphertext': base64Url.encode(secretBox.cipherText),
      'mac': base64Url.encode(secretBox.mac.bytes),
    };
  }

  Future<Map<Object?, Object?>> decryptPayload({
    required String roomId,
    required String purpose,
    required Map<Object?, Object?> payload,
    String? sender,
    String? receiver,
  }) async {
    if (!isEncryptedEnvelope(payload) && !isEncryptedEnvelopeV2(payload)) {
      return payload;
    }

    // TASK-001.4 (Phase 4 verifiable slice): auto-route v=2 envelopes.
    //
    // When the adapter is eventually wired to use per-pair ciphers
    // (TASK-001.3, deferred for emulator verification), older builds that
    // only know v=1 must still be able to decrypt v=2 if they hold the
    // correct per-pair key. Routing here keeps the adapter untouched.
    if (isEncryptedEnvelopeV2(payload)) {
      return decryptPayloadV2(
        roomId: roomId,
        purpose: purpose,
        payload: payload,
        sender: sender,
        receiver: receiver,
      );
    }

    try {
      final timestamp = (payload['ts'] as num?)?.toInt();
      if (timestamp == null) {
        throw const FormatException('Missing encrypted signaling timestamp.');
      }
      final nonce = _decodeRequiredBase64(payload, 'nonce');
      final cipherText = _decodeRequiredBase64(payload, 'ciphertext');
      final mac = _decodeRequiredBase64(payload, 'mac');
      final envelopeSender = _optionalContextPeer(payload, 'from');
      final envelopeReceiver = _optionalContextPeer(payload, 'to');
      final expectedSender = sender == null
          ? null
          : _normalizeContextPeer('sender', sender);
      final expectedReceiver = receiver == null
          ? null
          : _normalizeContextPeer('receiver', receiver);
      if (envelopeSender != null &&
          expectedSender != null &&
          envelopeSender != expectedSender) {
        throw FormatException(
          'Encrypted signaling sender mismatch: expected $expectedSender.',
        );
      }
      if (envelopeReceiver != null &&
          expectedReceiver != null &&
          envelopeReceiver != expectedReceiver) {
        throw FormatException(
          'Encrypted signaling receiver mismatch: expected $expectedReceiver.',
        );
      }
      final secretKey = await _deriveRoomKey(roomId: roomId, purpose: purpose);
      final clearText = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
        aad: _aad(
          roomId: roomId,
          purpose: purpose,
          timestamp: timestamp,
          sender: envelopeSender,
          receiver: envelopeReceiver,
        ),
      );
      final decoded = jsonDecode(utf8.decode(clearText));
      if (decoded is! Map) {
        throw const FormatException('Encrypted signaling payload is not JSON.');
      }
      return Map<Object?, Object?>.from(decoded);
    } on SignalingEncryptionException {
      rethrow;
    } catch (error) {
      throw SignalingEncryptionException(
        'Unable to decrypt $purpose signaling payload for room $roomId.',
        error,
      );
    }
  }

  static bool isEncryptedEnvelope(Map<Object?, Object?> payload) {
    return payload['v'] == envelopeVersion &&
        payload['alg'] == algorithmName &&
        payload['nonce'] is String &&
        payload['ciphertext'] is String &&
        payload['mac'] is String;
  }

  /// TASK-001 (crypto core, additive).
  ///
  /// Encrypts with a per-pair, per-envelope key: HKDF binds the key to
  /// `from`/`to`/`sessionId`/`roomId`/`purpose`/`v=2`, and a fresh random 16-byte
  /// salt is embedded in the envelope on every call. This makes the ciphertext
  /// unlinkable across envelopes even with the same pair key.
  ///
  /// Does NOT modify the `v=1` path; the adapter wiring + `v=1` fallback window
  /// remain deferred (need emulator verification).
  Future<Map<String, Object?>> encryptPayloadV2({
    required String roomId,
    required String purpose,
    required int timestamp,
    required String sender,
    required String receiver,
    required Map<String, Object?> payload,
  }) async {
    final normalizedSender = _normalizeContextPeer('sender', sender);
    final normalizedReceiver = _normalizeContextPeer('receiver', receiver);
    final salt = _randomSalt();
    final secretKey = await _derivePairKey(
      roomId: roomId,
      purpose: purpose,
      salt: salt,
    );
    final clearText = utf8.encode(jsonEncode(payload));
    final secretBox = await _cipher.encrypt(
      clearText,
      secretKey: secretKey,
      aad: _aadV2(
        roomId: roomId,
        purpose: purpose,
        timestamp: timestamp,
        sender: normalizedSender,
        receiver: normalizedReceiver,
      ),
    );

    return <String, Object?>{
      'v': envelopeVersionV2,
      'alg': algorithmName,
      'ts': timestamp,
      'from': normalizedSender,
      'to': normalizedReceiver,
      'salt': base64Url.encode(salt),
      'nonce': base64Url.encode(secretBox.nonce),
      'ciphertext': base64Url.encode(secretBox.cipherText),
      'mac': base64Url.encode(secretBox.mac.bytes),
    };
  }

  /// TASK-001 (crypto core, additive). Decrypts a `v=2` envelope.
  ///
  /// Requires the same per-pair cipher (matching `from`/`to`/`sessionId`) that
  /// produced the envelope. A holder of only the app-wide `v=1` root key cannot
  /// derive the per-pair key, so `decryptPayloadV2` fails for them.
  Future<Map<Object?, Object?>> decryptPayloadV2({
    required String roomId,
    required String purpose,
    required Map<Object?, Object?> payload,
    String? sender,
    String? receiver,
  }) async {
    if (payload['v'] != envelopeVersionV2) {
      throw const SignalingEncryptionException(
        'Not a v=2 encrypted signaling envelope.',
      );
    }

    try {
      final timestamp = (payload['ts'] as num?)?.toInt();
      if (timestamp == null) {
        throw const FormatException('Missing encrypted signaling timestamp.');
      }
      final salt = _decodeRequiredBase64(payload, 'salt');
      final nonce = _decodeRequiredBase64(payload, 'nonce');
      final cipherText = _decodeRequiredBase64(payload, 'ciphertext');
      final mac = _decodeRequiredBase64(payload, 'mac');
      final envelopeSender = _optionalContextPeer(payload, 'from');
      final envelopeReceiver = _optionalContextPeer(payload, 'to');
      final expectedSender = sender == null
          ? null
          : _normalizeContextPeer('sender', sender);
      final expectedReceiver = receiver == null
          ? null
          : _normalizeContextPeer('receiver', receiver);
      if (envelopeSender != null &&
          expectedSender != null &&
          envelopeSender != expectedSender) {
        throw FormatException(
          'Encrypted signaling sender mismatch: expected $expectedSender.',
        );
      }
      if (envelopeReceiver != null &&
          expectedReceiver != null &&
          envelopeReceiver != expectedReceiver) {
        throw FormatException(
          'Encrypted signaling receiver mismatch: expected $expectedReceiver.',
        );
      }
      final secretKey = await _derivePairKey(
        roomId: roomId,
        purpose: purpose,
        salt: salt,
      );
      final clearText = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: secretKey,
        aad: _aadV2(
          roomId: roomId,
          purpose: purpose,
          timestamp: timestamp,
          sender: envelopeSender,
          receiver: envelopeReceiver,
        ),
      );
      final decoded = jsonDecode(utf8.decode(clearText));
      if (decoded is! Map) {
        throw const FormatException('Encrypted signaling payload is not JSON.');
      }
      return Map<Object?, Object?>.from(decoded);
    } on SignalingEncryptionException {
      rethrow;
    } catch (error) {
      throw SignalingEncryptionException(
        'Unable to decrypt $purpose v=2 signaling payload for room $roomId.',
        error,
      );
    }
  }

  static bool isEncryptedEnvelopeV2(Map<Object?, Object?> payload) {
    return payload['v'] == envelopeVersionV2 &&
        payload['alg'] == algorithmName &&
        payload['salt'] is String &&
        payload['nonce'] is String &&
        payload['ciphertext'] is String &&
        payload['mac'] is String;
  }

  Future<SecretKey> _deriveRoomKey({
    required String roomId,
    required String purpose,
  }) {
    return _hkdf.deriveKey(
      secretKey: _rootKey,
      nonce: _salt,
      info: utf8.encode('room=$roomId;purpose=$purpose;v=$envelopeVersion'),
    );
  }

  /// TASK-001 (crypto core). Per-pair, per-envelope key derivation.
  ///
  /// Binds the derived key to the friendship (`from`/`to`), the call session
  /// (`sessionId`), the room, and the purpose, plus a random `salt` that is
  /// unique per envelope. A different `salt` (or different pair context) yields
  /// a different key, so a `v=1` root-key holder cannot reproduce it.
  Future<SecretKey> _derivePairKey({
    required String roomId,
    required String purpose,
    required List<int> salt,
  }) {
    final from = _pairFrom ?? '';
    final to = _pairTo ?? '';
    final session = _sessionId ?? '';
    return _hkdf.deriveKey(
      secretKey: _rootKey,
      nonce: salt,
      info: utf8.encode(
        'from=$from;to=$to;session=$session;'
        'room=$roomId;purpose=$purpose;v=$envelopeVersionV2',
      ),
    );
  }

  List<int> _aadV2({
    required String roomId,
    required String purpose,
    required int timestamp,
    String? sender,
    String? receiver,
  }) {
    if (sender == null || receiver == null) {
      return utf8.encode(
        'rain.signaling|v=$envelopeVersionV2|alg=$algorithmName|'
        'room=$roomId|purpose=$purpose|ts=$timestamp',
      );
    }
    return utf8.encode(
      'rain.signaling|v=$envelopeVersionV2|alg=$algorithmName|'
      'room=$roomId|purpose=$purpose|from=$sender|to=$receiver|ts=$timestamp',
    );
  }

  List<int> _randomSalt() {
    final rng = Random.secure();
    final salt = List<int>.filled(_v2SaltLength, 0);
    for (var i = 0; i < _v2SaltLength; i += 1) {
      salt[i] = rng.nextInt(256);
    }
    return salt;
  }

  List<int> _aad({
    required String roomId,
    required String purpose,
    required int timestamp,
    String? sender,
    String? receiver,
  }) {
    if (sender == null || receiver == null) {
      return utf8.encode(
        'rain.signaling|v=$envelopeVersion|alg=$algorithmName|room=$roomId|purpose=$purpose|ts=$timestamp',
      );
    }
    return utf8.encode(
      'rain.signaling|v=$envelopeVersion|alg=$algorithmName|room=$roomId|purpose=$purpose|from=$sender|to=$receiver|ts=$timestamp',
    );
  }

  List<int> _decodeRequiredBase64(Map<Object?, Object?> payload, String field) {
    final value = payload[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('Missing encrypted signaling $field.');
    }
    return base64Url.decode(value);
  }

  String _normalizeContextPeer(String field, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw FormatException('Encrypted signaling $field is empty.');
    }
    return normalized;
  }

  String? _optionalContextPeer(Map<Object?, Object?> payload, String field) {
    final value = payload[field];
    if (value == null) {
      return null;
    }
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Encrypted signaling $field is invalid.');
    }
    return value.trim().toLowerCase();
  }
}

class SignalingEncryptionException implements Exception {
  const SignalingEncryptionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' Cause: $cause';
    return '$message$suffix';
  }
}
