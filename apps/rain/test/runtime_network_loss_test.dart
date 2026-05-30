import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show MediaStream, MediaStreamTrack, RTCSessionDescription;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/connection_attempt_coordinator.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('network loss fails active transfers and deletes temp files', () async {
    final db = RainDatabase(NativeDatabase.memory());
    final temp = await Directory.systemTemp.createTemp('rain-network-loss-');
    addTearDown(() async {
      await db.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final tempFile = File('${temp.path}${Platform.pathSeparator}file.part');
    await tempFile.writeAsString('partial');
    final transferStore = FileTransferStore(db);
    await transferStore.upsert(
      FileTransferRecord(
        id: 'transfer-1',
        peerId: 'bob',
        messageId: 'message-1',
        direction: FileTransferDirection.incoming,
        fileName: 'clip.bin',
        fileSize: 4096,
        localPath: '${temp.path}${Platform.pathSeparator}clip.bin',
        tempPath: tempFile.path,
        bytesTransferred: 7,
        state: FileTransferState.receiving,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: null,
      ),
      adapter: NoopSignalingAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
      fileTransferStore: transferStore,
      networkRecoveryDebounce: Duration.zero,
    );

    await runtime.handleNetworkLost(
      'Internet connection lost. Transfer canceled.',
    );

    final failed = await transferStore.loadById('transfer-1');
    expect(failed?.state, FileTransferState.failed);
    expect(failed?.error, 'Internet connection lost. Transfer canceled.');
    expect(await tempFile.exists(), isFalse);
  });

  test('peer connection drop fails active transfers clearly', () async {
    final db = RainDatabase(NativeDatabase.memory());
    final adapter = NoopSignalingAdapter();
    final brain = _DisconnectingSessionManager();
    final temp = await Directory.systemTemp.createTemp('rain-peer-drop-');
    addTearDown(() async {
      await brain.close();
      await db.close();
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    await adapter.upsertFriendship('alice', 'bob');
    await db
        .into(db.friends)
        .insert(
          FriendsCompanion.insert(
            username: 'bob',
            displayName: 'Bob',
            state: FriendState.friend.name,
            addedAt: 1,
          ),
        );
    final tempFile = File('${temp.path}${Platform.pathSeparator}file.part');
    await tempFile.writeAsString('partial');
    final transferStore = FileTransferStore(db);
    await transferStore.upsert(
      FileTransferRecord(
        id: 'transfer-1',
        peerId: 'bob',
        messageId: 'message-1',
        direction: FileTransferDirection.incoming,
        fileName: 'clip.bin',
        fileSize: 4096,
        localPath: '${temp.path}${Platform.pathSeparator}clip.bin',
        tempPath: tempFile.path,
        bytesTransferred: 7,
        state: FileTransferState.receiving,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: null,
      ),
      adapter: adapter,
      brain: brain,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
      fileTransferStore: transferStore,
      networkRecoveryDebounce: Duration.zero,
    );
    addTearDown(runtime.dispose);
    await adapter.setPresence('bob', true);
    await runtime.start();

    brain.emitPeerDisconnected('bob');
    await _waitForTransferState(
      transferStore,
      'transfer-1',
      FileTransferState.failed,
    );

    final failed = await transferStore.loadById('transfer-1');
    expect(failed?.state, FileTransferState.failed);
    expect(failed?.error, 'Connection lost. Transfer canceled.');
    expect(await tempFile.exists(), isFalse);
    expect(
      runtime.connectionCoordinatorSnapshotFor('bob').disconnectIntent,
      PeerDisconnectIntent.remoteManual,
    );
  });

  test('network recovery asks active peer manager to restart paths', () async {
    final db = RainDatabase(NativeDatabase.memory());
    final adapter = NoopSignalingAdapter();
    final brain = _DisconnectingSessionManager();
    addTearDown(() async {
      await brain.close();
      await db.close();
    });

    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 1,
        gender: null,
      ),
      adapter: adapter,
      brain: brain,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
      networkRecoveryDebounce: Duration.zero,
    );
    addTearDown(runtime.dispose);
    await runtime.start();

    await runtime.handleNetworkAvailable(
      'Network changed. Restarting peer connection paths.',
    );

    expect(brain.recoveryReasons, <String>[
      'Network changed. Restarting peer connection paths.',
    ]);
  });
}

Future<void> _waitForTransferState(
  FileTransferStore store,
  String transferId,
  FileTransferState expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    final transfer = await store.loadById(transferId);
    if (transfer?.state == expected) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  final transfer = await store.loadById(transferId);
  fail(
    'Timed out waiting for $transferId to become ${expected.name}; '
    'last state was ${transfer?.state.name}.',
  );
}

class _DisconnectingSessionManager implements SessionManager {
  final List<String> recoveryReasons = <String>[];
  final StreamController<Session> _connected =
      StreamController<Session>.broadcast();
  final StreamController<String> _disconnected =
      StreamController<String>.broadcast();
  final StreamController<SessionMessage> _messages =
      StreamController<SessionMessage>.broadcast();
  final StreamController<SessionRemoteTrack> _remoteTracks =
      StreamController<SessionRemoteTrack>.broadcast();
  final StreamController<Session> _changes =
      StreamController<Session>.broadcast();
  final StreamController<IncomingOfferRejection> _incomingOfferRejected =
      StreamController<IncomingOfferRejection>.broadcast();

  void emitPeerDisconnected(String peerId) {
    _disconnected.add(peerId);
  }

  Future<void> close() async {
    await _connected.close();
    await _disconnected.close();
    await _messages.close();
    await _remoteTracks.close();
    await _changes.close();
    await _incomingOfferRejected.close();
  }

  @override
  Future<int> bufferedAmount(String peerId, SessionChannel channel) async => 0;

  @override
  Future<Session> connect(String peerId) async {
    throw UnimplementedError();
  }

  @override
  Future<void> disconnect(String peerId) async {}

  @override
  Future<void> recoverConnection(
    String peerId, {
    String reason = 'Network changed. Restarting peer connection.',
  }) async {
    recoveryReasons.add(reason);
  }

  @override
  Future<void> recoverConnections({
    String reason = 'Network changed. Restarting peer connections.',
  }) async {
    recoveryReasons.add(reason);
  }

  @override
  List<Session> getSessions() => const <Session>[];

  @override
  Session? getSession(String peerId) => null;

  @override
  bool isChannelOpen(String peerId, SessionChannel channel) => false;

  @override
  Stream<Session> get onPeerConnected => _connected.stream;

  @override
  Stream<String> get onPeerDisconnected => _disconnected.stream;

  @override
  Stream<SessionMessage> get onPeerMessage => _messages.stream;

  @override
  Stream<SessionRemoteTrack> get onRemoteTrack => _remoteTracks.stream;

  @override
  Stream<Session> get onSessionChanged => _changes.stream;

  @override
  Stream<IncomingOfferRejection> get onIncomingOfferRejected =>
      _incomingOfferRejected.stream;

  @override
  Future<void> openChannel(String peerId, SessionChannel channel) async {}

  @override
  Future<void> startLocalAudio(String peerId) async {}

  @override
  Future<void> stopLocalAudio(String peerId) async {}

  @override
  Future<void> setMicrophoneMuted(String peerId, {required bool muted}) async {}

  @override
  Future<VoiceMediaConnection> createVoiceMediaConnection(String peerId) async {
    return _NoopVoiceMediaConnection();
  }

  @override
  Future<CallMediaConnection> createCallMediaConnection(String peerId) async {
    return _NoopCallMediaConnection();
  }

  @override
  Future<RTCSessionDescription> createMediaOffer(String peerId) async =>
      RTCSessionDescription('media-offer-$peerId', 'offer');

  @override
  Future<RTCSessionDescription> applyMediaOffer(
    String peerId,
    RTCSessionDescription offer,
  ) async => RTCSessionDescription('media-answer-$peerId', 'answer');

  @override
  Future<void> applyMediaAnswer(
    String peerId,
    RTCSessionDescription answer,
  ) async {}

  @override
  Future<void> registerPeer(
    String peerId, {
    IncomingOfferGuard? incomingOfferGuard,
  }) async {}

  @override
  void send(String peerId, SessionChannel channel, Object data) {}

  @override
  void sendControl(String peerId, String data) {}

  @override
  Future<void> unregisterPeer(String peerId) async {}
}

class _NoopVoiceMediaConnection implements VoiceMediaConnection {
  final StreamController<VoiceIceCandidate> _ice =
      StreamController<VoiceIceCandidate>.broadcast();
  final StreamController<VoiceRemoteAudioTrack> _tracks =
      StreamController<VoiceRemoteAudioTrack>.broadcast();
  final StreamController<VoiceMediaAudioLevel> _audioLevels =
      StreamController<VoiceMediaAudioLevel>.broadcast();
  final StreamController<VoiceMediaState> _states =
      StreamController<VoiceMediaState>.broadcast();

  @override
  Stream<VoiceIceCandidate> get onIceCandidate => _ice.stream;

  @override
  Stream<VoiceRemoteAudioTrack> get onRemoteAudioTrack => _tracks.stream;

  @override
  Stream<VoiceMediaAudioLevel> get onAudioLevelChanged => _audioLevels.stream;

  @override
  Stream<VoiceMediaState> get onStateChanged => _states.stream;

  @override
  VoiceMediaDiagnostics get diagnostics => const VoiceMediaDiagnostics();

  @override
  Future<void> startLocalAudio() async {}

  @override
  Future<VoiceSessionDescription> createOffer({
    bool iceRestart = false,
  }) async => const VoiceSessionDescription(sdp: 'offer', type: 'offer');

  @override
  Future<VoiceSessionDescription> acceptOffer(
    VoiceSessionDescription offer,
  ) async => const VoiceSessionDescription(sdp: 'answer', type: 'answer');

  @override
  Future<void> applyAnswer(VoiceSessionDescription answer) async {}

  @override
  Future<void> addRemoteCandidate(VoiceIceCandidate candidate) async {}

  @override
  Future<void> setMuted({required bool muted}) async {}

  @override
  Future<void> setDeafened({required bool deafened}) async {}

  @override
  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route) async {}

  @override
  Future<void> selectAudioOutputDevice(String deviceId) async {}

  @override
  Future<void> dispose() async {
    await _ice.close();
    await _tracks.close();
    await _audioLevels.close();
    await _states.close();
  }
}

class _NoopCallMediaConnection implements CallMediaConnection {
  final StreamController<CallIceCandidate> _ice =
      StreamController<CallIceCandidate>.broadcast();
  final StreamController<CallRemoteMediaTrack> _tracks =
      StreamController<CallRemoteMediaTrack>.broadcast();
  final StreamController<CallMediaState> _states =
      StreamController<CallMediaState>.broadcast();

  @override
  Stream<CallIceCandidate> get onIceCandidate => _ice.stream;

  @override
  Stream<CallRemoteMediaTrack> get onRemoteTrack => _tracks.stream;

  @override
  Stream<CallMediaState> get onStateChanged => _states.stream;

  @override
  CallMediaDiagnostics get diagnostics => const CallMediaDiagnostics();

  @override
  MediaStream? get localStream => null;

  @override
  MediaStreamTrack? get localVideoTrack => null;

  @override
  Future<void> startLocalMedia({required CallMediaKind kind}) async {}

  @override
  Future<CallSessionDescription> createOffer({
    required CallMediaKind kind,
    bool iceRestart = false,
  }) async => const CallSessionDescription(sdp: 'offer', type: 'offer');

  @override
  Future<CallSessionDescription> acceptOffer(
    CallSessionDescription offer, {
    required CallMediaKind kind,
  }) async => const CallSessionDescription(sdp: 'answer', type: 'answer');

  @override
  Future<void> applyAnswer(CallSessionDescription answer) async {}

  @override
  Future<void> addRemoteCandidate(CallIceCandidate candidate) async {}

  @override
  Future<void> setMicrophoneMuted({required bool muted}) async {}

  @override
  Future<void> setCameraMuted({required bool muted}) async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> setDeafened({required bool deafened}) async {}

  @override
  Future<void> setAudioOutputRoute(CallMediaOutputRoute route) async {}

  @override
  Future<void> selectAudioOutputDevice(String deviceId) async {}

  @override
  Future<void> refreshProcessingConfig() async {}

  @override
  Future<void> dispose() async {
    await _ice.close();
    await _tracks.close();
    await _states.close();
  }
}
