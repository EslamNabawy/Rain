import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'serialized_runtime_mutations.dart';

enum FriendRequestResult { sent, acceptedExisting }

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
  }) : fileTransferStore = fileTransferStore ?? FileTransferStore(database);

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
  final Set<String> _manualDisconnectedPeers = <String>{};
  final Set<String> _unblockingPeers = <String>{};
  final Map<String, StreamSubscription<bool>> _presenceSubscriptions =
      <String, StreamSubscription<bool>>{};
  final Map<String, FileTransferFrame> _pendingFileChunks =
      <String, FileTransferFrame>{};
  final Map<String, _OutgoingFileSource> _outgoingFileSources =
      <String, _OutgoingFileSource>{};
  final Set<String> _canceledTransfers = <String>{};

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
        brain!.onPeerConnected.listen((Session session) async {
          if (_manualDisconnectedPeers.contains(session.peerId)) {
            return;
          }
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
          unawaited(_failActiveTransfersForPeer(peerId, 'Peer disconnected.'));
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
            await _handleFileChannelMessage(peerId, message);
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
    _watchPresence(normalizedUsername);
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
    Duration connectionTimeout = const Duration(seconds: 15),
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
    _manualDisconnectedPeers.remove(normalizedUsername);
    await brain!.registerPeer(normalizedUsername);
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
    await _failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer link was disconnected.',
    );
    await brain?.disconnect(normalizedUsername);
    await brain?.unregisterPeer(normalizedUsername);
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
    _sendFileControlIfConnected(
      transfer.peerId,
      FileTransferFrame.cancel(transfer.id, 'Canceled.'),
    );
  }

  Future<void> _handleFileChannelMessage(
    String peerId,
    SessionMessage message,
  ) async {
    final text = message.text;
    if (text != null) {
      FileTransferFrame frame;
      try {
        frame = FileTransferFrame.parse(text);
      } on FormatException catch (error) {
        _sendFileControlIfConnected(
          peerId,
          FileTransferFrame.fail('unknown', error.message),
        );
        return;
      }
      await _handleFileFrame(peerId, frame, receivedAt: message.receivedAt);
      return;
    }

    final binary = message.binary;
    if (binary != null) {
      await _handleFileChunkBytes(peerId, binary);
    }
  }

  Future<void> _handleFileFrame(
    String peerId,
    FileTransferFrame frame, {
    required DateTime receivedAt,
  }) async {
    switch (frame.type) {
      case FileTransferFrame.offerType:
        await _handleFileOffer(peerId, frame, receivedAt: receivedAt);
        break;
      case FileTransferFrame.acceptType:
        await _handleFileAccept(peerId, frame.transferId);
        break;
      case FileTransferFrame.rejectType:
        await _handleFileTerminalFrame(
          frame.transferId,
          FileTransferState.rejected,
          frame.reason ?? 'Rejected.',
        );
        break;
      case FileTransferFrame.chunkType:
        _pendingFileChunks[peerId] = frame;
        break;
      case FileTransferFrame.completeType:
        await _handleFileComplete(peerId, frame.transferId);
        break;
      case FileTransferFrame.receivedType:
        await _handleFileReceived(frame.transferId);
        break;
      case FileTransferFrame.cancelType:
        await _handleFileTerminalFrame(
          frame.transferId,
          FileTransferState.canceled,
          frame.reason ?? 'Canceled.',
        );
        break;
      case FileTransferFrame.failType:
        await _handleFileTerminalFrame(
          frame.transferId,
          FileTransferState.failed,
          frame.reason ?? 'Transfer failed.',
        );
        break;
    }
  }

  Future<void> _handleFileOffer(
    String peerId,
    FileTransferFrame frame, {
    required DateTime receivedAt,
  }) async {
    final messageId = frame.messageId;
    final fileName = frame.fileName;
    final fileSize = frame.fileSize;
    final sentAt = frame.sentAt;
    final seq = frame.seq;
    if (messageId == null ||
        fileName == null ||
        fileSize == null ||
        sentAt == null ||
        seq == null) {
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.reject(frame.transferId, 'Malformed file offer.'),
      );
      return;
    }

    final existing = await fileTransferStore.loadById(frame.transferId);
    if (existing != null) {
      return;
    }

    final friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.reject(
          frame.transferId,
          'Only friends can send files.',
        ),
      );
      return;
    }
    if (fileSize > maxFileTransferBytes) {
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.reject(
          frame.transferId,
          'Files are limited to ${formatFileTransferSize(maxFileTransferBytes)}.',
        ),
      );
      return;
    }
    if (await fileTransferStore.hasActiveTransferForPeer(peerId)) {
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.reject(
          frame.transferId,
          'Finish the active file transfer first.',
        ),
      );
      return;
    }

    final safeName = sanitizeFileName(fileName);
    final content = FileMessageContent(
      transferId: frame.transferId,
      fileName: safeName,
      fileSize: fileSize,
      mimeType: frame.mimeType,
    ).encode();
    final envelope = MessageEnvelope(
      id: messageId,
      from: peerId,
      to: selfIdentity.username,
      content: content,
      sentAt: sentAt,
      seq: seq,
      type: MessageType.file,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    await _localMutations.run(() async {
      if (!await messageStore.containsMessage(messageId)) {
        await messageStore.forceStoreIncomingEnvelope(
          envelope,
          receivedAt: receivedAt,
          trackSequence: false,
        );
        await friendStore.incrementUnread(peerId);
      }
      await fileTransferStore.upsert(
        FileTransferRecord(
          id: frame.transferId,
          peerId: peerId,
          messageId: messageId,
          direction: FileTransferDirection.incoming,
          fileName: safeName,
          fileSize: fileSize,
          mimeType: frame.mimeType,
          bytesTransferred: 0,
          state: FileTransferState.offered,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });
  }

  Future<void> _handleFileAccept(String peerId, String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null ||
        transfer.peerId != peerId ||
        transfer.direction != FileTransferDirection.outgoing ||
        transfer.state != FileTransferState.offered) {
      return;
    }
    await fileTransferStore.markState(transferId, FileTransferState.accepted);
    unawaited(_sendTransferBytes(transferId));
  }

  Future<void> _handleFileChunkBytes(String peerId, Uint8List bytes) async {
    final frame = _pendingFileChunks.remove(peerId);
    if (frame == null) {
      return;
    }
    final transfer = await fileTransferStore.loadById(frame.transferId);
    if (transfer == null ||
        transfer.peerId != peerId ||
        transfer.direction != FileTransferDirection.incoming ||
        transfer.state != FileTransferState.receiving) {
      return;
    }
    if (frame.offset != transfer.bytesTransferred ||
        frame.byteCount != bytes.lengthInBytes ||
        transfer.tempPath == null) {
      await _markTransferFailed(transfer.id, 'Received an invalid file chunk.');
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(transfer.id, 'Received an invalid file chunk.'),
      );
      return;
    }

    final tempFile = File(transfer.tempPath!);
    await tempFile.parent.create(recursive: true);
    final sink = tempFile.openWrite(mode: FileMode.append);
    sink.add(bytes);
    await sink.close();
    await fileTransferStore.markProgress(
      transfer.id,
      transfer.bytesTransferred + bytes.lengthInBytes,
    );
  }

  Future<void> _handleFileComplete(String peerId, String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null ||
        transfer.peerId != peerId ||
        transfer.direction != FileTransferDirection.incoming ||
        transfer.tempPath == null ||
        transfer.localPath == null) {
      return;
    }
    final tempFile = File(transfer.tempPath!);
    if (!await tempFile.exists()) {
      await _markTransferFailed(transfer.id, 'Received file is missing.');
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(transfer.id, 'Received file is missing.'),
      );
      return;
    }
    final actualBytes = await tempFile.length();
    if (actualBytes != transfer.fileSize) {
      await _markTransferFailed(
        transfer.id,
        'Received file size did not match the offer.',
      );
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(
          transfer.id,
          'Received file size did not match the offer.',
        ),
      );
      return;
    }

    final finalFile = File(transfer.localPath!);
    await finalFile.parent.create(recursive: true);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalFile.path);
    await fileTransferStore.markState(
      transfer.id,
      FileTransferState.completed,
      bytesTransferred: transfer.fileSize,
      localPath: finalFile.path,
    );
    _sendFileControlIfConnected(
      peerId,
      FileTransferFrame.received(transfer.id),
    );
  }

  Future<void> _handleFileReceived(String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null ||
        transfer.direction != FileTransferDirection.outgoing) {
      return;
    }
    _outgoingFileSources.remove(transferId);
    _canceledTransfers.remove(transferId);
    await _localMutations.run(() async {
      await fileTransferStore.markState(
        transferId,
        FileTransferState.completed,
        bytesTransferred: transfer.fileSize,
      );
      await messageStore.markMessageStatus(
        transfer.messageId,
        MessageStatus.delivered,
      );
    });
  }

  Future<void> _handleFileTerminalFrame(
    String transferId,
    FileTransferState state,
    String reason,
  ) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      return;
    }
    _outgoingFileSources.remove(transferId);
    _canceledTransfers.add(transferId);
    await _deleteTempFile(transfer);
    await _localMutations.run(() async {
      await fileTransferStore.markState(transferId, state, error: reason);
      if (transfer.direction == FileTransferDirection.outgoing) {
        await messageStore.markMessageStatus(
          transfer.messageId,
          MessageStatus.failed,
        );
      }
    });
  }

  Future<void> _sendTransferBytes(String transferId) async {
    var transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      return;
    }
    final source = _outgoingFileSources[transferId];
    if (source == null && transfer.localPath == null) {
      await _markTransferFailed(
        transferId,
        'Original file is no longer available.',
      );
      return;
    }

    try {
      final initialPeerId = transfer.peerId;
      final initialMessageId = transfer.messageId;
      await _ensureFileChannelReady(initialPeerId);
      await _localMutations.run(() async {
        await fileTransferStore.markState(
          transferId,
          FileTransferState.sending,
          bytesTransferred: 0,
        );
        await messageStore.markMessageStatus(
          initialMessageId,
          MessageStatus.sending,
        );
      });
      transfer = await fileTransferStore.loadById(transferId);
      if (transfer == null) {
        return;
      }
      final activeTransfer = transfer;
      final peerId = activeTransfer.peerId;
      final messageId = activeTransfer.messageId;
      final fileSize = activeTransfer.fileSize;

      final openRead =
          source?.openRead ?? () => File(activeTransfer.localPath!).openRead();
      var offset = 0;
      var index = 0;
      final pending = <int>[];
      await for (final bytes in openRead()) {
        pending.addAll(bytes);
        while (pending.length >= fileTransferChunkBytes) {
          final chunk = Uint8List.fromList(
            pending.take(fileTransferChunkBytes).toList(growable: false),
          );
          pending.removeRange(0, fileTransferChunkBytes);
          await _sendFileChunk(transferId, peerId, chunk, index, offset);
          offset += chunk.lengthInBytes;
          index += 1;
        }
      }
      if (pending.isNotEmpty) {
        final chunk = Uint8List.fromList(pending);
        await _sendFileChunk(transferId, peerId, chunk, index, offset);
        offset += chunk.lengthInBytes;
      }
      if (_canceledTransfers.contains(transferId)) {
        return;
      }
      if (offset != fileSize) {
        throw StateError('File changed while sending.');
      }
      brain!.send(
        peerId,
        SessionChannel.file,
        FileTransferFrame.complete(transferId).encode(),
      );
      await messageStore.markMessageStatus(messageId, MessageStatus.pendingAck);
    } catch (error) {
      final reason = _formatTransferError(error);
      await _markTransferFailed(transferId, reason);
      final latest = await fileTransferStore.loadById(transferId);
      if (latest != null) {
        _sendFileControlIfConnected(
          latest.peerId,
          FileTransferFrame.fail(transferId, reason),
        );
      }
    }
  }

  Future<void> _sendFileChunk(
    String transferId,
    String peerId,
    Uint8List chunk,
    int index,
    int offset,
  ) async {
    if (_canceledTransfers.contains(transferId)) {
      throw StateError('Transfer canceled.');
    }
    if (_connectedSession(peerId) == null) {
      throw StateError('Peer disconnected.');
    }
    await _waitForFileBuffer(peerId);
    brain!.send(
      peerId,
      SessionChannel.file,
      FileTransferFrame.chunk(
        transferId: transferId,
        index: index,
        offset: offset,
        byteCount: chunk.lengthInBytes,
      ).encode(),
    );
    brain!.send(peerId, SessionChannel.file, chunk);
    await fileTransferStore.markProgress(
      transferId,
      offset + chunk.lengthInBytes,
    );
  }

  Future<void> _waitForFileBuffer(String peerId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (_connectedSession(peerId) == null) {
        throw StateError('Peer disconnected.');
      }
      final buffered = await brain!.bufferedAmount(peerId, SessionChannel.file);
      if (buffered <= fileTransferLowWatermarkBytes) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw StateError('File channel is congested. Try again.');
  }

  Future<void> _assertCanTransferFile(String peerId) async {
    var friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      await _syncRelationships(onlyUsername: peerId);
      friend = await _localMutations.run(() => friendStore.loadFriend(peerId));
    }
    if (friend?.state != FriendState.friend) {
      throw StateError('Only friends can exchange files.');
    }
  }

  Session? _connectedSession(String peerId) {
    final session = brain?.getSession(peerId);
    return session?.state == SessionState.connected ? session : null;
  }

  Future<void> _ensureFileChannelReady(String peerId) async {
    if (brain == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
    if (_connectedSession(peerId) == null) {
      throw StateError('Connect first.');
    }
    await brain!.openChannel(peerId, SessionChannel.file);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (_connectedSession(peerId) == null) {
        throw StateError('Connect first.');
      }
      if (brain!.isChannelOpen(peerId, SessionChannel.file)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('File channel did not open. Reconnect and try again.');
  }

  void _sendFileControlIfConnected(String peerId, FileTransferFrame frame) {
    if (_connectedSession(peerId) == null ||
        !(brain?.isChannelOpen(peerId, SessionChannel.file) ?? false)) {
      return;
    }
    try {
      brain!.send(peerId, SessionChannel.file, frame.encode());
    } catch (_) {
      // Best effort: terminal file controls should not crash the runtime.
    }
  }

  Future<void> _markTransferFailed(String transferId, String reason) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      return;
    }
    _outgoingFileSources.remove(transferId);
    _canceledTransfers.add(transferId);
    await _deleteTempFile(transfer);
    await _localMutations.run(() async {
      await fileTransferStore.markState(
        transferId,
        FileTransferState.failed,
        error: reason,
      );
      if (transfer.direction == FileTransferDirection.outgoing) {
        await messageStore.markMessageStatus(
          transfer.messageId,
          MessageStatus.failed,
        );
      }
    });
  }

  Future<void> _failActiveTransfersForPeer(String peerId, String reason) async {
    List<FileTransferRecord> active;
    try {
      active = await fileTransferStore.loadActiveTransfers(peerId: peerId);
    } catch (_) {
      return;
    }
    for (final transfer in active) {
      try {
        await _markTransferFailed(transfer.id, reason);
      } catch (_) {
        // Transfer cleanup is best effort during shutdown and relationship churn.
      }
    }
    _pendingFileChunks.remove(peerId);
  }

  Future<_ReceivePaths> _prepareReceivePaths(
    FileTransferRecord transfer,
  ) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      [
        documents.path,
        'received-files',
        sanitizeFileName(transfer.peerId),
      ].join(Platform.pathSeparator),
    );
    await directory.create(recursive: true);

    final safeName = sanitizeFileName(transfer.fileName);
    final dot = safeName.lastIndexOf('.');
    final hasExtension = dot > 0 && dot < safeName.length - 1;
    final stem = hasExtension ? safeName.substring(0, dot) : safeName;
    final extension = hasExtension ? safeName.substring(dot) : '';
    var candidate = File('${directory.path}${Platform.pathSeparator}$safeName');
    var suffix = 1;
    while (await candidate.exists()) {
      candidate = File(
        '${directory.path}${Platform.pathSeparator}$stem ($suffix)$extension',
      );
      suffix += 1;
    }
    final tempPath = '${candidate.path}.part-${transfer.id}';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    return _ReceivePaths(finalPath: candidate.path, tempPath: tempPath);
  }

  Future<void> _deleteTempFile(FileTransferRecord transfer) async {
    final tempPath = transfer.tempPath;
    if (tempPath == null || tempPath.isEmpty) {
      return;
    }
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  }

  String _formatTransferError(Object error) {
    final raw = error.toString();
    const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
    for (final prefix in prefixes) {
      if (raw.startsWith(prefix)) {
        return raw.substring(prefix.length);
      }
    }
    return raw;
  }

  void _watchPresence(String username) {
    if (_presenceSubscriptions.containsKey(username)) {
      return;
    }

    _presenceSubscriptions[username] = adapter.watchPresence(username).listen((
      bool isOnline,
    ) async {
      if (_shutDown) {
        return;
      }
      try {
        await _localMutations.run(
          () => friendStore.updatePresence(username, isOnline),
        );
      } catch (_) {
        // Ignore late presence callbacks during shutdown or store teardown.
      }
    });
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
          await brain!.unregisterPeer(session.peerId);
        } catch (error) {
          // Ignore errors during cleanup
        }
      }
    }

    WidgetsBinding.instance.removeObserver(this);
    _backgroundOfflineTimer?.cancel();
    _heartbeatTimer?.cancel();
    _friendRequestRefreshTimer?.cancel();

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

  Future<void> _clearFriendRequests(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await adapter.deleteFriendRequest(
      selfIdentity.username,
      normalizedUsername,
    );
    await adapter.deleteFriendRequest(
      normalizedUsername,
      selfIdentity.username,
    );
  }

  void _refreshRelationshipsSilently({String? onlyUsername}) {
    if (_shutDown || !_started) {
      return;
    }
    unawaited(_safeSyncRelationships(onlyUsername: onlyUsername));
  }

  Future<void> _processIncomingFriendRequest(String from) async {
    if (_shutDown) {
      return;
    }
    final normalizedFrom = _normalizedUsername(from);
    var existing = await _localMutations.run(() {
      if (_shutDown) {
        return Future<FriendRecord?>.value();
      }
      return friendStore.loadFriend(normalizedFrom);
    });
    if (_shutDown) {
      return;
    }
    BackendIdentity? backendIdentity;
    try {
      backendIdentity = await adapter.fetchIdentity(normalizedFrom);
    } catch (_) {
      backendIdentity = null;
    }
    final backendDisplayName = backendIdentity?.displayName.trim() ?? '';
    final displayName = backendDisplayName.isNotEmpty
        ? backendDisplayName
        : (existing?.displayName ?? normalizedFrom);
    final gender = _backendGender(backendIdentity?.gender) ?? existing?.gender;
    if (_shutDown) {
      return;
    }
    if (existing?.state == FriendState.blockedByPeer) {
      await _syncRelationships(onlyUsername: normalizedFrom);
      existing = await _localMutations.run(
        () => friendStore.loadFriend(normalizedFrom),
      );
    }
    if (existing?.state == FriendState.blocked) {
      await adapter.blockUser(selfIdentity.username, normalizedFrom);
      await _clearFriendRequests(normalizedFrom);
      await adapter.deleteFriendship(selfIdentity.username, normalizedFrom);
      await _stopTrackingPeer(normalizedFrom);
      return;
    }
    if (existing?.state == FriendState.blockedByPeer) {
      await _clearFriendRequests(normalizedFrom);
      await adapter.deleteFriendship(selfIdentity.username, normalizedFrom);
      await _stopTrackingPeer(normalizedFrom);
      return;
    }
    if (existing?.state == FriendState.pendingOutgoing ||
        existing?.state == FriendState.friend) {
      await adapter.upsertFriendship(selfIdentity.username, normalizedFrom);
      await _localMutations.run(() {
        if (_shutDown) {
          return Future<void>.value();
        }
        return friendStore.markAccepted(
          normalizedFrom,
          displayName: displayName,
          gender: gender,
        );
      });
    } else if (!_isBlockedState(existing?.state)) {
      await _localMutations.run(() {
        if (_shutDown) {
          return Future<void>.value();
        }
        return friendStore.upsertFriend(
          username: normalizedFrom,
          displayName: displayName,
          state: FriendState.pendingIncoming,
          addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
          gender: gender,
        );
      });
    }
    _watchPresence(normalizedFrom);
  }

  Future<void> _safeSyncRelationships({String? onlyUsername}) async {
    try {
      await _syncRelationships(onlyUsername: onlyUsername);
    } catch (_) {
      // Keep the app usable when backend polling or realtime temporarily fails.
    }
  }

  Future<void> _waitForPeerConnection(
    String username, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final session = brain?.getSession(username);
      if (session?.state == SessionState.connected) {
        return;
      }
      if (session?.state == SessionState.failed) {
        final detail = session?.error ?? session?.detail;
        throw StateError(
          detail == null || detail.isEmpty
              ? 'Could not connect to @$username.'
              : 'Could not connect to @$username. $detail',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final session = brain?.getSession(username);
    if (session?.state == SessionState.connected) {
      return;
    }
    try {
      await brain?.disconnect(username);
    } catch (_) {}
    throw StateError(
      'Connection to @$username timed out. Ask them to keep Rain open; in manual mode both users must press Connect.',
    );
  }

  Future<void> _syncRelationships({String? onlyUsername}) async {
    final existingFriends = await _localMutations.run(friendStore.loadFriends);
    final existingByUsername = <String, FriendRecord>{
      for (final friend in existingFriends) friend.username: friend,
    };
    final acceptedFriends = await adapter.loadAcceptedFriends(
      selfIdentity.username,
    );
    final incomingRequests = await adapter.loadIncomingFriendRequests(
      selfIdentity.username,
    );
    final outgoingRequests = await adapter.loadOutgoingFriendRequests(
      selfIdentity.username,
    );
    final blockedByMe = await adapter.loadBlockedUsers(selfIdentity.username);
    final blockedMe = await adapter.loadUsersBlocking(selfIdentity.username);

    final incomingSet = incomingRequests.toSet();
    final outgoingSet = outgoingRequests.toSet();
    final acceptedSet = acceptedFriends.toSet();
    final blockedByMeSet = blockedByMe.toSet();
    final blockedMeSet = blockedMe.toSet();

    final crossedRequests = incomingSet
        .intersection(outgoingSet)
        .difference(blockedByMeSet)
        .difference(blockedMeSet);
    for (final username in crossedRequests) {
      await adapter.upsertFriendship(selfIdentity.username, username);
      acceptedSet.add(username);
      incomingSet.remove(username);
      outgoingSet.remove(username);
    }

    final usernames = <String>{
      ...acceptedSet,
      ...incomingSet,
      ...outgoingSet,
      ...blockedByMeSet,
      ...blockedMeSet,
      ...existingByUsername.keys,
    };

    for (final username in usernames) {
      if (onlyUsername != null && username != onlyUsername) {
        continue;
      }

      final existing = existingByUsername[username];
      final locallyBlockedByMe = existing?.state == FriendState.blocked;
      final unblocking = _unblockingPeers.contains(username);
      if (locallyBlockedByMe &&
          !blockedByMeSet.contains(username) &&
          !unblocking) {
        await adapter.blockUser(selfIdentity.username, username);
        blockedByMeSet.add(username);
        incomingSet.remove(username);
        outgoingSet.remove(username);
        acceptedSet.remove(username);
      }

      if (blockedByMeSet.contains(username) ||
          (locallyBlockedByMe && !unblocking)) {
        await _clearFriendRequests(username);
        await adapter.deleteFriendship(selfIdentity.username, username);
        await _localMutations.run(() => friendStore.block(username));
        await _stopTrackingPeer(username);
        continue;
      }

      if (blockedMeSet.contains(username)) {
        await _clearFriendRequests(username);
        await adapter.deleteFriendship(selfIdentity.username, username);
        await _localMutations.run(
          () => friendStore.markBlockedByPeer(username),
        );
        await _stopTrackingPeer(username);
        continue;
      }

      final nextState = acceptedSet.contains(username)
          ? FriendState.friend
          : incomingSet.contains(username)
          ? FriendState.pendingIncoming
          : outgoingSet.contains(username)
          ? FriendState.pendingOutgoing
          : null;

      if (nextState == null) {
        if (existing != null && !_isBlockedState(existing.state)) {
          await _localMutations.run(() => friendStore.reject(username));
          await _stopTrackingPeer(username);
        } else if (existing?.state == FriendState.blockedByPeer) {
          await _localMutations.run(() => friendStore.reject(username));
        }
        continue;
      }

      final backendIdentity = await adapter.fetchIdentity(username);
      final backendDisplayName = backendIdentity?.displayName.trim() ?? '';
      final fallbackDisplayName = backendDisplayName.isNotEmpty
          ? backendDisplayName
          : username;
      final displayName =
          backendDisplayName.isNotEmpty && backendDisplayName != username
          ? backendDisplayName
          : (existing?.displayName ?? fallbackDisplayName);
      final gender =
          _backendGender(backendIdentity?.gender) ?? existing?.gender;

      if (nextState == FriendState.friend) {
        await _localMutations.run(
          () => friendStore.upsertFriend(
            username: username,
            displayName: displayName,
            state: FriendState.friend,
            addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
            gender: gender,
          ),
        );
        _watchPresence(username);
        continue;
      }

      await _localMutations.run(
        () => friendStore.upsertFriend(
          username: username,
          displayName: displayName,
          state: nextState,
          addedAt: existing?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
          gender: gender,
        ),
      );
      _watchPresence(username);
    }
  }

  Future<void> _stopTrackingPeer(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await _failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer link closed.',
    );
    await _presenceSubscriptions.remove(normalizedUsername)?.cancel();
    _manualDisconnectedPeers.remove(normalizedUsername);
    await brain?.disconnect(normalizedUsername);
    await brain?.unregisterPeer(normalizedUsername);
  }

  bool _isBlockedState(FriendState? state) {
    return state == FriendState.blocked || state == FriendState.blockedByPeer;
  }
}

class _OutgoingFileSource {
  const _OutgoingFileSource({required this.openRead, this.localPath});

  final Stream<List<int>> Function() openRead;
  final String? localPath;
}

class _ReceivePaths {
  const _ReceivePaths({required this.finalPath, required this.tempPath});

  final String finalPath;
  final String tempPath;
}
