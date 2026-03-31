import 'package:peer_core/peer_core.dart';

enum SessionState { connecting, connected, reconnecting, failed }

enum ConnectionType { signaling }

abstract class SessionManager {
  List<Session> getSessions();
  Session? getSession(String peerId);

  Stream<Session> get onPeerConnected;
  Stream<String> get onPeerDisconnected;
  Stream<PeerMessage> get onPeerMessage;
}

abstract class ProtocolBrain implements SessionManager {
  Future<void> registerPeer(String peerId);
  Future<void> unregisterPeer(String peerId);
  Future<Session> connect(String peerId);
  Future<void> disconnect(String peerId);
  void sendControl(String peerId, String data);
}

class Session {
  Session({
    required this.peerId,
    required this.state,
    required this.connectionType,
    required void Function(String data) sender,
    this.connectedAt,
  }) : _sender = sender;

  final String peerId;
  final SessionState state;
  final int? connectedAt;
  final ConnectionType connectionType;
  final void Function(String data) _sender;

  void send(String data) => _sender(data);

  Session copyWith({
    SessionState? state,
    int? connectedAt,
    ConnectionType? connectionType,
    void Function(String data)? sender,
  }) {
    return Session(
      peerId: peerId,
      state: state ?? this.state,
      connectedAt: connectedAt ?? this.connectedAt,
      connectionType: connectionType ?? this.connectionType,
      sender: sender ?? _sender,
    );
  }
}

