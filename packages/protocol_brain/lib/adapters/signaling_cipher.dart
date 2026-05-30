import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class SignalingCipher {
  SignalingCipher.fromKeyMaterial(String keyMaterial)
    : _rootKey = SecretKey(utf8.encode(keyMaterial.trim()));

  factory SignalingCipher.demo() {
    return SignalingCipher.fromKeyMaterial(demoKeyMaterial);
  }

  static const String demoKeyMaterial =
      'rain-demo-signaling-encryption-key-v1-change-me';
  static const int envelopeVersion = 1;
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

  final SecretKey _rootKey;
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
    if (!isEncryptedEnvelope(payload)) {
      return payload;
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
