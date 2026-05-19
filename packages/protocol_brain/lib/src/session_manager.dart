import 'dart:typed_data';

import 'package:peer_core/peer_core.dart' show PeerConnectionRoute;

import 'ice_attempt.dart';

enum SessionState { connecting, connected, reconnecting, failed }

enum ConnectionType { signaling, iroh }

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
  connected,
  reconnecting,
  disconnecting,
  disconnected,
  failed,
}

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
  Stream<Session> get onSessionChanged;

  Future<void> registerPeer(String peerId);
  Future<void> unregisterPeer(String peerId);
  Future<Session> connect(String peerId);
  Future<void> disconnect(String peerId);
  void sendControl(String peerId, String data);
  void send(String peerId, SessionChannel channel, Object data);
  Future<void> openChannel(String peerId, SessionChannel channel);
  Future<int> bufferedAmount(String peerId, SessionChannel channel);
  bool isChannelOpen(String peerId, SessionChannel channel);
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
    this.iceStage,
    this.providerTier,
    this.providerId,
    this.connectAttemptId,
    this.attemptIndex = 0,
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
  final IceAttemptStage? iceStage;
  final IceProviderTier? providerTier;
  final String? providerId;
  final String? connectAttemptId;
  final int attemptIndex;
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
    IceAttemptStage? iceStage,
    IceProviderTier? providerTier,
    String? providerId,
    String? connectAttemptId,
    int? attemptIndex,
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
      iceStage: iceStage ?? this.iceStage,
      providerTier: providerTier ?? this.providerTier,
      providerId: providerId ?? this.providerId,
      connectAttemptId: connectAttemptId ?? this.connectAttemptId,
      attemptIndex: attemptIndex ?? this.attemptIndex,
      sender: sender ?? _sender,
    );
  }
}
