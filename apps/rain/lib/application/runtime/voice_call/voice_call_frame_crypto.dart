import 'package:protocol_brain/protocol_brain.dart';

import '../rain_runtime_controller.dart';

/// Encryption of voice-call signaling frames: per-pair (`v=2`) when both
/// users published a key, the shared-key `v=1` cipher otherwise.
extension VoiceCallFrameCrypto on RainRuntimeController {
  Future<VoiceSignalingEnvelope> encryptVoiceFrame(
    VoiceCallFrame frame, {
    required String purpose,
    required int maxCiphertextLength,
  }) async {
    final pairCipher = await resolveVoicePairCipher(frame.from, frame.to);
    final encrypted = pairCipher != null
        ? await pairCipher.encryptPayloadV2(
            roomId: frame.callId,
            purpose: purpose,
            timestamp: frame.sentAt,
            sender: frame.from,
            receiver: frame.to,
            payload: frame.toJson(),
          )
        : await voiceSignalingCipher.encryptPayload(
            roomId: frame.callId,
            purpose: purpose,
            timestamp: frame.sentAt,
            sender: frame.from,
            receiver: frame.to,
            payload: frame.toJson(),
          );
    return VoiceSignalingEnvelope.fromJson(
      Map<Object?, Object?>.from(encrypted),
      maxCiphertextLength: maxCiphertextLength,
    );
  }

  Future<VoiceCallFrame> decryptVoiceFrame({
    required String callId,
    required VoiceSignalingEnvelope envelope,
    required String purpose,
  }) async {
    final payload = envelope.toJson(
      maxCiphertextLength:
          purpose == SignalingCipher.offerPurpose ||
              purpose == SignalingCipher.answerPurpose
          ? VoiceSignalingEnvelope.maxSdpCiphertextLength
          : VoiceSignalingEnvelope.maxIceCiphertextLength,
    );
    final Map<Object?, Object?> decrypted;
    if (envelope.v == VoiceSignalingEnvelope.versionPerPair) {
      final pairCipher = await resolveVoicePairCipher(
        envelope.sender ?? '',
        envelope.receiver ?? '',
      );
      if (pairCipher == null) {
        throw const FormatException(
          'Per-pair voice envelope cannot be decrypted without a pair key.',
        );
      }
      decrypted = await pairCipher.decryptPayloadV2(
        roomId: callId,
        purpose: purpose,
        payload: payload,
        sender: envelope.sender,
        receiver: envelope.receiver,
      );
    } else {
      decrypted = await voiceSignalingCipher.decryptPayload(
        roomId: callId,
        purpose: purpose,
        payload: payload,
      );
    }
    return VoiceCallFrame.fromJson(Map<String, Object?>.from(decrypted));
  }

  /// Per-pair cipher for the other participant, or null to use `v=1`.
  Future<SignalingCipher?> resolveVoicePairCipher(
    String sender,
    String receiver,
  ) {
    final resolver = voicePairCipherResolver;
    if (resolver == null) {
      return Future<SignalingCipher?>.value();
    }
    final local = normalizeUsername(selfIdentity.username);
    final peer = normalizeUsername(sender) == local ? receiver : sender;
    return resolver(normalizeUsername(peer));
  }
}
