class IrohAddressPayload {
  const IrohAddressPayload({
    required this.protocolVersion,
    required this.connectAttemptId,
    required this.username,
    required this.nodeId,
    required this.endpointAddr,
    required this.sessionSecret,
    required this.createdAt,
    required this.expiresAt,
  });

  final int protocolVersion;
  final String connectAttemptId;
  final String username;
  final String nodeId;
  final String endpointAddr;
  final String sessionSecret;
  final int createdAt;
  final int expiresAt;

  bool isUsableAt(int nowMs) => protocolVersion == 1 && nowMs <= expiresAt;

  bool matches({required String username, required String connectAttemptId}) {
    return this.username.trim().toLowerCase() ==
            username.trim().toLowerCase() &&
        this.connectAttemptId == connectAttemptId;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'connectAttemptId': connectAttemptId,
      'username': username,
      'nodeId': nodeId,
      'endpointAddr': endpointAddr,
      'sessionSecret': sessionSecret,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
    };
  }

  static IrohAddressPayload fromJson(Map<Object?, Object?> json) {
    return IrohAddressPayload(
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      connectAttemptId: json['connectAttemptId']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      nodeId: json['nodeId']?.toString() ?? '',
      endpointAddr: json['endpointAddr']?.toString() ?? '',
      sessionSecret: json['sessionSecret']?.toString() ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IrohAddressPayload &&
        other.protocolVersion == protocolVersion &&
        other.connectAttemptId == connectAttemptId &&
        other.username == username &&
        other.nodeId == nodeId &&
        other.endpointAddr == endpointAddr &&
        other.sessionSecret == sessionSecret &&
        other.createdAt == createdAt &&
        other.expiresAt == expiresAt;
  }

  @override
  int get hashCode => Object.hash(
    protocolVersion,
    connectAttemptId,
    username,
    nodeId,
    endpointAddr,
    sessionSecret,
    createdAt,
    expiresAt,
  );
}
