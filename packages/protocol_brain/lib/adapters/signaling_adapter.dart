import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../src/iroh_signaling.dart';

abstract class SignalingAdapter {
  Future<void> ensureAuthenticated();
  Future<String> currentUid();
  Future<void> signOut();

  Future<String> register(String username, String password);
  Future<String> login(String username, String password);

  Future<void> writeOffer(String roomId, SDPPayload offer);
  Future<void> writeAnswer(String roomId, SDPPayload answer);
  Future<void> writeICE(
    String roomId,
    IceRole role,
    IceCandidatePayload candidate,
  );
  Future<void> writeIrohAddress(String roomId, IrohAddressPayload payload);

  Stream<SDPPayload> onAnswer(String roomId);
  Stream<IceCandidatePayload> onICE(String roomId, IceRole role);
  Stream<IrohAddressPayload> onIrohAddress(String roomId);
  Stream<SDPPayload> onOffer(String roomId);

  Future<void> setPresence(String username, bool online);
  Future<void> sendHeartbeat(String username);
  Stream<bool> watchPresence(String username);

  Future<bool> isUsernameAvailable(String username);
  Future<void> upsertIdentity(BackendIdentity identity);
  Future<BackendIdentity?> fetchIdentity(String username);

  Future<void> addToUserSearch(String username);
  Future<List<BackendIdentity>> searchUsers(String query);

  Future<void> writeFriendRequest(String to, String from);
  Future<void> deleteFriendRequest(String to, String from);
  Future<List<String>> loadIncomingFriendRequests(String username);
  Future<List<String>> loadOutgoingFriendRequests(String username);
  Future<List<String>> loadAcceptedFriends(String username);
  Future<List<String>> loadBlockedUsers(String username);
  Future<List<String>> loadUsersBlocking(String username);
  Future<void> upsertFriendship(String firstUser, String secondUser);
  Future<void> deleteFriendship(String firstUser, String secondUser);
  Future<void> blockUser(String blocker, String blocked);
  Future<void> unblockUser(String blocker, String blocked);
  Stream<String> onFriendRequest(String username);
  Stream<String> onRelationshipChanged(String username);

  Future<void> deleteRoom(String roomId);
  Future<void> dispose();
}

class SignalingSessionExpiredException implements Exception {
  const SignalingSessionExpiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum IceRole { caller, callee }

class SDPPayload {
  const SDPPayload({
    required this.sdp,
    required this.ts,
    this.restart = false,
    this.icePolicy,
    this.connectAttemptId,
    this.iceStage,
    this.protocolVersion = 1,
    this.createdAt,
  });

  final RTCSessionDescription sdp;
  final int ts;
  final bool restart;
  final String? icePolicy;
  final String? connectAttemptId;
  final String? iceStage;
  final int protocolVersion;
  final int? createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sdp': <String, Object?>{'type': sdp.type, 'sdp': sdp.sdp},
      'ts': ts,
      if (restart) 'restart': true,
      if (icePolicy != null && icePolicy!.isNotEmpty) 'icePolicy': icePolicy,
      if (connectAttemptId != null && connectAttemptId!.isNotEmpty)
        'connectAttemptId': connectAttemptId,
      if (iceStage != null && iceStage!.isNotEmpty) 'iceStage': iceStage,
      'protocolVersion': protocolVersion,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  static SDPPayload fromJson(Map<Object?, Object?> json) {
    final sdpMap =
        (json['sdp'] as Map<Object?, Object?>?) ?? <Object?, Object?>{};
    return SDPPayload(
      sdp: RTCSessionDescription(
        sdpMap['sdp'] as String?,
        sdpMap['type'] as String?,
      ),
      ts: (json['ts'] as num?)?.toInt() ?? 0,
      restart: json['restart'] == true,
      icePolicy: json['icePolicy'] as String?,
      connectAttemptId: json['connectAttemptId'] as String?,
      iceStage: json['iceStage'] as String?,
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      createdAt: (json['createdAt'] as num?)?.toInt(),
    );
  }
}

class IceCandidatePayload {
  const IceCandidatePayload({
    required this.candidate,
    this.connectAttemptId,
    this.iceStage,
    this.protocolVersion = 1,
    this.createdAt,
  });

  final RTCIceCandidate candidate;
  final String? connectAttemptId;
  final String? iceStage;
  final int protocolVersion;
  final int? createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...iceCandidateToJson(candidate),
      if (connectAttemptId != null && connectAttemptId!.isNotEmpty)
        'connectAttemptId': connectAttemptId,
      if (iceStage != null && iceStage!.isNotEmpty) 'iceStage': iceStage,
      'protocolVersion': protocolVersion,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }

  static IceCandidatePayload fromJson(Map<Object?, Object?> json) {
    return IceCandidatePayload(
      candidate: iceCandidateFromJson(json),
      connectAttemptId: json['connectAttemptId'] as String?,
      iceStage: json['iceStage'] as String?,
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      createdAt: (json['createdAt'] as num?)?.toInt(),
    );
  }
}

class BackendIdentity {
  const BackendIdentity({
    required this.username,
    required this.uid,
    required this.displayName,
    required this.gender,
    required this.registeredAt,
    required this.lastSeen,
    required this.lastHeartbeat,
    required this.online,
  });

  final String username;
  final String uid;
  final String displayName;
  final String? gender;
  final int registeredAt;
  final int lastSeen;
  final int lastHeartbeat;
  final bool online;

  Map<String, Object?> toFirebaseJson() {
    return <String, Object?>{
      'username': username,
      'displayName': displayName,
      'gender': gender,
      'registeredAt': registeredAt,
      'lastSeen': lastSeen,
      'lastHeartbeat': lastHeartbeat,
      'online': online,
      'uid': uid,
    };
  }
}

Map<String, Object?> iceCandidateToJson(RTCIceCandidate candidate) {
  return <String, Object?>{
    'candidate': candidate.candidate,
    'sdpMid': candidate.sdpMid,
    'sdpMLineIndex': candidate.sdpMLineIndex,
  };
}

RTCIceCandidate iceCandidateFromJson(Map<Object?, Object?> json) {
  return RTCIceCandidate(
    json['candidate'] as String?,
    json['sdpMid'] as String?,
    (json['sdpMLineIndex'] as num?)?.toInt(),
  );
}
