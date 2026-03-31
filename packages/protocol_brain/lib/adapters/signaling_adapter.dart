import 'package:flutter_webrtc/flutter_webrtc.dart';

abstract class SignalingAdapter {
  Future<void> ensureAuthenticated();
  Future<String> currentUid();

  Future<void> writeOffer(String roomId, SDPPayload offer);
  Future<void> writeAnswer(String roomId, SDPPayload answer);
  Future<void> writeICE(String roomId, IceRole role, RTCIceCandidate candidate);

  Stream<SDPPayload> onAnswer(String roomId);
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role);
  Stream<SDPPayload> onOffer(String roomId);

  Future<void> setPresence(String username, bool online);
  Stream<bool> watchPresence(String username);

  Future<bool> isUsernameAvailable(String username);
  Future<void> upsertIdentity(BackendIdentity identity);
  Future<BackendIdentity?> fetchIdentity(String username);

  Future<void> writeFriendRequest(String to, String from);
  Stream<String> onFriendRequest(String username);

  Future<void> deleteRoom(String roomId);
  Future<void> dispose();
}

enum IceRole { caller, callee }

class SDPPayload {
  const SDPPayload({required this.sdp, required this.ts});

  final RTCSessionDescription sdp;
  final int ts;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sdp': <String, Object?>{'type': sdp.type, 'sdp': sdp.sdp},
      'ts': ts,
    };
  }

  static SDPPayload fromJson(Map<Object?, Object?> json) {
    final sdpMap = (json['sdp'] as Map<Object?, Object?>?) ?? <Object?, Object?>{};
    return SDPPayload(
      sdp: RTCSessionDescription(
        sdpMap['sdp'] as String?,
        sdpMap['type'] as String?,
      ),
      ts: (json['ts'] as num?)?.toInt() ?? 0,
    );
  }
}

class BackendIdentity {
  const BackendIdentity({
    required this.username,
    required this.uid,
    required this.displayName,
    required this.registeredAt,
    required this.lastSeen,
    required this.lastHeartbeat,
    required this.online,
  });

  final String username;
  final String uid;
  final String displayName;
  final int registeredAt;
  final int lastSeen;
  final int lastHeartbeat;
  final bool online;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'username': username,
      'displayName': displayName,
      'registeredAt': registeredAt,
      'registered_at': registeredAt,
      'lastSeen': lastSeen,
      'last_seen': lastSeen,
      'lastHeartbeat': lastHeartbeat,
      'last_heartbeat': lastHeartbeat,
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
