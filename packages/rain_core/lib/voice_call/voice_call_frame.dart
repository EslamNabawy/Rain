import 'dart:convert';

enum VoiceCallFrameType {
  invite,
  accept,
  reject,
  busy,
  offer,
  answer,
  hangup,
  mute,
}

class VoiceCallFrame {
  const VoiceCallFrame({
    required this.type,
    required this.callId,
    required this.from,
    required this.to,
    required this.sentAt,
    this.reason,
    this.muted,
    this.sdp,
    this.sdpType,
  });

  static const String wireType = 'voice_call';
  static const int maxIdLength = 128;
  static const int maxUsernameLength = 64;
  static const int maxReasonLength = 256;
  static const int maxSdpLength = 262144;

  final VoiceCallFrameType type;
  final String callId;
  final String from;
  final String to;
  final int sentAt;
  final String? reason;
  final bool? muted;
  final String? sdp;
  final String? sdpType;

  bool get carriesSessionDescription {
    return type == VoiceCallFrameType.offer ||
        type == VoiceCallFrameType.answer;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': wireType,
      'action': type.name,
      'callId': callId,
      'from': from,
      'to': to,
      'sentAt': sentAt,
      if (reason != null) 'reason': reason,
      if (muted != null) 'muted': muted,
      if (sdp != null) 'sdp': sdp,
      if (sdpType != null) 'sdpType': sdpType,
    };
  }

  String encode() => jsonEncode(toJson());

  static VoiceCallFrame decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Voice call frame must be a JSON object.');
    }
    return fromJson(decoded);
  }

  static VoiceCallFrame? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> ||
          decoded['type'] != VoiceCallFrame.wireType) {
        return null;
      }
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  static VoiceCallFrame fromJson(Map<String, Object?> json) {
    if (json['type'] != wireType) {
      throw const FormatException('Not a voice call frame.');
    }
    final action = _requiredString(json, 'action', max: 32);
    final frameType = VoiceCallFrameType.values
        .where((VoiceCallFrameType value) => value.name == action)
        .firstOrNull;
    if (frameType == null) {
      throw FormatException('Unknown voice call action: $action');
    }

    final frame = VoiceCallFrame(
      type: frameType,
      callId: _requiredString(json, 'callId', max: maxIdLength),
      from: _requiredString(json, 'from', max: maxUsernameLength),
      to: _requiredString(json, 'to', max: maxUsernameLength),
      sentAt: _requiredInt(json, 'sentAt'),
      reason: _optionalString(json, 'reason', max: maxReasonLength),
      muted: _optionalBool(json, 'muted'),
      sdp: _optionalString(json, 'sdp', max: maxSdpLength),
      sdpType: _optionalString(json, 'sdpType', max: 16),
    );
    frame._validateShape();
    return frame;
  }

  void _validateShape() {
    if (sentAt <= 0) {
      throw const FormatException('Voice call sentAt must be positive.');
    }
    if (carriesSessionDescription) {
      if (sdp == null || sdp!.isEmpty) {
        throw const FormatException('Voice call media frame requires SDP.');
      }
      if (sdpType != 'offer' && sdpType != 'answer') {
        throw const FormatException(
          'Voice call media frame has invalid SDP type.',
        );
      }
      if (type == VoiceCallFrameType.offer && sdpType != 'offer') {
        throw const FormatException('Offer frame must carry offer SDP.');
      }
      if (type == VoiceCallFrameType.answer && sdpType != 'answer') {
        throw const FormatException('Answer frame must carry answer SDP.');
      }
      return;
    }
    if (sdp != null || sdpType != null) {
      throw const FormatException(
        'Only media offer/answer frames may carry SDP.',
      );
    }
    if (type == VoiceCallFrameType.mute && muted == null) {
      throw const FormatException('Mute frame requires muted flag.');
    }
    if (type != VoiceCallFrameType.mute && muted != null) {
      throw const FormatException('Only mute frames may carry muted flag.');
    }
  }

  static String _requiredString(
    Map<String, Object?> json,
    String key, {
    required int max,
  }) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('Voice call $key must be a string.');
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > max) {
      throw FormatException('Voice call $key length is invalid.');
    }
    return trimmed;
  }

  static String? _optionalString(
    Map<String, Object?> json,
    String key, {
    required int max,
  }) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('Voice call $key must be a string.');
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > max) {
      throw FormatException('Voice call $key length is invalid.');
    }
    return trimmed;
  }

  static int _requiredInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite && value.roundToDouble() == value) {
      return value.toInt();
    }
    throw FormatException('Voice call $key must be an integer.');
  }

  static bool? _optionalBool(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    throw FormatException('Voice call $key must be a boolean.');
  }
}
