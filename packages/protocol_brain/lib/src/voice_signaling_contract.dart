enum VoiceCallRole { caller, callee }

enum VoiceCallSignalingStatus {
  ringing,
  accepted,
  negotiating,
  connected,
  ended,
  failed,
  expired;

  bool get isTerminal {
    return switch (this) {
      VoiceCallSignalingStatus.ended ||
      VoiceCallSignalingStatus.failed ||
      VoiceCallSignalingStatus.expired => true,
      VoiceCallSignalingStatus.ringing ||
      VoiceCallSignalingStatus.accepted ||
      VoiceCallSignalingStatus.negotiating ||
      VoiceCallSignalingStatus.connected => false,
    };
  }
}

abstract interface class VoiceSignalingAdapter {
  Future<VoiceCallRoom> createOutgoingCall({
    required String callId,
    required String caller,
    required String callee,
    required int createdAt,
    required int expiresAt,
  });

  Future<VoiceCallRoom?> fetchCall(String callId);

  Stream<VoiceCallRoom?> watchCall(String callId);

  Stream<VoiceCallInboxEntry> watchIncomingCalls(String username);

  Future<void> acceptCall({
    required String callId,
    required String callee,
    required int acceptedAt,
  });

  Future<void> markConnected({
    required String callId,
    required String username,
    required int connectedAt,
  });

  Future<void> endCall({
    required String callId,
    required String username,
    required VoiceCallSignalingStatus status,
    required int endedAt,
    String? reasonCode,
    String? reason,
  });

  Future<void> setMuted({
    required String callId,
    required String username,
    required bool muted,
    required int updatedAt,
  });

  Future<void> writeVoiceOffer({
    required String callId,
    required String caller,
    required VoiceSignalingEnvelope offer,
    required int updatedAt,
  });

  Future<void> writeVoiceAnswer({
    required String callId,
    required String callee,
    required VoiceSignalingEnvelope answer,
    required int updatedAt,
  });

  Stream<VoiceSignalingEnvelope> watchVoiceOffer(String callId);

  Stream<VoiceSignalingEnvelope> watchVoiceAnswer(String callId);

  Future<String> writeIceCandidate({
    required String callId,
    required String username,
    required VoiceCallRole role,
    required VoiceSignalingEnvelope candidate,
    required int createdAt,
  });

  Stream<VoiceCallIceCandidateRecord> watchIceCandidates({
    required String callId,
    required VoiceCallRole role,
  });

  Future<void> deleteCall(String callId);

  Future<void> dispose();
}

final class VoiceSignalingEnvelope {
  const VoiceSignalingEnvelope({
    required this.v,
    required this.alg,
    required this.ts,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  static const int version = 1;
  static const String algorithmName = 'A256GCM-HKDF-SHA256';
  static const int maxNonceLength = 96;
  static const int maxMacLength = 96;
  static const int maxSdpCiphertextLength = 262144;
  static const int maxIceCiphertextLength = 32768;

  final int v;
  final String alg;
  final int ts;
  final String nonce;
  final String ciphertext;
  final String mac;

  Map<String, Object?> toJson({required int maxCiphertextLength}) {
    validate(maxCiphertextLength: maxCiphertextLength);
    return <String, Object?>{
      'v': v,
      'alg': alg,
      'ts': ts,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'mac': mac,
    };
  }

  factory VoiceSignalingEnvelope.fromJson(
    Map<Object?, Object?> json, {
    required int maxCiphertextLength,
  }) {
    final envelope = VoiceSignalingEnvelope(
      v: _requiredInt(json, 'v'),
      alg: _requiredString(json, 'alg', max: 64),
      ts: _requiredInt(json, 'ts'),
      nonce: _requiredString(json, 'nonce', max: maxNonceLength),
      ciphertext: _requiredString(json, 'ciphertext', max: maxCiphertextLength),
      mac: _requiredString(json, 'mac', max: maxMacLength),
    );
    envelope.validate(maxCiphertextLength: maxCiphertextLength);
    return envelope;
  }

  void validate({required int maxCiphertextLength}) {
    if (v != version) {
      throw const FormatException('Voice signaling envelope version invalid.');
    }
    if (alg != algorithmName) {
      throw const FormatException('Voice signaling envelope alg invalid.');
    }
    if (ts <= 0) {
      throw const FormatException('Voice signaling envelope ts invalid.');
    }
    _validateRequiredString('nonce', nonce, max: maxNonceLength);
    _validateRequiredString('ciphertext', ciphertext, max: maxCiphertextLength);
    _validateRequiredString('mac', mac, max: maxMacLength);
  }
}

final class VoiceActivePairLock {
  const VoiceActivePairLock({
    required this.pairId,
    required this.callId,
    required this.caller,
    required this.callee,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String pairId;
  final String callId;
  final String caller;
  final String callee;
  final int createdAt;
  final int updatedAt;
  final int expiresAt;

  Map<String, Object?> toJson() {
    _validateCallId(callId);
    _validatePairId(pairId);
    _validateUsername(caller);
    _validateUsername(callee);
    _validateTimestampOrder(createdAt: createdAt, updatedAt: updatedAt);
    _validateExpiresAt(createdAt: createdAt, expiresAt: expiresAt);
    return <String, Object?>{
      'callId': callId,
      'caller': caller,
      'callee': callee,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'expiresAt': expiresAt,
    };
  }

  factory VoiceActivePairLock.fromJson({
    required String pairId,
    required Map<Object?, Object?> json,
  }) {
    final lock = VoiceActivePairLock(
      pairId: pairId,
      callId: _requiredString(json, 'callId', max: _maxCallIdLength),
      caller: _requiredString(json, 'caller', max: _maxUsernameLength),
      callee: _requiredString(json, 'callee', max: _maxUsernameLength),
      createdAt: _requiredInt(json, 'createdAt'),
      updatedAt: _requiredInt(json, 'updatedAt'),
      expiresAt: _requiredInt(json, 'expiresAt'),
    );
    lock.toJson();
    return lock;
  }
}

final class VoiceCallInboxEntry {
  const VoiceCallInboxEntry({
    required this.callId,
    required this.from,
    required this.to,
    required this.pairId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
  });

  final String callId;
  final String from;
  final String to;
  final String pairId;
  final VoiceCallSignalingStatus status;
  final int createdAt;
  final int updatedAt;
  final int expiresAt;

  Map<String, Object?> toJson() {
    _validateCallId(callId);
    _validateUsername(from);
    _validateUsername(to);
    _validatePairId(pairId);
    _validateTimestampOrder(createdAt: createdAt, updatedAt: updatedAt);
    _validateExpiresAt(createdAt: createdAt, expiresAt: expiresAt);
    return <String, Object?>{
      'from': from,
      'to': to,
      'pairId': pairId,
      'status': status.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'expiresAt': expiresAt,
    };
  }

  factory VoiceCallInboxEntry.fromJson({
    required String callId,
    required Map<Object?, Object?> json,
  }) {
    final entry = VoiceCallInboxEntry(
      callId: callId,
      from: _requiredString(json, 'from', max: _maxUsernameLength),
      to: _requiredString(json, 'to', max: _maxUsernameLength),
      pairId: _requiredString(
        json,
        'pairId',
        max: (_maxUsernameLength * 2) + 1,
      ),
      status: voiceCallSignalingStatusFromName(
        _requiredString(json, 'status', max: 32),
      ),
      createdAt: _requiredInt(json, 'createdAt'),
      updatedAt: _requiredInt(json, 'updatedAt'),
      expiresAt: _requiredInt(json, 'expiresAt'),
    );
    entry.toJson();
    return entry;
  }
}

final class VoiceCallRoom {
  const VoiceCallRoom({
    required this.v,
    required this.callId,
    required this.pairId,
    required this.caller,
    required this.callee,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.expiresAt,
    this.acceptedAt,
    this.connectedAt,
    this.endedAt,
    this.endedBy,
    this.reasonCode,
    this.reason,
    this.muted = const <String, bool>{},
    this.offer,
    this.answer,
  });

  static const int version = 1;
  static const int maxReasonCodeLength = 48;
  static const int maxReasonLength = 256;

  final int v;
  final String callId;
  final String pairId;
  final String caller;
  final String callee;
  final VoiceCallSignalingStatus status;
  final int createdAt;
  final int updatedAt;
  final int expiresAt;
  final int? acceptedAt;
  final int? connectedAt;
  final int? endedAt;
  final String? endedBy;
  final String? reasonCode;
  final String? reason;
  final Map<String, bool> muted;
  final VoiceSignalingEnvelope? offer;
  final VoiceSignalingEnvelope? answer;

  bool get isTerminal => status.isTerminal;

  VoiceCallRoom copyWith({
    VoiceCallSignalingStatus? status,
    int? updatedAt,
    int? acceptedAt,
    int? connectedAt,
    int? endedAt,
    String? endedBy,
    String? reasonCode,
    String? reason,
    Map<String, bool>? muted,
    VoiceSignalingEnvelope? offer,
    VoiceSignalingEnvelope? answer,
  }) {
    return VoiceCallRoom(
      v: v,
      callId: callId,
      pairId: pairId,
      caller: caller,
      callee: callee,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      endedBy: endedBy ?? this.endedBy,
      reasonCode: reasonCode ?? this.reasonCode,
      reason: reason ?? this.reason,
      muted: Map<String, bool>.unmodifiable(muted ?? this.muted),
      offer: offer ?? this.offer,
      answer: answer ?? this.answer,
    );
  }

  Map<String, Object?> toJson() {
    validate();
    return <String, Object?>{
      'v': v,
      'pairId': pairId,
      'caller': caller,
      'callee': callee,
      'status': status.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'expiresAt': expiresAt,
      if (acceptedAt != null) 'acceptedAt': acceptedAt,
      if (connectedAt != null) 'connectedAt': connectedAt,
      if (endedAt != null) 'endedAt': endedAt,
      if (endedBy != null) 'endedBy': endedBy,
      if (reasonCode != null) 'reasonCode': reasonCode,
      if (reason != null) 'reason': reason,
      if (muted.isNotEmpty) 'muted': muted,
      if (offer != null)
        'offer': offer!.toJson(
          maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
        ),
      if (answer != null)
        'answer': answer!.toJson(
          maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
        ),
    };
  }

  factory VoiceCallRoom.fromJson({
    required String callId,
    required Map<Object?, Object?> json,
  }) {
    final mutedJson = json['muted'];
    final muted = <String, bool>{};
    if (mutedJson is Map<Object?, Object?>) {
      for (final entry in mutedJson.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is bool) {
          muted[key] = value;
        }
      }
    }

    VoiceSignalingEnvelope? sdpEnvelope(String key) {
      final value = json[key];
      if (value is! Map<Object?, Object?>) {
        return null;
      }
      return VoiceSignalingEnvelope.fromJson(
        value,
        maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
      );
    }

    final room = VoiceCallRoom(
      v: _requiredInt(json, 'v'),
      callId: callId,
      pairId: _requiredString(
        json,
        'pairId',
        max: (_maxUsernameLength * 2) + 1,
      ),
      caller: _requiredString(json, 'caller', max: _maxUsernameLength),
      callee: _requiredString(json, 'callee', max: _maxUsernameLength),
      status: voiceCallSignalingStatusFromName(
        _requiredString(json, 'status', max: 32),
      ),
      createdAt: _requiredInt(json, 'createdAt'),
      updatedAt: _requiredInt(json, 'updatedAt'),
      expiresAt: _requiredInt(json, 'expiresAt'),
      acceptedAt: _optionalInt(json, 'acceptedAt'),
      connectedAt: _optionalInt(json, 'connectedAt'),
      endedAt: _optionalInt(json, 'endedAt'),
      endedBy: _optionalString(json, 'endedBy', max: _maxUsernameLength),
      reasonCode: _optionalString(
        json,
        'reasonCode',
        max: VoiceCallRoom.maxReasonCodeLength,
      ),
      reason: _optionalString(
        json,
        'reason',
        max: VoiceCallRoom.maxReasonLength,
      ),
      muted: Map<String, bool>.unmodifiable(muted),
      offer: sdpEnvelope('offer'),
      answer: sdpEnvelope('answer'),
    );
    room.validate();
    return room;
  }

  void validate() {
    if (v != version) {
      throw const FormatException('Voice call room version invalid.');
    }
    _validateCallId(callId);
    _validatePairId(pairId);
    _validateUsername(caller);
    _validateUsername(callee);
    if (caller == callee) {
      throw const FormatException('Voice call participants must differ.');
    }
    if (voiceCallPairId(caller, callee) != pairId) {
      throw const FormatException('Voice call pairId is not canonical.');
    }
    _validateTimestampOrder(createdAt: createdAt, updatedAt: updatedAt);
    _validateExpiresAt(createdAt: createdAt, expiresAt: expiresAt);
    if (acceptedAt != null && acceptedAt! < createdAt) {
      throw const FormatException('Voice call acceptedAt invalid.');
    }
    if (connectedAt != null && connectedAt! < createdAt) {
      throw const FormatException('Voice call connectedAt invalid.');
    }
    if (endedAt != null && endedAt! < createdAt) {
      throw const FormatException('Voice call endedAt invalid.');
    }
    if (endedBy != null) {
      _validateUsername(endedBy!);
      if (endedBy != caller && endedBy != callee) {
        throw const FormatException('Voice call endedBy is not a participant.');
      }
    }
    if (reasonCode != null) {
      _validateRequiredString(
        'reasonCode',
        reasonCode!,
        max: maxReasonCodeLength,
      );
    }
    if (reason != null) {
      _validateRequiredString('reason', reason!, max: maxReasonLength);
    }
    for (final username in muted.keys) {
      _validateUsername(username);
      if (username != caller && username != callee) {
        throw const FormatException('Muted user is not a call participant.');
      }
    }
    offer?.validate(
      maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
    );
    answer?.validate(
      maxCiphertextLength: VoiceSignalingEnvelope.maxSdpCiphertextLength,
    );
  }
}

final class VoiceCallIceCandidateRecord {
  const VoiceCallIceCandidateRecord({
    required this.callId,
    required this.candidateId,
    required this.role,
    required this.envelope,
    required this.createdAt,
  });

  final String callId;
  final String candidateId;
  final VoiceCallRole role;
  final VoiceSignalingEnvelope envelope;
  final int createdAt;

  Map<String, Object?> toJson() {
    _validateCallId(callId);
    _validateCallId(candidateId);
    if (createdAt <= 0) {
      throw const FormatException('ICE candidate timestamp invalid.');
    }
    return envelope.toJson(
      maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength,
    );
  }

  factory VoiceCallIceCandidateRecord.fromJson({
    required String callId,
    required String candidateId,
    required VoiceCallRole role,
    required Map<Object?, Object?> json,
  }) {
    final envelope = VoiceSignalingEnvelope.fromJson(
      json,
      maxCiphertextLength: VoiceSignalingEnvelope.maxIceCiphertextLength,
    );
    return VoiceCallIceCandidateRecord(
      callId: callId,
      candidateId: candidateId,
      role: role,
      envelope: envelope,
      createdAt: envelope.ts,
    );
  }
}

String normalizeVoiceCallUsername(String value) {
  final normalized = value.trim().toLowerCase();
  _validateUsername(normalized);
  return normalized;
}

String voiceCallPairId(String firstUser, String secondUser) {
  final users = <String>[
    normalizeVoiceCallUsername(firstUser),
    normalizeVoiceCallUsername(secondUser),
  ]..sort();
  if (users[0] == users[1]) {
    throw const FormatException('Voice call pair requires two users.');
  }
  return '${users[0]}:${users[1]}';
}

VoiceCallSignalingStatus voiceCallSignalingStatusFromName(String value) {
  for (final status in VoiceCallSignalingStatus.values) {
    if (status.name == value) {
      return status;
    }
  }
  throw FormatException('Unknown voice call signaling status: $value');
}

VoiceCallRole voiceCallRoleFor({
  required VoiceCallRoom room,
  required String username,
}) {
  final normalized = normalizeVoiceCallUsername(username);
  if (normalized == room.caller) {
    return VoiceCallRole.caller;
  }
  if (normalized == room.callee) {
    return VoiceCallRole.callee;
  }
  throw const FormatException('Username is not a voice call participant.');
}

String voiceCallRoleUsername(VoiceCallRoom room, VoiceCallRole role) {
  return switch (role) {
    VoiceCallRole.caller => room.caller,
    VoiceCallRole.callee => room.callee,
  };
}

final class VoiceSignalingException implements Exception {
  const VoiceSignalingException(this.message);

  final String message;

  @override
  String toString() => message;
}

const int _maxCallIdLength = 128;
const int _maxUsernameLength = 64;

void _validateCallId(String value) {
  _validateRequiredString('callId', value, max: _maxCallIdLength);
}

void _validatePairId(String value) {
  _validateRequiredString('pairId', value, max: (_maxUsernameLength * 2) + 1);
  final parts = value.split(':');
  if (parts.length != 2 ||
      parts[0].isEmpty ||
      parts[1].isEmpty ||
      parts[0].compareTo(parts[1]) >= 0) {
    throw const FormatException('Voice call pairId is invalid.');
  }
  _validateUsername(parts[0]);
  _validateUsername(parts[1]);
}

void _validateUsername(String value) {
  _validateRequiredString('username', value, max: _maxUsernameLength);
  if (value != value.trim().toLowerCase()) {
    throw const FormatException('Voice call username must be normalized.');
  }
}

void _validateTimestampOrder({required int createdAt, required int updatedAt}) {
  if (createdAt <= 0 || updatedAt < createdAt) {
    throw const FormatException('Voice call timestamps are invalid.');
  }
}

void _validateExpiresAt({required int createdAt, required int expiresAt}) {
  if (expiresAt <= createdAt) {
    throw const FormatException(
      'Voice call expiresAt must be after createdAt.',
    );
  }
}

void _validateRequiredString(String key, String value, {required int max}) {
  if (value.trim().isEmpty || value.length > max) {
    throw FormatException('Voice signaling $key length is invalid.');
  }
}

String _requiredString(
  Map<Object?, Object?> json,
  String key, {
  required int max,
}) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Voice signaling $key must be a string.');
  }
  _validateRequiredString(key, value, max: max);
  return value;
}

int _requiredInt(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value.roundToDouble() == value) {
    return value.toInt();
  }
  throw FormatException('Voice signaling $key must be an integer.');
}

int? _optionalInt(Map<Object?, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value.roundToDouble() == value) {
    return value.toInt();
  }
  throw FormatException('Voice signaling $key must be an integer.');
}

String? _optionalString(
  Map<Object?, Object?> json,
  String key, {
  required int max,
}) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Voice signaling $key must be a string.');
  }
  _validateRequiredString(key, value, max: max);
  return value;
}
