import 'dart:convert';

enum VoiceCallFrameType {
  invite,
  accept,
  reject,
  busy,
  offer,
  answer,
  candidate,
  hangup,
  mute,
}

enum CallMediaMode { audio, video }

class VoiceCallFrame {
  const VoiceCallFrame({
    required this.type,
    required this.callId,
    required this.from,
    required this.to,
    required this.sentAt,
    this.seq = 1,
    this.sessionEpoch = 1,
    this.reason,
    this.reasonCode,
    this.muted,
    this.cameraMuted,
    this.mediaMode = CallMediaMode.audio,
    this.sdp,
    this.sdpType,
    this.mediaSeq,
    this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  static const String wireType = 'voice_call';
  static const int maxIdLength = 128;
  static const int maxUsernameLength = 64;
  static const int maxReasonLength = 256;
  static const int maxReasonCodeLength = 48;
  static const int maxSdpLength = 262144;
  static const int maxCandidateLength = 8192;

  final VoiceCallFrameType type;
  final String callId;
  final String from;
  final String to;
  final int sentAt;
  final int seq;
  final int sessionEpoch;
  final String? reason;
  final String? reasonCode;
  final bool? muted;
  final bool? cameraMuted;
  final CallMediaMode mediaMode;
  final String? sdp;
  final String? sdpType;
  final int? mediaSeq;
  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  bool get carriesSessionDescription {
    return type == VoiceCallFrameType.offer ||
        type == VoiceCallFrameType.answer;
  }

  bool get carriesIceCandidate => type == VoiceCallFrameType.candidate;

  Map<String, Object?> toJson() {
    _validateShape();
    return <String, Object?>{
      'type': wireType,
      'action': type.name,
      'callId': callId,
      'from': from,
      'to': to,
      'sentAt': sentAt,
      'seq': seq,
      'sessionEpoch': sessionEpoch,
      if (reason != null) 'reason': reason,
      if (reasonCode != null) 'reasonCode': reasonCode,
      if (muted != null) 'muted': muted,
      if (cameraMuted != null) 'cameraMuted': cameraMuted,
      if (mediaMode != CallMediaMode.audio) 'mediaMode': mediaMode.name,
      if (sdp != null) 'sdp': sdp,
      if (sdpType != null) 'sdpType': sdpType,
      if (mediaSeq != null) 'mediaSeq': mediaSeq,
      if (candidate != null) 'candidate': candidate,
      if (sdpMid != null) 'sdpMid': sdpMid,
      if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
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
      seq: _requiredPositiveInt(json, 'seq'),
      sessionEpoch: _requiredPositiveInt(json, 'sessionEpoch'),
      reason: _optionalString(json, 'reason', max: maxReasonLength),
      reasonCode: _optionalString(json, 'reasonCode', max: maxReasonCodeLength),
      muted: _optionalBool(json, 'muted'),
      cameraMuted: _optionalBool(json, 'cameraMuted'),
      mediaMode: _optionalMediaMode(json, 'mediaMode'),
      sdp: _optionalString(json, 'sdp', max: maxSdpLength, preserve: true),
      sdpType: _optionalString(json, 'sdpType', max: 16),
      mediaSeq: _optionalPositiveInt(json, 'mediaSeq'),
      candidate: _optionalString(
        json,
        'candidate',
        max: maxCandidateLength,
        preserve: true,
      ),
      sdpMid: _optionalString(json, 'sdpMid', max: 64, preserve: true),
      sdpMLineIndex: _optionalPositiveOrZeroInt(json, 'sdpMLineIndex'),
    );
    frame._validateShape();
    return frame;
  }

  void _validateShape() {
    if (sentAt <= 0) {
      throw const FormatException('Voice call sentAt must be positive.');
    }
    if (seq <= 0) {
      throw const FormatException('Voice call seq must be positive.');
    }
    if (sessionEpoch <= 0) {
      throw const FormatException('Voice call sessionEpoch must be positive.');
    }
    if (reasonCode != null &&
        type != VoiceCallFrameType.reject &&
        type != VoiceCallFrameType.busy &&
        type != VoiceCallFrameType.hangup) {
      throw const FormatException(
        'Only reject, busy, and hangup frames may carry reason codes.',
      );
    }
    if (type == VoiceCallFrameType.mute &&
        muted == null &&
        cameraMuted == null) {
      throw const FormatException(
        'Mute frame requires muted or cameraMuted flag.',
      );
    }
    if (type != VoiceCallFrameType.mute && muted != null) {
      throw const FormatException('Only mute frames may carry muted flag.');
    }
    if (type != VoiceCallFrameType.mute && cameraMuted != null) {
      throw const FormatException(
        'Only mute frames may carry cameraMuted flag.',
      );
    }
    if (carriesSessionDescription) {
      if (sdp == null || sdp!.trim().isEmpty) {
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
      if (candidate != null || sdpMid != null || sdpMLineIndex != null) {
        throw const FormatException(
          'Offer and answer frames may not carry ICE candidates.',
        );
      }
      return;
    }
    if (sdp != null || sdpType != null) {
      throw const FormatException(
        'Only media offer/answer frames may carry SDP.',
      );
    }
    if (mediaSeq != null) {
      throw const FormatException(
        'Only media offer/answer frames may carry media sequence.',
      );
    }
    if (carriesIceCandidate) {
      if (candidate == null || sdpMid == null || sdpMLineIndex == null) {
        throw const FormatException(
          'Voice call candidate frame requires candidate, sdpMid, and '
          'sdpMLineIndex.',
        );
      }
      return;
    }
    if (candidate != null || sdpMid != null || sdpMLineIndex != null) {
      throw const FormatException(
        'Only candidate frames may carry ICE candidates.',
      );
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
    bool preserve = false,
  }) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw FormatException('Voice call $key must be a string.');
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty || value.length > max) {
      throw FormatException('Voice call $key length is invalid.');
    }
    return preserve ? value : trimmed;
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

  static int _requiredPositiveInt(Map<String, Object?> json, String key) {
    final parsed = _requiredInt(json, key);
    if (parsed <= 0) {
      throw FormatException('Voice call $key must be positive.');
    }
    return parsed;
  }

  static int? _optionalPositiveInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    final parsed = _parseInt(value, key);
    if (parsed <= 0) {
      throw FormatException('Voice call $key must be positive.');
    }
    return parsed;
  }

  static int? _optionalPositiveOrZeroInt(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    final parsed = _parseInt(value, key);
    if (parsed < 0) {
      throw FormatException('Voice call $key must not be negative.');
    }
    return parsed;
  }

  static int _parseInt(Object? value, String key) {
    return switch (value) {
      final int raw => raw,
      final num raw when raw.isFinite && raw.roundToDouble() == raw =>
        raw.toInt(),
      _ => throw FormatException('Voice call $key must be an integer.'),
    };
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

  static CallMediaMode _optionalMediaMode(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return CallMediaMode.audio;
    }
    if (value is! String) {
      throw FormatException('Voice call $key must be a string.');
    }
    for (final mode in CallMediaMode.values) {
      if (mode.name == value) {
        return mode;
      }
    }
    throw FormatException('Unknown voice call media mode: $value');
  }
}
