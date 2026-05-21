import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'connection_attempt_coordinator.dart';
import 'file_transfer_progress_batcher.dart';
import 'serialized_runtime_mutations.dart';

part 'file_transfer_runtime.dart';
part 'friend_runtime.dart';

enum FriendRequestResult { sent, acceptedExisting }

String _formatRetryDelay(Duration delay) {
  if (delay.inSeconds <= 1) {
    return '1 second';
  }
  if (delay.inMinutes < 1) {
    return '${delay.inSeconds} seconds';
  }
  if (delay.inMinutes == 1) {
    return '1 minute';
  }
  return '${delay.inMinutes} minutes';
}

class RainRuntimeController with WidgetsBindingObserver {
  RainRuntimeController({
    required this.selfIdentity,
    required this.adapter,
    required this.brain,
    required this.database,
    required this.friendStore,
    required this.messageStore,
    required this.offlineQueueStore,
    required this.messageDeliveryService,
    FileTransferStore? fileTransferStore,
    this.heartbeatInterval = const Duration(minutes: 3),
    this.friendRequestRefreshInterval = Duration.zero,
    this.maxPassivePeerListeners = 32,
    this.networkRecoveryDebounce = const Duration(seconds: 2),
    Duration initialConnectionRetryBackoff = const Duration(seconds: 3),
    Duration maxConnectionRetryBackoff = const Duration(minutes: 1),
    Future<Directory> Function()? documentsDirectoryProvider,
  }) : fileTransferStore = fileTransferStore ?? FileTransferStore(database),
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _connectionCoordinator = ConnectionAttemptCoordinator(
         passiveListenerLimit: maxPassivePeerListeners,
         networkRecoveryDebounce: networkRecoveryDebounce,
         initialRetryBackoff: initialConnectionRetryBackoff,
         maxRetryBackoff: maxConnectionRetryBackoff,
       ) {
    _fileProgressBatcher = FileTransferProgressBatcher(
      markProgress: this.fileTransferStore.markProgress,
    );
  }

  final RainIdentity selfIdentity;
  final SignalingAdapter adapter;
  final SessionManager? brain;
  final RainDatabase database;
  final FriendStore friendStore;
  final MessageStore messageStore;
  final OfflineQueueStore offlineQueueStore;
  final MessageDeliveryService messageDeliveryService;
  final FileTransferStore fileTransferStore;
  final Duration heartbeatInterval;
  final Duration friendRequestRefreshInterval;
  final int maxPassivePeerListeners;
  final Duration networkRecoveryDebounce;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final Set<String> _manualDisconnectedPeers = <String>{};
  final Set<String> _registeredPeerListeners = <String>{};
  final Set<String> _passivePeerListeners = <String>{};
  final Set<String> _unblockingPeers = <String>{};
  final Map<String, StreamSubscription<bool>> _presenceSubscriptions =
      <String, StreamSubscription<bool>>{};
  final Map<String, FileTransferFrame> _pendingFileChunks =
      <String, FileTransferFrame>{};
  final Map<String, int> _receiveProgressOffsets = <String, int>{};
  final Map<String, Future<void>> _fileMessageQueues = <String, Future<void>>{};
  final Map<String, _OutgoingFileSource> _outgoingFileSources =
      <String, _OutgoingFileSource>{};
  final Map<String, String> _outgoingFileHashes = <String, String>{};
  final Set<String> _canceledTransfers = <String>{};
  late final FileTransferProgressBatcher _fileProgressBatcher;
  final ConnectionAttemptCoordinator _connectionCoordinator;

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  Timer? _heartbeatTimer;
  Timer? _friendRequestRefreshTimer;
  Timer? _backgroundOfflineTimer;
  bool _started = false;
  bool _shutDown = false;
  final SerializedRuntimeMutations _localMutations =
      SerializedRuntimeMutations();

  String _normalizedUsername(String username) {
    return username.trim().toLowerCase();
  }

  ConnectionCoordinatorSnapshot connectionCoordinatorSnapshotFor(
    String username,
  ) {
    return _connectionCoordinator.snapshot(
      peerId: _normalizedUsername(username),
    );
  }

  RainGender? _backendGender(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final gender in RainGender.values) {
      if (gender.name == normalized) {
        return gender;
      }
    }
    return null;
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    try {
      await adapter.ensureAuthenticated();
      final currentUid = await adapter.currentUid();
      final now = DateTime.now().millisecondsSinceEpoch;
      await adapter.upsertIdentity(
        BackendIdentity(
          username: selfIdentity.username,
          uid: currentUid,
          displayName: selfIdentity.displayName,
          gender: selfIdentity.gender?.name,
          registeredAt: selfIdentity.createdAt,
          lastSeen: now,
          lastHeartbeat: now,
          online: true,
        ),
      );
      await adapter.setPresence(selfIdentity.username, true);
    } on SignalingSessionExpiredException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Could not authenticate signaling backend: $error'),
        stackTrace,
      );
    }
    await _localMutations.run(offlineQueueStore.recoverInFlightMessages);
    await _syncRelationships();

    final existingFriends = await friendStore.loadFriends();
    for (final friend in existingFriends) {
      if (!_isBlockedState(friend.state)) {
        _watchPresence(friend.username);
      }
    }
    await _reconcilePassivePeerListeners(existingFriends);

    if (friendRequestRefreshInterval > Duration.zero) {
      _friendRequestRefreshTimer = Timer.periodic(
        friendRequestRefreshInterval,
        (_) => _refreshRelationshipsSilently(),
      );
    }

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (!_shutDown && _started) {
        adapter.sendHeartbeat(selfIdentity.username);
      }
    });

    _subscriptions.add(
      adapter
          .onFriendRequest(selfIdentity.username)
          .listen(
            (String from) async {
              await _processIncomingFriendRequest(from);
            },
            onError: (Object error, StackTrace stackTrace) {
              _refreshRelationshipsSilently();
            },
          ),
    );

    _subscriptions.add(
      adapter
          .onRelationshipChanged(selfIdentity.username)
          .listen(
            (String username) {
              final normalizedUsername = _normalizedUsername(username);
              if (normalizedUsername.isNotEmpty &&
                  normalizedUsername !=
                      _normalizedUsername(selfIdentity.username)) {
                _refreshRelationshipsSilently(onlyUsername: normalizedUsername);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              _refreshRelationshipsSilently();
            },
          ),
    );

    if (brain != null) {
      _subscriptions.add(
        brain!.onSessionChanged.listen(_recordSessionAttemptState),
      );

      _subscriptions.add(
        brain!.onIncomingOfferRejected.listen(
          _connectionCoordinator.recordIncomingOfferRejected,
        ),
      );

      _subscriptions.add(
        brain!.onPeerConnected.listen((Session session) async {
          if (_manualDisconnectedPeers.contains(session.peerId)) {
            return;
          }
          _connectionCoordinator.recordAttemptSuccess(session.peerId);
          await _localMutations.run(
            () => messageDeliveryService.flushQueue(
              selfIdentity.username,
              session.peerId,
              sendChat: (String payload) async => session.send(payload),
            ),
          );
        }),
      );

      _subscriptions.add(
        brain!.onPeerDisconnected.listen((String peerId) {
          unawaited(
            _failActiveTransfersForPeer(
              peerId,
              'Connection lost. Transfer canceled.',
            ),
          );
        }),
      );

      _subscriptions.add(
        brain!.onPeerMessage.listen((SessionMessage message) async {
          final peerId = message.peerId;
          if (peerId == null) {
            return;
          }

          if (message.channel == SessionChannel.control) {
            final text = message.text;
            if (text == null) {
              return;
            }
            await _localMutations.run(
              () => messageDeliveryService.handleControlMessage(text),
            );
            return;
          }

          if (message.channel == SessionChannel.chat) {
            final text = message.text;
            if (text == null) {
              return;
            }
            await _localMutations.run(() async {
              final friend = await friendStore.loadFriend(peerId);
              if (friend?.state != FriendState.friend) {
                return;
              }
              final envelope = MessageEnvelope.fromWireString(text);
              await messageDeliveryService.handleIncomingEnvelope(
                envelope,
                receivedAt: message.receivedAt,
                sendAck: (String rawAck) async {
                  brain!.sendControl(peerId, rawAck);
                },
                onStored: (_) => friendStore.incrementUnread(peerId),
              );
            });
            return;
          }

          if (message.channel == SessionChannel.file) {
            unawaited(_enqueueFileChannelMessage(peerId, message));
          }
        }),
      );
    }
  }

  Future<void> acceptFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    // Prefer using an existing displayName if available to preserve
    // the user's chosen display name instead of falling back to the username.
    await _syncRelationships(onlyUsername: normalizedUsername);
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state != FriendState.pendingIncoming &&
        existing?.state != FriendState.pendingOutgoing &&
        existing?.state != FriendState.friend) {
      throw StateError(
        'There is no pending friend request from @$normalizedUsername.',
      );
    }
    final displayName = existing?.displayName ?? normalizedUsername;
    await adapter.upsertFriendship(selfIdentity.username, normalizedUsername);
    await _localMutations.run(
      () => friendStore.markAccepted(
        normalizedUsername,
        displayName: displayName,
        gender: existing?.gender,
      ),
    );
    await _refreshPassivePeerListeners();
  }

  Future<void> blockFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await _failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer was blocked.',
    );
    await adapter.blockUser(selfIdentity.username, normalizedUsername);
    await _clearFriendRequests(normalizedUsername);
    await adapter.deleteFriendship(selfIdentity.username, normalizedUsername);
    await _localMutations.run(() => friendStore.block(normalizedUsername));
    await _stopTrackingPeer(normalizedUsername);
  }

  Future<void> unblockFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    _unblockingPeers.add(normalizedUsername);
    try {
      await adapter.unblockUser(selfIdentity.username, normalizedUsername);
      await _localMutations.run(() => friendStore.unblock(normalizedUsername));
      await _stopTrackingPeer(normalizedUsername);
    } finally {
      _unblockingPeers.remove(normalizedUsername);
    }
  }

  Future<void> unfriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await _failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer was removed.',
    );
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state != FriendState.friend) {
      await rejectFriend(normalizedUsername);
      return;
    }

    await adapter.deleteFriendship(selfIdentity.username, normalizedUsername);
    await _localMutations.run(() => friendStore.reject(normalizedUsername));
    await _stopTrackingPeer(normalizedUsername);
  }

  Future<void> connectPeer(
    String username, {
    bool interactive = false,
    bool waitForConnected = false,
    Duration connectionTimeout = const Duration(seconds: 60),
  }) async {
    final normalizedUsername = _normalizedUsername(username);
    if (brain == null) {
      if (interactive) {
        throw StateError('Peer connection is unavailable right now.');
      }
      return;
    }
    var friend = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (friend?.state != FriendState.friend) {
      await _syncRelationships(onlyUsername: normalizedUsername);
      friend = await _localMutations.run(
        () => friendStore.loadFriend(normalizedUsername),
      );
    }
    if (friend?.state != FriendState.friend) {
      if (interactive) {
        final message = switch (friend?.state) {
          FriendState.pendingOutgoing =>
            'Wait for @$normalizedUsername to accept your friend request before connecting.',
          FriendState.pendingIncoming =>
            'Accept @$normalizedUsername first before trying to connect.',
          FriendState.blocked =>
            'Unblock @$normalizedUsername before trying to connect.',
          FriendState.blockedByPeer =>
            '@$normalizedUsername blocked you. You cannot connect right now.',
          FriendState.friend => null,
          null => 'Could not find @$normalizedUsername in your friends list.',
        };
        if (message != null) {
          throw StateError(message);
        }
      }
      return;
    }
    final current = brain!.getSession(normalizedUsername);
    if (current?.state == SessionState.connected) {
      return;
    }
    if (current?.state == SessionState.connecting ||
        current?.state == SessionState.reconnecting) {
      if (waitForConnected) {
        await _waitForPeerConnection(
          normalizedUsername,
          timeout: connectionTimeout,
        );
      }
      return;
    }
    final backendIdentity = await adapter.fetchIdentity(normalizedUsername);
    final isOnline = backendIdentity?.online ?? friend?.isOnline ?? false;
    await _localMutations.run(
      () => friendStore.updatePresence(normalizedUsername, isOnline),
    );
    if (!isOnline) {
      if (interactive) {
        throw StateError(
          '@$normalizedUsername is offline. Wait for them to come online before connecting.',
        );
      }
      return;
    }
    final retryGate = _connectionCoordinator.retryGate(normalizedUsername);
    if (!retryGate.allowed) {
      if (interactive) {
        throw StateError(
          'Connection to @$normalizedUsername is cooling down after a failed attempt. Try again in ${_formatRetryDelay(retryGate.remaining)}.',
        );
      }
      return;
    }
    _manualDisconnectedPeers.remove(normalizedUsername);
    await _registerPeerListener(normalizedUsername, bestEffort: false);
    await brain!.connect(normalizedUsername);
    if (waitForConnected) {
      await _waitForPeerConnection(
        normalizedUsername,
        timeout: connectionTimeout,
      );
    }
  }

  Future<void> disconnectPeer(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    _manualDisconnectedPeers.add(normalizedUsername);
    _connectionCoordinator.clearRetry(normalizedUsername);
    await _failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer link was disconnected.',
    );
    await brain?.disconnect(normalizedUsername);
    await _unregisterPeerListener(normalizedUsername);
  }

  Future<void> handleNetworkLost(String reason) async {
    if (_shutDown) {
      return;
    }

    List<FileTransferRecord> activeTransfers;
    try {
      activeTransfers = await fileTransferStore.loadActiveTransfers();
    } catch (_) {
      activeTransfers = const <FileTransferRecord>[];
    }
    for (final transfer in activeTransfers) {
      try {
        await _markTransferFailed(transfer.id, reason);
      } catch (_) {
        // Network-loss cleanup is best effort; the next launch can retry cleanup.
      }
    }

    final sessions = brain?.getSessions() ?? const <Session>[];
    for (final session in sessions) {
      _manualDisconnectedPeers.add(session.peerId);
      try {
        await brain?.disconnect(session.peerId);
        await _unregisterPeerListener(session.peerId);
      } catch (_) {
        // The network is already unavailable; stale peer cleanup is best effort.
      }
    }
    for (final peerId in _registeredPeerListeners.toList()) {
      try {
        await _unregisterPeerListener(peerId);
      } catch (_) {
        // The network is already unavailable; stale listener cleanup is best effort.
      }
    }

    _pendingFileChunks.clear();
    _fileMessageQueues.clear();
    _outgoingFileSources.clear();
  }

  Future<void> handleNetworkAvailable(String reason) async {
    if (_shutDown || !_started) {
      return;
    }

    try {
      await adapter.setPresence(selfIdentity.username, true);
      await adapter.sendHeartbeat(selfIdentity.username);
    } catch (_) {
      // Backend reachability is already reported by NetworkStatusService.
    }

    await _connectionCoordinator.scheduleNetworkRecovery(reason, (
      String recoveryReason,
    ) async {
      await brain?.recoverConnections(reason: recoveryReason);
    });
  }

  Future<void> setBackgroundServiceEnabled(bool enabled) async {
    _backgroundOfflineTimer?.cancel();
    if (_started && !_shutDown && !enabled) {
      await adapter.setPresence(selfIdentity.username, true);
    }
  }

  Future<void> dispose() async {
    await _shutdown(
      markOffline: true,
      signOut: false,
      clearLocalSession: false,
    );
  }

  Future<void> logOut() async {
    await _shutdown(markOffline: true, signOut: true, clearLocalSession: true);
  }

  Future<void> markConversationRead(String username) {
    return _localMutations.run(() => friendStore.clearUnread(username));
  }

  Future<void> refreshRelationships({String? onlyUsername}) {
    return _syncRelationships(
      onlyUsername: onlyUsername == null
          ? null
          : _normalizedUsername(onlyUsername),
    );
  }

  Future<void> refreshPeer(String username) {
    return refreshRelationships(onlyUsername: username);
  }

  Future<void> rejectFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await _failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the relationship changed.',
    );
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state == FriendState.friend) {
      await unfriend(normalizedUsername);
      return;
    }
    if (existing?.state == FriendState.pendingIncoming) {
      await adapter.deleteFriendRequest(
        selfIdentity.username,
        normalizedUsername,
      );
    } else if (existing?.state == FriendState.pendingOutgoing) {
      await adapter.deleteFriendRequest(
        normalizedUsername,
        selfIdentity.username,
      );
    }
    await _localMutations.run(() => friendStore.reject(normalizedUsername));
    await _stopTrackingPeer(normalizedUsername);
  }

  Future<void> resendMessage(String messageId) async {
    final queued = await _localMutations.run(
      () => offlineQueueStore.loadById(messageId),
    );
    if (queued == null) {
      return;
    }
    final friend = await _localMutations.run(
      () => friendStore.loadFriend(queued.to),
    );
    if (friend?.state != FriendState.friend) {
      await _localMutations.run(() async {
        await messageStore.markMessageStatus(messageId, MessageStatus.failed);
        await offlineQueueStore.markStatus(
          messageId,
          QueuedMessageStatus.failed,
        );
      });
      return;
    }

    final envelope = queued.toEnvelope(from: selfIdentity.username);
    final session = brain?.getSession(queued.to);
    await _localMutations.run(() async {
      await messageStore.markMessageStatus(messageId, MessageStatus.queued);
      await offlineQueueStore.markStatus(messageId, QueuedMessageStatus.queued);
    });

    if (brain == null || session?.state != SessionState.connected) {
      return;
    }

    await _localMutations.run(
      () => messageDeliveryService.sendEnvelope(
        envelope,
        sendChat: (String payload) async => session!.send(payload),
      ),
    );
  }

  Future<FriendRequestResult> sendFriendRequest(String username) async {
    final targetUsername = _normalizedUsername(username);
    final selfUsername = selfIdentity.username.trim().toLowerCase();
    if (targetUsername.isEmpty || targetUsername == selfUsername) {
      throw Exception('Cannot send friend request to yourself');
    }

    await _syncRelationships(onlyUsername: targetUsername);

    final existing = await _localMutations.run(
      () => friendStore.loadFriend(targetUsername),
    );
    if (existing != null) {
      switch (existing.state) {
        case FriendState.friend:
          throw Exception('You are already friends with @$targetUsername.');
        case FriendState.pendingOutgoing:
          throw Exception(
            'A friend request to @$targetUsername is already pending.',
          );
        case FriendState.pendingIncoming:
          await acceptFriend(targetUsername);
          return FriendRequestResult.acceptedExisting;
        case FriendState.blocked:
          throw Exception('Unblock @$targetUsername before sending a request.');
        case FriendState.blockedByPeer:
          throw Exception(
            '@$targetUsername blocked you. You cannot send a request right now.',
          );
      }
    }

    final targetIdentity = await adapter.fetchIdentity(targetUsername);
    if (targetIdentity == null) {
      throw Exception(
        'User "@$targetUsername" was not found. Ask them to create an account first.',
      );
    }

    await adapter.writeFriendRequest(targetUsername, selfIdentity.username);
    await _localMutations.run(
      () => friendStore.upsertFriend(
        username: targetUsername,
        displayName: targetIdentity.displayName.isEmpty
            ? targetUsername
            : targetIdentity.displayName,
        state: FriendState.pendingOutgoing,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        gender: _backendGender(targetIdentity.gender),
      ),
    );
    _watchPresence(targetUsername);
    return FriendRequestResult.sent;
  }

  Future<void> sendMessage(String peerId, String content) async {
    var friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      await _syncRelationships(onlyUsername: peerId);
      friend = await _localMutations.run(() => friendStore.loadFriend(peerId));
    }
    if (friend?.state != FriendState.friend) {
      throw StateError('Only friends can chat.');
    }
    final envelope = await _localMutations.run(
      () => messageStore.composeOutgoingEnvelope(
        from: selfIdentity.username,
        to: peerId,
        content: content,
      ),
    );

    final session = brain?.getSession(peerId);
    if (brain == null || session?.state != SessionState.connected) {
      await _localMutations.run(
        () => messageDeliveryService.queueOutgoing(envelope),
      );
      return;
    }

    await _localMutations.run(
      () => messageDeliveryService.sendEnvelope(
        envelope,
        sendChat: (String payload) async => session!.send(payload),
      ),
    );
    await _localMutations.run(() => friendStore.clearUnread(peerId));
  }

  Future<void> sendFile({
    required String peerId,
    required String fileName,
    required int fileSize,
    required Stream<List<int>> Function() openRead,
    String? localPath,
    String? mimeType,
  }) async {
    final normalizedPeerId = _normalizedUsername(peerId);
    if (fileSize > maxFileTransferBytes) {
      throw StateError(
        'Files are limited to ${formatFileTransferSize(maxFileTransferBytes)}.',
      );
    }
    if (fileSize < 0) {
      throw StateError('File size is invalid.');
    }

    await _assertCanTransferFile(normalizedPeerId);
    final session = _connectedSession(normalizedPeerId);
    if (session == null) {
      throw StateError('Connect first.');
    }
    if (await fileTransferStore.hasActiveTransferForPeer(normalizedPeerId)) {
      throw StateError('Finish the active file transfer first.');
    }
    await _ensureFileChannelReady(normalizedPeerId);

    final safeName = sanitizeFileName(fileName);
    final transferEnvelope = await _localMutations.run(
      () => messageStore.composeOutgoingEnvelope(
        from: selfIdentity.username,
        to: normalizedPeerId,
        content: FileMessageContent(
          transferId: '',
          fileName: safeName,
          fileSize: fileSize,
          mimeType: mimeType,
        ).encode(),
        type: MessageType.file,
        trackSequence: false,
      ),
    );
    final transferId = transferEnvelope.id;
    final content = FileMessageContent(
      transferId: transferId,
      fileName: safeName,
      fileSize: fileSize,
      mimeType: mimeType,
    ).encode();
    final envelope = MessageEnvelope(
      id: transferEnvelope.id,
      from: transferEnvelope.from,
      to: transferEnvelope.to,
      content: content,
      sentAt: transferEnvelope.sentAt,
      seq: transferEnvelope.seq,
      type: MessageType.file,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    _outgoingFileSources[transferId] = _OutgoingFileSource(
      openRead: openRead,
      localPath: localPath,
    );

    await _localMutations.run(() async {
      await messageStore.storeOutgoingEnvelope(
        envelope,
        status: MessageStatus.sending,
      );
      await fileTransferStore.upsert(
        FileTransferRecord(
          id: transferId,
          peerId: normalizedPeerId,
          messageId: envelope.id,
          direction: FileTransferDirection.outgoing,
          fileName: safeName,
          fileSize: fileSize,
          mimeType: mimeType,
          localPath: localPath,
          bytesTransferred: 0,
          state: FileTransferState.offered,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    final offer = FileTransferFrame.offer(
      transferId: transferId,
      messageId: envelope.id,
      fileName: safeName,
      fileSize: fileSize,
      mimeType: mimeType,
      sentAt: envelope.sentAt,
      seq: envelope.seq,
    );
    try {
      brain!.send(normalizedPeerId, SessionChannel.file, offer.encode());
      await messageStore.markMessageStatus(envelope.id, MessageStatus.sent);
    } catch (error) {
      await _markTransferFailed(transferId, 'File offer failed: $error');
      rethrow;
    }
  }

  Future<void> acceptFileTransfer(String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      throw StateError('File transfer not found.');
    }
    if (transfer.direction != FileTransferDirection.incoming ||
        transfer.state != FileTransferState.offered) {
      throw StateError('This file transfer cannot be accepted.');
    }
    await _assertCanTransferFile(transfer.peerId);
    if (_connectedSession(transfer.peerId) == null) {
      throw StateError('Connect first.');
    }
    await _ensureFileChannelReady(transfer.peerId);
    final paths = await _prepareReceivePaths(transfer);
    await fileTransferStore.markState(
      transfer.id,
      FileTransferState.receiving,
      bytesTransferred: 0,
      localPath: paths.finalPath,
      tempPath: paths.tempPath,
    );
    _receiveProgressOffsets[transfer.id] = 0;
    brain!.send(
      transfer.peerId,
      SessionChannel.file,
      FileTransferFrame.accept(transfer.id).encode(),
    );
  }

  Future<void> rejectFileTransfer(String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      return;
    }
    await fileTransferStore.markState(
      transfer.id,
      FileTransferState.rejected,
      error: 'Rejected.',
    );
    _clearTransferRuntimeState(transfer.id);
    _sendFileControlIfConnected(
      transfer.peerId,
      FileTransferFrame.reject(transfer.id, 'Rejected.'),
    );
  }

  Future<void> cancelFileTransfer(String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      return;
    }
    _canceledTransfers.add(transfer.id);
    await _deleteTempFile(transfer);
    await fileTransferStore.markState(
      transfer.id,
      FileTransferState.canceled,
      error: 'Canceled.',
    );
    _clearTransferRuntimeState(transfer.id);
    _sendFileControlIfConnected(
      transfer.peerId,
      FileTransferFrame.cancel(transfer.id, 'Canceled.'),
    );
  }

  void _recordSessionAttemptState(Session session) {
    switch (session.state) {
      case SessionState.connected:
        _connectionCoordinator.recordAttemptSuccess(session.peerId);
        break;
      case SessionState.failed:
        _connectionCoordinator.recordAttemptFailure(
          session.peerId,
          session.error ?? session.detail,
        );
        break;
      case SessionState.connecting:
      case SessionState.reconnecting:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _shutDown) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        _backgroundOfflineTimer?.cancel();
        unawaited(adapter.setPresence(selfIdentity.username, true));
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _backgroundOfflineTimer?.cancel();
        _backgroundOfflineTimer = Timer(const Duration(seconds: 30), () {
          if (_started && !_shutDown) {
            unawaited(adapter.setPresence(selfIdentity.username, false));
          }
        });
        break;
      case AppLifecycleState.detached:
        _backgroundOfflineTimer?.cancel();
        unawaited(
          _shutdown(
            markOffline: true,
            signOut: false,
            clearLocalSession: false,
          ),
        );
        break;
    }
  }

  Future<void> _shutdown({
    required bool markOffline,
    required bool signOut,
    required bool clearLocalSession,
  }) async {
    if (_shutDown) {
      return;
    }
    _shutDown = true;
    const keepBackgroundPresence = false;

    if (markOffline && _started && !keepBackgroundPresence) {
      try {
        await adapter.setPresence(selfIdentity.username, false);
      } catch (error) {
        // Ignore permission errors during logout
      }
    }

    if (brain != null) {
      for (final session in brain!.getSessions()) {
        try {
          await _failActiveTransfersForPeer(
            session.peerId,
            'Transfer canceled because Rain is closing.',
          );
          await brain!.disconnect(session.peerId);
          await _unregisterPeerListener(session.peerId);
        } catch (error) {
          // Ignore errors during cleanup
        }
      }
      for (final peerId in _registeredPeerListeners.toList()) {
        try {
          await _unregisterPeerListener(peerId);
        } catch (_) {
          // Ignore errors during cleanup
        }
      }
    }

    WidgetsBinding.instance.removeObserver(this);
    _backgroundOfflineTimer?.cancel();
    _heartbeatTimer?.cancel();
    _friendRequestRefreshTimer?.cancel();
    _connectionCoordinator.dispose();

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    for (final subscription in _presenceSubscriptions.values) {
      await subscription.cancel();
    }
    _presenceSubscriptions.clear();

    if (signOut) {
      await adapter.signOut();
    }

    if (clearLocalSession) {
      await _localMutations.run(database.clearSessionData);
    }
  }
}
