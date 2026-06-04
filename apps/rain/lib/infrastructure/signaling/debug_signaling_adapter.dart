import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/infrastructure/services/rain_debug_log_service.dart';

SignalingAdapter wrapSignalingAdapterWithDebugLogging(
  SignalingAdapter adapter,
  RainDebugLogService log,
) {
  if (!log.enabled) {
    return adapter;
  }
  if (adapter is VoiceSignalingAdapter && adapter is ConnectionRequestAdapter) {
    return DebugFullSignalingAdapter(adapter, log);
  }
  return DebugSignalingAdapter(adapter, log);
}

class DebugSignalingAdapter implements SignalingAdapter {
  DebugSignalingAdapter(this._inner, this._log);

  final SignalingAdapter _inner;
  final RainDebugLogService _log;

  @override
  Future<void> ensureAuthenticated() {
    return _traceFuture<void>(
      operation: 'ensureAuthenticated',
      kind: 'auth',
      action: _inner.ensureAuthenticated,
    );
  }

  @override
  Future<void> ensureSignedInAs(String username) {
    return _traceFuture<void>(
      operation: 'ensureSignedInAs',
      kind: 'auth',
      context: <String, Object?>{'username': username},
      action: () => _inner.ensureSignedInAs(username),
    );
  }

  @override
  Future<String> currentUid() {
    return _traceFuture<String>(
      operation: 'currentUid',
      kind: 'auth',
      action: _inner.currentUid,
      resultContext: (String uid) => <String, Object?>{
        'hasUid': uid.isNotEmpty,
      },
    );
  }

  @override
  Future<void> signOut() {
    return _traceFuture<void>(
      operation: 'signOut',
      kind: 'auth',
      action: _inner.signOut,
    );
  }

  @override
  Future<void> reauthenticate(String username, String password) {
    return _traceFuture<void>(
      operation: 'reauthenticate',
      kind: 'auth',
      context: <String, Object?>{
        'username': username,
        'passwordProvided': password.isNotEmpty,
      },
      action: () => _inner.reauthenticate(username, password),
    );
  }

  @override
  Future<void> deleteAccount(String username) {
    return _traceFuture<void>(
      operation: 'deleteAccount',
      kind: 'auth',
      context: <String, Object?>{'username': username},
      action: () => _inner.deleteAccount(username),
    );
  }

  @override
  Future<String> register(String username, String password) {
    return _traceFuture<String>(
      operation: 'register',
      kind: 'auth',
      context: <String, Object?>{
        'username': username,
        'passwordProvided': password.isNotEmpty,
      },
      action: () => _inner.register(username, password),
      resultContext: (String uid) => <String, Object?>{
        'hasUid': uid.isNotEmpty,
      },
    );
  }

  @override
  Future<String> login(String username, String password) {
    return _traceFuture<String>(
      operation: 'login',
      kind: 'auth',
      context: <String, Object?>{
        'username': username,
        'passwordProvided': password.isNotEmpty,
      },
      action: () => _inner.login(username, password),
      resultContext: (String uid) => <String, Object?>{
        'hasUid': uid.isNotEmpty,
      },
    );
  }

  @override
  Future<void> writeOffer(String roomId, SDPPayload offer) {
    return _traceFuture<void>(
      operation: 'writeOffer',
      kind: 'write',
      context: <String, Object?>{'roomId': roomId, ..._sdpSummary(offer)},
      action: () => _inner.writeOffer(roomId, offer),
    );
  }

  @override
  Future<void> writeAnswer(String roomId, SDPPayload answer) {
    return _traceFuture<void>(
      operation: 'writeAnswer',
      kind: 'write',
      context: <String, Object?>{'roomId': roomId, ..._sdpSummary(answer)},
      action: () => _inner.writeAnswer(roomId, answer),
    );
  }

  @override
  Future<void> writeICE(
    String roomId,
    IceRole role,
    RTCIceCandidate candidate,
  ) {
    return _traceFuture<void>(
      operation: 'writeICE',
      kind: 'write',
      context: <String, Object?>{
        'roomId': roomId,
        'role': role.name,
        ..._iceCandidateSummary(candidate),
      },
      action: () => _inner.writeICE(roomId, role, candidate),
    );
  }

  @override
  Stream<SDPPayload> onAnswer(String roomId) {
    return _traceStream<SDPPayload>(
      operation: 'onAnswer',
      kind: 'watch',
      context: <String, Object?>{'roomId': roomId},
      subscribe: () => _inner.onAnswer(roomId),
      eventContext: _sdpSummary,
    );
  }

  @override
  Stream<RTCIceCandidate> onICE(String roomId, IceRole role) {
    return _traceStream<RTCIceCandidate>(
      operation: 'onICE',
      kind: 'watch',
      context: <String, Object?>{'roomId': roomId, 'role': role.name},
      subscribe: () => _inner.onICE(roomId, role),
      eventContext: _iceCandidateSummary,
    );
  }

  @override
  Stream<SDPPayload> onOffer(String roomId) {
    return _traceStream<SDPPayload>(
      operation: 'onOffer',
      kind: 'watch',
      context: <String, Object?>{'roomId': roomId},
      subscribe: () => _inner.onOffer(roomId),
      eventContext: _sdpSummary,
    );
  }

  @override
  Future<void> setPresence(String username, bool online) {
    return _traceFuture<void>(
      operation: 'setPresence',
      kind: 'presence_write',
      context: <String, Object?>{'username': username, 'online': online},
      action: () => _inner.setPresence(username, online),
    );
  }

  @override
  Future<void> sendHeartbeat(String username) {
    return _traceFuture<void>(
      operation: 'sendHeartbeat',
      kind: 'presence_write',
      context: <String, Object?>{'username': username},
      action: () => _inner.sendHeartbeat(username),
    );
  }

  @override
  Stream<bool> watchPresence(String username) {
    return _traceStream<bool>(
      operation: 'watchPresence',
      kind: 'presence_watch',
      context: <String, Object?>{'username': username},
      subscribe: () => _inner.watchPresence(username),
      eventContext: (bool online) => <String, Object?>{'online': online},
    );
  }

  @override
  Future<bool> isUsernameAvailable(String username) {
    return _traceFuture<bool>(
      operation: 'isUsernameAvailable',
      kind: 'read',
      context: <String, Object?>{'username': username},
      action: () => _inner.isUsernameAvailable(username),
      resultContext: (bool available) => <String, Object?>{
        'available': available,
      },
    );
  }

  @override
  Future<void> upsertIdentity(BackendIdentity identity) {
    return _traceFuture<void>(
      operation: 'upsertIdentity',
      kind: 'write',
      context: _identitySummary(identity),
      action: () => _inner.upsertIdentity(identity),
    );
  }

  @override
  Future<BackendIdentity?> fetchIdentity(String username) {
    return _traceFuture<BackendIdentity?>(
      operation: 'fetchIdentity',
      kind: 'read',
      context: <String, Object?>{'username': username},
      action: () => _inner.fetchIdentity(username),
      resultContext: (BackendIdentity? identity) => <String, Object?>{
        'found': identity != null,
        if (identity != null) 'online': identity.online,
        if (identity != null) 'lastHeartbeat': identity.lastHeartbeat,
      },
    );
  }

  @override
  Future<void> addToUserSearch(String username) {
    return _traceFuture<void>(
      operation: 'addToUserSearch',
      kind: 'write',
      context: <String, Object?>{'username': username},
      action: () => _inner.addToUserSearch(username),
    );
  }

  @override
  Future<List<BackendIdentity>> searchUsers(String query) {
    return _traceFuture<List<BackendIdentity>>(
      operation: 'searchUsers',
      kind: 'read',
      context: <String, Object?>{'queryLength': query.trim().length},
      action: () => _inner.searchUsers(query),
      resultContext: (List<BackendIdentity> identities) => <String, Object?>{
        'resultCount': identities.length,
      },
    );
  }

  @override
  Future<void> writeFriendRequest(String to, String from) {
    return _traceFuture<void>(
      operation: 'writeFriendRequest',
      kind: 'write',
      context: <String, Object?>{'to': to, 'from': from},
      action: () => _inner.writeFriendRequest(to, from),
    );
  }

  @override
  Future<void> deleteFriendRequest(String to, String from) {
    return _traceFuture<void>(
      operation: 'deleteFriendRequest',
      kind: 'write',
      context: <String, Object?>{'to': to, 'from': from},
      action: () => _inner.deleteFriendRequest(to, from),
    );
  }

  @override
  Future<List<String>> loadIncomingFriendRequests(String username) {
    return _traceFuture<List<String>>(
      operation: 'loadIncomingFriendRequests',
      kind: 'read',
      context: <String, Object?>{'username': username},
      action: () => _inner.loadIncomingFriendRequests(username),
      resultContext: _listCount,
    );
  }

  @override
  Future<List<String>> loadOutgoingFriendRequests(String username) {
    return _traceFuture<List<String>>(
      operation: 'loadOutgoingFriendRequests',
      kind: 'read',
      context: <String, Object?>{'username': username},
      action: () => _inner.loadOutgoingFriendRequests(username),
      resultContext: _listCount,
    );
  }

  @override
  Future<List<String>> loadAcceptedFriends(String username) {
    return _traceFuture<List<String>>(
      operation: 'loadAcceptedFriends',
      kind: 'read',
      context: <String, Object?>{'username': username},
      action: () => _inner.loadAcceptedFriends(username),
      resultContext: _listCount,
    );
  }

  @override
  Future<List<String>> loadBlockedUsers(String username) {
    return _traceFuture<List<String>>(
      operation: 'loadBlockedUsers',
      kind: 'read',
      context: <String, Object?>{'username': username},
      action: () => _inner.loadBlockedUsers(username),
      resultContext: _listCount,
    );
  }

  @override
  Future<List<String>> loadUsersBlocking(String username) {
    return _traceFuture<List<String>>(
      operation: 'loadUsersBlocking',
      kind: 'read',
      context: <String, Object?>{'username': username},
      action: () => _inner.loadUsersBlocking(username),
      resultContext: _listCount,
    );
  }

  @override
  Future<void> upsertFriendship(String firstUser, String secondUser) {
    return _traceFuture<void>(
      operation: 'upsertFriendship',
      kind: 'write',
      context: <String, Object?>{
        'firstUser': firstUser,
        'secondUser': secondUser,
      },
      action: () => _inner.upsertFriendship(firstUser, secondUser),
    );
  }

  @override
  Future<void> deleteFriendship(String firstUser, String secondUser) {
    return _traceFuture<void>(
      operation: 'deleteFriendship',
      kind: 'write',
      context: <String, Object?>{
        'firstUser': firstUser,
        'secondUser': secondUser,
      },
      action: () => _inner.deleteFriendship(firstUser, secondUser),
    );
  }

  @override
  Future<void> blockUser(String blocker, String blocked) {
    return _traceFuture<void>(
      operation: 'blockUser',
      kind: 'write',
      context: <String, Object?>{'blocker': blocker, 'blocked': blocked},
      action: () => _inner.blockUser(blocker, blocked),
    );
  }

  @override
  Future<void> unblockUser(String blocker, String blocked) {
    return _traceFuture<void>(
      operation: 'unblockUser',
      kind: 'write',
      context: <String, Object?>{'blocker': blocker, 'blocked': blocked},
      action: () => _inner.unblockUser(blocker, blocked),
    );
  }

  @override
  Stream<String> onFriendRequest(String username) {
    return _traceStream<String>(
      operation: 'onFriendRequest',
      kind: 'watch',
      context: <String, Object?>{'username': username},
      subscribe: () => _inner.onFriendRequest(username),
      eventContext: (String from) => <String, Object?>{'from': from},
    );
  }

  @override
  Stream<String> onRelationshipChanged(String username) {
    return _traceStream<String>(
      operation: 'onRelationshipChanged',
      kind: 'watch',
      context: <String, Object?>{'username': username},
      subscribe: () => _inner.onRelationshipChanged(username),
      eventContext: (String peer) => <String, Object?>{'peerId': peer},
    );
  }

  @override
  Future<void> deleteRoom(String roomId) {
    return _traceFuture<void>(
      operation: 'deleteRoom',
      kind: 'write',
      context: <String, Object?>{'roomId': roomId},
      action: () => _inner.deleteRoom(roomId),
    );
  }

  @override
  Future<void> dispose() {
    return _traceFuture<void>(
      operation: 'dispose',
      kind: 'lifecycle',
      action: _inner.dispose,
    );
  }

  Future<T> _traceFuture<T>({
    required String operation,
    required String kind,
    Map<String, Object?> context = const <String, Object?>{},
    required Future<T> Function() action,
    Map<String, Object?> Function(T result)? resultContext,
  }) async {
    final stopwatch = Stopwatch()..start();
    _event(
      name: 'operation_started',
      severity: RainDebugSeverity.debug,
      context: <String, Object?>{
        'operation': operation,
        'kind': kind,
        ...context,
      },
    );
    try {
      final result = await action();
      stopwatch.stop();
      _event(
        name: 'operation_completed',
        severity: RainDebugSeverity.debug,
        context: <String, Object?>{
          'operation': operation,
          'kind': kind,
          'durationMs': stopwatch.elapsedMilliseconds,
          ...context,
          if (resultContext != null) ...resultContext(result),
        },
      );
      return result;
    } catch (error, stackTrace) {
      stopwatch.stop();
      _log.error(
        error,
        stackTrace,
        source: 'signaling.$operation',
        fatal: false,
        context: <String, Object?>{
          'operation': operation,
          'kind': kind,
          'durationMs': stopwatch.elapsedMilliseconds,
          ...context,
        },
      );
      _event(
        name: 'operation_failed',
        severity: RainDebugSeverity.error,
        message: error.toString(),
        context: <String, Object?>{
          'operation': operation,
          'kind': kind,
          'durationMs': stopwatch.elapsedMilliseconds,
          ...context,
          'errorType': error.runtimeType.toString(),
        },
      );
      rethrow;
    }
  }

  Stream<T> _traceStream<T>({
    required String operation,
    required String kind,
    Map<String, Object?> context = const <String, Object?>{},
    required Stream<T> Function() subscribe,
    Map<String, Object?> Function(T value)? eventContext,
  }) async* {
    final stopwatch = Stopwatch()..start();
    var eventCount = 0;
    var completed = false;
    var failed = false;
    _event(
      name: 'stream_subscribed',
      severity: RainDebugSeverity.debug,
      context: <String, Object?>{
        'operation': operation,
        'kind': kind,
        ...context,
      },
    );
    try {
      await for (final value in subscribe()) {
        eventCount += 1;
        _event(
          name: 'stream_event',
          severity: RainDebugSeverity.debug,
          context: <String, Object?>{
            'operation': operation,
            'kind': kind,
            'eventCount': eventCount,
            ...context,
            if (eventContext != null) ...eventContext(value),
          },
        );
        yield value;
      }
      completed = true;
      stopwatch.stop();
      _event(
        name: 'stream_completed',
        severity: RainDebugSeverity.debug,
        context: <String, Object?>{
          'operation': operation,
          'kind': kind,
          'eventCount': eventCount,
          'durationMs': stopwatch.elapsedMilliseconds,
          ...context,
        },
      );
    } catch (error, stackTrace) {
      failed = true;
      stopwatch.stop();
      _log.error(
        error,
        stackTrace,
        source: 'signaling.$operation.watch',
        fatal: false,
        context: <String, Object?>{
          'operation': operation,
          'kind': kind,
          'eventCount': eventCount,
          'durationMs': stopwatch.elapsedMilliseconds,
          ...context,
        },
      );
      _event(
        name: 'stream_failed',
        severity: RainDebugSeverity.error,
        message: error.toString(),
        context: <String, Object?>{
          'operation': operation,
          'kind': kind,
          'eventCount': eventCount,
          'durationMs': stopwatch.elapsedMilliseconds,
          ...context,
          'errorType': error.runtimeType.toString(),
        },
      );
      rethrow;
    } finally {
      if (!completed && !failed) {
        stopwatch.stop();
        _event(
          name: 'stream_cancelled',
          severity: RainDebugSeverity.debug,
          context: <String, Object?>{
            'operation': operation,
            'kind': kind,
            'eventCount': eventCount,
            'durationMs': stopwatch.elapsedMilliseconds,
            ...context,
          },
        );
      }
    }
  }

  void _event({
    required String name,
    required RainDebugSeverity severity,
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    _log.event(
      category: 'network',
      name: name,
      severity: severity,
      message: message,
      context: context,
    );
  }
}

class DebugFullSignalingAdapter extends DebugSignalingAdapter
    implements VoiceSignalingAdapter, ConnectionRequestAdapter {
  DebugFullSignalingAdapter(super.adapter, super.log)
    : _voice = adapter as VoiceSignalingAdapter,
      _requests = adapter as ConnectionRequestAdapter;

  final VoiceSignalingAdapter _voice;
  final ConnectionRequestAdapter _requests;

  @override
  Future<VoiceCallRoom> createOutgoingCall({
    required String callId,
    required String caller,
    required String callee,
    required int createdAt,
    required int expiresAt,
    CallMediaMode mediaMode = CallMediaMode.audio,
  }) {
    return _traceFuture<VoiceCallRoom>(
      operation: 'createOutgoingCall',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'caller': caller,
        'callee': callee,
        'mediaMode': mediaMode.name,
        'createdAt': createdAt,
        'expiresAt': expiresAt,
      },
      action: () => _voice.createOutgoingCall(
        callId: callId,
        caller: caller,
        callee: callee,
        createdAt: createdAt,
        expiresAt: expiresAt,
        mediaMode: mediaMode,
      ),
      resultContext: _voiceRoomSummary,
    );
  }

  @override
  Future<VoiceCallRoom?> fetchCall(String callId) {
    return _traceFuture<VoiceCallRoom?>(
      operation: 'fetchCall',
      kind: 'voice_read',
      context: <String, Object?>{'callId': callId},
      action: () => _voice.fetchCall(callId),
      resultContext: (VoiceCallRoom? room) => <String, Object?>{
        'found': room != null,
        if (room != null) ..._voiceRoomSummary(room),
      },
    );
  }

  @override
  Stream<VoiceCallRoom?> watchCall(String callId) {
    return _traceStream<VoiceCallRoom?>(
      operation: 'watchCall',
      kind: 'voice_watch',
      context: <String, Object?>{'callId': callId},
      subscribe: () => _voice.watchCall(callId),
      eventContext: (VoiceCallRoom? room) => <String, Object?>{
        'found': room != null,
        if (room != null) ..._voiceRoomSummary(room),
      },
    );
  }

  @override
  Stream<VoiceCallInboxEntry> watchIncomingCalls(String username) {
    return _traceStream<VoiceCallInboxEntry>(
      operation: 'watchIncomingCalls',
      kind: 'voice_watch',
      context: <String, Object?>{'username': username},
      subscribe: () => _voice.watchIncomingCalls(username),
      eventContext: _voiceInboxSummary,
    );
  }

  @override
  Future<void> acceptCall({
    required String callId,
    required String callee,
    required int acceptedAt,
  }) {
    return _traceFuture<void>(
      operation: 'acceptCall',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'callee': callee,
        'acceptedAt': acceptedAt,
      },
      action: () => _voice.acceptCall(
        callId: callId,
        callee: callee,
        acceptedAt: acceptedAt,
      ),
    );
  }

  @override
  Future<void> markConnected({
    required String callId,
    required String username,
    required int connectedAt,
  }) {
    return _traceFuture<void>(
      operation: 'markConnected',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'username': username,
        'connectedAt': connectedAt,
      },
      action: () => _voice.markConnected(
        callId: callId,
        username: username,
        connectedAt: connectedAt,
      ),
    );
  }

  @override
  Future<void> endCall({
    required String callId,
    required String username,
    required VoiceCallSignalingStatus status,
    required int endedAt,
    String? reasonCode,
    String? reason,
  }) {
    return _traceFuture<void>(
      operation: 'endCall',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'username': username,
        'status': status.name,
        'endedAt': endedAt,
        'reasonCode': ?reasonCode,
        'reasonLength': ?reason?.length,
      },
      action: () => _voice.endCall(
        callId: callId,
        username: username,
        status: status,
        endedAt: endedAt,
        reasonCode: reasonCode,
        reason: reason,
      ),
    );
  }

  @override
  Future<void> setMuted({
    required String callId,
    required String username,
    required bool muted,
    required int updatedAt,
  }) {
    return _traceFuture<void>(
      operation: 'setMuted',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'username': username,
        'muted': muted,
        'updatedAt': updatedAt,
      },
      action: () => _voice.setMuted(
        callId: callId,
        username: username,
        muted: muted,
        updatedAt: updatedAt,
      ),
    );
  }

  @override
  Future<void> setCameraMuted({
    required String callId,
    required String username,
    required bool cameraMuted,
    required int updatedAt,
  }) {
    return _traceFuture<void>(
      operation: 'setCameraMuted',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'username': username,
        'cameraMuted': cameraMuted,
        'updatedAt': updatedAt,
      },
      action: () => _voice.setCameraMuted(
        callId: callId,
        username: username,
        cameraMuted: cameraMuted,
        updatedAt: updatedAt,
      ),
    );
  }

  @override
  Future<void> writeVoiceOffer({
    required String callId,
    required String caller,
    required VoiceSignalingEnvelope offer,
    required int updatedAt,
  }) {
    return _traceFuture<void>(
      operation: 'writeVoiceOffer',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'caller': caller,
        'updatedAt': updatedAt,
        ..._voiceEnvelopeSummary(offer),
      },
      action: () => _voice.writeVoiceOffer(
        callId: callId,
        caller: caller,
        offer: offer,
        updatedAt: updatedAt,
      ),
    );
  }

  @override
  Future<void> writeVoiceAnswer({
    required String callId,
    required String callee,
    required VoiceSignalingEnvelope answer,
    required int updatedAt,
  }) {
    return _traceFuture<void>(
      operation: 'writeVoiceAnswer',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'callee': callee,
        'updatedAt': updatedAt,
        ..._voiceEnvelopeSummary(answer),
      },
      action: () => _voice.writeVoiceAnswer(
        callId: callId,
        callee: callee,
        answer: answer,
        updatedAt: updatedAt,
      ),
    );
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceOffer(String callId) {
    return _traceStream<VoiceSignalingEnvelope>(
      operation: 'watchVoiceOffer',
      kind: 'voice_watch',
      context: <String, Object?>{'callId': callId},
      subscribe: () => _voice.watchVoiceOffer(callId),
      eventContext: _voiceEnvelopeSummary,
    );
  }

  @override
  Stream<VoiceSignalingEnvelope> watchVoiceAnswer(String callId) {
    return _traceStream<VoiceSignalingEnvelope>(
      operation: 'watchVoiceAnswer',
      kind: 'voice_watch',
      context: <String, Object?>{'callId': callId},
      subscribe: () => _voice.watchVoiceAnswer(callId),
      eventContext: _voiceEnvelopeSummary,
    );
  }

  @override
  Future<String> writeIceCandidate({
    required String callId,
    required String username,
    required VoiceCallRole role,
    required VoiceSignalingEnvelope candidate,
    required int createdAt,
  }) {
    return _traceFuture<String>(
      operation: 'writeIceCandidate',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'username': username,
        'role': role.name,
        'createdAt': createdAt,
        ..._voiceEnvelopeSummary(candidate),
      },
      action: () => _voice.writeIceCandidate(
        callId: callId,
        username: username,
        role: role,
        candidate: candidate,
        createdAt: createdAt,
      ),
      resultContext: (String id) => <String, Object?>{
        'candidateRecordIdLength': id.length,
      },
    );
  }

  @override
  Future<List<String>> writeIceCandidates({
    required String callId,
    required String username,
    required VoiceCallRole role,
    required List<VoiceSignalingEnvelope> candidates,
    required int createdAt,
  }) {
    return _traceFuture<List<String>>(
      operation: 'writeIceCandidates',
      kind: 'voice_write',
      context: <String, Object?>{
        'callId': callId,
        'username': username,
        'role': role.name,
        'createdAt': createdAt,
        'candidateCount': candidates.length,
        'payloadBytes': candidates.fold<int>(
          0,
          (int sum, VoiceSignalingEnvelope envelope) =>
              sum + envelope.ciphertext.length,
        ),
      },
      action: () => _voice.writeIceCandidates(
        callId: callId,
        username: username,
        role: role,
        candidates: candidates,
        createdAt: createdAt,
      ),
      resultContext: _listCount,
    );
  }

  @override
  Stream<VoiceCallIceCandidateRecord> watchIceCandidates({
    required String callId,
    required VoiceCallRole role,
  }) {
    return _traceStream<VoiceCallIceCandidateRecord>(
      operation: 'watchIceCandidates',
      kind: 'voice_watch',
      context: <String, Object?>{'callId': callId, 'role': role.name},
      subscribe: () => _voice.watchIceCandidates(callId: callId, role: role),
      eventContext: _voiceIceRecordSummary,
    );
  }

  @override
  Future<VoiceCallCleanupSummary> cleanupStaleVoiceCallArtifacts({
    required String username,
    required int now,
    int limit = maxCallCleanupItemsPerRun,
  }) {
    return _traceFuture<VoiceCallCleanupSummary>(
      operation: 'cleanupStaleVoiceCallArtifacts',
      kind: 'voice_cleanup',
      context: <String, Object?>{
        'username': username,
        'now': now,
        'limit': limit,
      },
      action: () => _voice.cleanupStaleVoiceCallArtifacts(
        username: username,
        now: now,
        limit: limit,
      ),
      resultContext: (VoiceCallCleanupSummary summary) => summary.toJson(),
    );
  }

  @override
  Future<void> deleteCall(String callId) {
    return _traceFuture<void>(
      operation: 'deleteCall',
      kind: 'voice_write',
      context: <String, Object?>{'callId': callId},
      action: () => _voice.deleteCall(callId),
    );
  }

  @override
  Future<ConnectionRequestDecision> createConnectionRequest(String peerId) {
    return _traceFuture<ConnectionRequestDecision>(
      operation: 'createConnectionRequest',
      kind: 'request_write',
      context: <String, Object?>{'peerId': peerId},
      action: () => _requests.createConnectionRequest(peerId),
      resultContext: _requestDecisionSummary,
    );
  }

  @override
  Future<ConnectionRequestDecision> cancelConnectionRequest(String requestId) {
    return _traceFuture<ConnectionRequestDecision>(
      operation: 'cancelConnectionRequest',
      kind: 'request_write',
      context: <String, Object?>{'requestId': requestId},
      action: () => _requests.cancelConnectionRequest(requestId),
      resultContext: _requestDecisionSummary,
    );
  }

  @override
  Future<ConnectionRequestDecision> acceptConnectionRequest(String requestId) {
    return _traceFuture<ConnectionRequestDecision>(
      operation: 'acceptConnectionRequest',
      kind: 'request_write',
      context: <String, Object?>{'requestId': requestId},
      action: () => _requests.acceptConnectionRequest(requestId),
      resultContext: _requestDecisionSummary,
    );
  }

  @override
  Future<ConnectionRequestDecision> rejectConnectionRequest(String requestId) {
    return _traceFuture<ConnectionRequestDecision>(
      operation: 'rejectConnectionRequest',
      kind: 'request_write',
      context: <String, Object?>{'requestId': requestId},
      action: () => _requests.rejectConnectionRequest(requestId),
      resultContext: _requestDecisionSummary,
    );
  }

  @override
  Future<ConnectionRequestDecision> markConnectionRequestSeen(
    String requestId,
  ) {
    return _traceFuture<ConnectionRequestDecision>(
      operation: 'markConnectionRequestSeen',
      kind: 'request_write',
      context: <String, Object?>{'requestId': requestId},
      action: () => _requests.markConnectionRequestSeen(requestId),
      resultContext: _requestDecisionSummary,
    );
  }

  @override
  Future<ConnectionRequestDecision> muteConnectionRequestsFromPeer(
    String peerId,
  ) {
    return _traceFuture<ConnectionRequestDecision>(
      operation: 'muteConnectionRequestsFromPeer',
      kind: 'request_write',
      context: <String, Object?>{'peerId': peerId},
      action: () => _requests.muteConnectionRequestsFromPeer(peerId),
      resultContext: _requestDecisionSummary,
    );
  }

  @override
  Future<ConnectionRequestDecision> unmuteConnectionRequestsFromPeer(
    String peerId,
  ) {
    return _traceFuture<ConnectionRequestDecision>(
      operation: 'unmuteConnectionRequestsFromPeer',
      kind: 'request_write',
      context: <String, Object?>{'peerId': peerId},
      action: () => _requests.unmuteConnectionRequestsFromPeer(peerId),
      resultContext: _requestDecisionSummary,
    );
  }

  @override
  Future<ConnectionRequestQuotaSnapshot> fetchConnectionRequestQuota() {
    return _traceFuture<ConnectionRequestQuotaSnapshot>(
      operation: 'fetchConnectionRequestQuota',
      kind: 'request_read',
      action: _requests.fetchConnectionRequestQuota,
      resultContext: (ConnectionRequestQuotaSnapshot quota) => quota.toJson(),
    );
  }

  @override
  Stream<List<ConnectionRequestPayload>> watchIncomingConnectionRequests(
    String username,
  ) {
    return _traceStream<List<ConnectionRequestPayload>>(
      operation: 'watchIncomingConnectionRequests',
      kind: 'request_watch',
      context: <String, Object?>{'username': username},
      subscribe: () => _requests.watchIncomingConnectionRequests(username),
      eventContext: _requestPayloadListSummary,
    );
  }

  @override
  Stream<List<ConnectionRequestPayload>> watchOutgoingConnectionRequests(
    String username,
  ) {
    return _traceStream<List<ConnectionRequestPayload>>(
      operation: 'watchOutgoingConnectionRequests',
      kind: 'request_watch',
      context: <String, Object?>{'username': username},
      subscribe: () => _requests.watchOutgoingConnectionRequests(username),
      eventContext: _requestPayloadListSummary,
    );
  }
}

Map<String, Object?> _identitySummary(BackendIdentity identity) {
  return <String, Object?>{
    'username': identity.username,
    'displayNameLength': identity.displayName.length,
    'hasGender': identity.gender != null,
    'registeredAt': identity.registeredAt,
    'lastSeen': identity.lastSeen,
    'lastHeartbeat': identity.lastHeartbeat,
    'online': identity.online,
    'presenceSessionId': identity.presenceSessionId,
    'presenceStartedAt': identity.presenceStartedAt,
    'presenceState': identity.presenceState,
    'hasUid': identity.uid.isNotEmpty,
  };
}

Map<String, Object?> _sdpSummary(SDPPayload payload) {
  return <String, Object?>{
    'sdpType': payload.sdp.type,
    'sdpLength': payload.sdp.sdp?.length ?? 0,
    'ts': payload.ts,
    'restart': payload.restart,
  };
}

Map<String, Object?> _iceCandidateSummary(RTCIceCandidate candidate) {
  return <String, Object?>{
    'candidateLength': candidate.candidate?.length ?? 0,
    'hasSdpMid': candidate.sdpMid?.isNotEmpty == true,
    'sdpMLineIndex': candidate.sdpMLineIndex,
  };
}

Map<String, Object?> _voiceEnvelopeSummary(VoiceSignalingEnvelope envelope) {
  return <String, Object?>{
    'envelopeVersion': envelope.v,
    'algorithm': envelope.alg,
    'ts': envelope.ts,
    if (envelope.sender != null) 'sender': envelope.sender,
    if (envelope.receiver != null) 'receiver': envelope.receiver,
    'nonceLength': envelope.nonce.length,
    'ciphertextLength': envelope.ciphertext.length,
    'macLength': envelope.mac.length,
  };
}

Map<String, Object?> _voiceRoomSummary(VoiceCallRoom room) {
  return <String, Object?>{
    'callId': room.callId,
    'pairId': room.pairId,
    'caller': room.caller,
    'callee': room.callee,
    'status': room.status.name,
    'mediaMode': room.mediaMode.name,
    'createdAt': room.createdAt,
    'updatedAt': room.updatedAt,
    'expiresAt': room.expiresAt,
    if (room.acceptedAt != null) 'acceptedAt': room.acceptedAt,
    if (room.connectedAt != null) 'connectedAt': room.connectedAt,
    if (room.endedAt != null) 'endedAt': room.endedAt,
    if (room.endedBy != null) 'endedBy': room.endedBy,
    if (room.reasonCode != null) 'reasonCode': room.reasonCode,
    if (room.reason != null) 'reasonLength': room.reason!.length,
    'mutedCount': room.muted.length,
    'cameraMutedCount': room.cameraMuted.length,
    'hasOffer': room.offer != null,
    'hasAnswer': room.answer != null,
  };
}

Map<String, Object?> _voiceInboxSummary(VoiceCallInboxEntry entry) {
  return <String, Object?>{
    'callId': entry.callId,
    'from': entry.from,
    'to': entry.to,
    'pairId': entry.pairId,
    'status': entry.status.name,
    'createdAt': entry.createdAt,
    'updatedAt': entry.updatedAt,
    'expiresAt': entry.expiresAt,
  };
}

Map<String, Object?> _voiceIceRecordSummary(
  VoiceCallIceCandidateRecord record,
) {
  return <String, Object?>{
    'callId': record.callId,
    'candidateId': record.candidateId,
    'role': record.role.name,
    'createdAt': record.createdAt,
    ..._voiceEnvelopeSummary(record.envelope),
  };
}

Map<String, Object?> _requestDecisionSummary(
  ConnectionRequestDecision decision,
) {
  return <String, Object?>{
    'allowed': decision.allowed,
    if (decision.reasonCode != null) 'reasonCode': decision.reasonCode!.name,
    if (decision.requestId != null) 'requestId': decision.requestId,
    if (decision.status != null) 'status': decision.status!.name,
    if (decision.peerId != null) 'peerId': decision.peerId,
    if (decision.blockingPeerId != null)
      'blockingPeerId': decision.blockingPeerId,
    if (decision.retryAfterMs != null) 'retryAfterMs': decision.retryAfterMs,
    if (decision.quota != null) 'quota': decision.quota!.toJson(),
  };
}

Map<String, Object?> _requestPayloadListSummary(
  List<ConnectionRequestPayload> payloads,
) {
  return <String, Object?>{
    'resultCount': payloads.length,
    'pendingCount': payloads.where((ConnectionRequestPayload payload) {
      return payload.status == ConnectionRequestStatus.pending;
    }).length,
  };
}

Map<String, Object?> _listCount(List<Object?> values) {
  return <String, Object?>{'resultCount': values.length};
}
