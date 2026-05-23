import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peer_core/peer_core.dart'
    show
        CallMediaConnection,
        PeerConnectionRoute,
        PeerRemoteTrack,
        VoiceMediaConnection;

enum SessionState { connecting, connected, reconnecting, failed }

enum ConnectionType { signaling }

enum SessionChannel { chat, control, file }

enum SessionPhase {
  idle,
  checkingPresence,
  registeringPeer,
  waitingForOffer,
  creatingOffer,
  writingOffer,
  waitingForAnswer,
  writingAnswer,
  exchangingIce,
  openingDataChannels,
  negotiatingMedia,
  connected,
  reconnecting,
  disconnecting,
  disconnected,
  failed,
}

class SessionRemoteTrack {
  const SessionRemoteTrack({
    required this.peerId,
    required this.track,
    required this.streams,
    required this.receivedAt,
  });

  final String peerId;
  final MediaStreamTrack track;
  final List<MediaStream> streams;
  final DateTime receivedAt;

  factory SessionRemoteTrack.fromPeerTrack(
    String peerId,
    PeerRemoteTrack event,
  ) {
    return SessionRemoteTrack(
      peerId: peerId,
      track: event.track,
      streams: event.streams,
      receivedAt: event.receivedAt,
    );
  }
}

class IncomingOfferDecision {
  const IncomingOfferDecision.allow() : allowed = true, reason = null;

  const IncomingOfferDecision.deny(this.reason) : allowed = false;

  final bool allowed;
  final String? reason;
}

class IncomingOfferRejection {
  const IncomingOfferRejection({
    required this.peerId,
    required this.reason,
    required this.rejectedAt,
    required this.offerTimestamp,
  });

  final String peerId;
  final String reason;
  final DateTime rejectedAt;
  final int offerTimestamp;
}

typedef IncomingOfferGuard =
    FutureOr<IncomingOfferDecision> Function(String peerId);

class SessionMessage {
  const SessionMessage({
    required this.channel,
    required this.data,
    required this.receivedAt,
    this.peerId,
  });

  final SessionChannel channel;
  final Object? data;
  final DateTime receivedAt;
  final String? peerId;

  String? get text => data is String ? data! as String : null;
  Uint8List? get binary => data is Uint8List ? data! as Uint8List : null;
}

abstract class SessionManager {
  List<Session> getSessions();
  Session? getSession(String peerId);

  Stream<Session> get onPeerConnected;
  Stream<String> get onPeerDisconnected;
  Stream<SessionMessage> get onPeerMessage;
  Stream<SessionRemoteTrack> get onRemoteTrack;
  Stream<Session> get onSessionChanged;
  Stream<IncomingOfferRejection> get onIncomingOfferRejected;

  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  });
  Future<void> unregisterPeer(String peerId);
  Future<Session> connect(String peerId);
  Future<void> disconnect(String peerId);
  Future<void> recoverConnection(
    String peerId, {
    String reason = 'Network changed. Restarting peer connection.',
  });
  Future<void> recoverConnections({
    String reason = 'Network changed. Restarting peer connections.',
  });
  void sendControl(String peerId, String data);
  void send(String peerId, SessionChannel channel, Object data);
  Future<void> openChannel(String peerId, SessionChannel channel);
  Future<int> bufferedAmount(String peerId, SessionChannel channel);
  bool isChannelOpen(String peerId, SessionChannel channel);
  Future<void> startLocalAudio(String peerId);
  Future<void> stopLocalAudio(String peerId);
  Future<void> setMicrophoneMuted(String peerId, {required bool muted});
  Future<VoiceMediaConnection> createVoiceMediaConnection(String peerId);
  Future<CallMediaConnection> createCallMediaConnection(String peerId);
  Future<RTCSessionDescription> createMediaOffer(String peerId);
  Future<RTCSessionDescription> applyMediaOffer(
    String peerId,
    RTCSessionDescription offer,
  );
  Future<void> applyMediaAnswer(String peerId, RTCSessionDescription answer);
}

abstract class ProtocolBrain implements SessionManager {}

class Session {
  Session({
    required this.peerId,
    required this.state,
    required this.connectionType,
    required void Function(String data) sender,
    this.connectedAt,
    this.phase = SessionPhase.idle,
    this.detail = 'Idle',
    this.updatedAt,
    this.error,
    this.retryAttempt = 0,
    this.roomId,
    this.isOfferOwner,
    this.route = const PeerConnectionRoute.unknown(),
  }) : _sender = sender;

  final String peerId;
  final SessionState state;
  final int? connectedAt;
  final ConnectionType connectionType;
  final SessionPhase phase;
  final String detail;
  final int? updatedAt;
  final String? error;
  final int retryAttempt;
  final String? roomId;
  final bool? isOfferOwner;
  final PeerConnectionRoute route;
  final void Function(String data) _sender;

  void send(String data) => _sender(data);

  Session copyWith({
    SessionState? state,
    int? connectedAt,
    ConnectionType? connectionType,
    SessionPhase? phase,
    String? detail,
    int? updatedAt,
    String? error,
    bool clearError = false,
    int? retryAttempt,
    String? roomId,
    bool? isOfferOwner,
    PeerConnectionRoute? route,
    void Function(String data)? sender,
  }) {
    return Session(
      peerId: peerId,
      state: state ?? this.state,
      connectedAt: connectedAt ?? this.connectedAt,
      connectionType: connectionType ?? this.connectionType,
      phase: phase ?? this.phase,
      detail: detail ?? this.detail,
      updatedAt: updatedAt ?? this.updatedAt,
      error: clearError ? null : error ?? this.error,
      retryAttempt: retryAttempt ?? this.retryAttempt,
      roomId: roomId ?? this.roomId,
      isOfferOwner: isOfferOwner ?? this.isOfferOwner,
      route: route ?? this.route,
      sender: sender ?? _sender,
    );
  }
}
