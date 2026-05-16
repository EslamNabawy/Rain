import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:protocol_brain/protocol_brain.dart';

part 'app_state.freezed.dart';

@freezed
abstract class PeerConnectionView with _$PeerConnectionView {
  const PeerConnectionView._();

  const factory PeerConnectionView({
    required String peerId,
    Session? session,
    String? localDetail,
    Object? error,
    @Default(false) bool actionBusy,
    @Default(false) bool disconnecting,
    int? updatedAt,
  }) = _PeerConnectionView;

  bool get isConnected => session?.state == SessionState.connected;

  bool get isBusy =>
      actionBusy ||
      disconnecting ||
      session?.state == SessionState.connecting ||
      session?.state == SessionState.reconnecting;
}

@freezed
abstract class ConnectionsState with _$ConnectionsState {
  const ConnectionsState._();

  const factory ConnectionsState({
    @Default(<String, PeerConnectionView>{})
    Map<String, PeerConnectionView> peers,
  }) = _ConnectionsState;

  PeerConnectionView peer(String peerId) {
    return peers[peerId] ?? PeerConnectionView(peerId: peerId);
  }
}

@freezed
abstract class UserSearchState with _$UserSearchState {
  const factory UserSearchState({
    @Default('') String query,
    @Default(<BackendIdentity>[]) List<BackendIdentity> results,
    String? sendingTo,
  }) = _UserSearchState;
}
