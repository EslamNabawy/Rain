part of 'rain_runtime_controller.dart';

extension FileTransferRuntime on RainRuntimeController {
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
      if (_pendingFileChunks.containsKey(peerId)) {
        await _handleFileChunkBytes(peerId, binary);
        return;
      }
      final packet = FileTransferChunkPacket.tryParse(binary);
      if (packet != null) {
        await _handleFileChunkPacket(peerId, packet.frame, packet.payload);
        return;
      }
      await _handleFileChunkBytes(peerId, binary);
    }
  }

  Future<void> _enqueueFileChannelMessage(
    String peerId,
    SessionMessage message,
  ) {
    final previous = _fileMessageQueues[peerId] ?? Future<void>.value();
    late final Future<void> queued;
    queued = previous
        .catchError((Object error, StackTrace stackTrace) {})
        .then((_) => _handleFileChannelMessage(peerId, message))
        .catchError((Object error, StackTrace stackTrace) async {
          await _failActiveTransfersForPeer(
            peerId,
            _formatTransferError(error),
          );
        });
    _fileMessageQueues[peerId] = queued;
    unawaited(
      queued.whenComplete(() {
        if (identical(_fileMessageQueues[peerId], queued)) {
          _fileMessageQueues.remove(peerId);
        }
      }),
    );
    return queued;
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
        final pendingFrame = _pendingFileChunks.remove(peerId);
        if (pendingFrame?.transferId == frame.transferId) {
          await _markTransferFailed(
            frame.transferId,
            'Received file chunk payload was missing.',
          );
          _sendFileControlIfConnected(
            peerId,
            FileTransferFrame.fail(
              frame.transferId,
              'Received file chunk payload was missing.',
            ),
          );
          return;
        }
        await _handleFileComplete(peerId, frame);
        break;
      case FileTransferFrame.receivedType:
        await _handleFileReceived(frame);
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
    final transferDecision = RuntimeInteractionGuard.canAcceptFileTransfer(
      peerId: peerId,
      transferId: frame.transferId,
      voiceCallState: _voiceCallState,
    );
    if (!transferDecision.allowed) {
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.reject(
          frame.transferId,
          transferDecision.userMessage ??
              'Finish the call before sending files.',
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
    await _handleFileChunkPacket(peerId, frame, bytes);
  }

  Future<void> _handleFileChunkPacket(
    String peerId,
    FileTransferFrame frame,
    Uint8List bytes,
  ) async {
    final transfer = await fileTransferStore.loadById(frame.transferId);
    if (transfer == null ||
        transfer.peerId != peerId ||
        transfer.direction != FileTransferDirection.incoming ||
        transfer.state != FileTransferState.receiving) {
      return;
    }
    final expectedOffset =
        _receiveProgressOffsets[transfer.id] ?? transfer.bytesTransferred;
    if (frame.offset != expectedOffset ||
        frame.byteCount != bytes.lengthInBytes ||
        transfer.tempPath == null) {
      await _markTransferFailed(transfer.id, 'Received an invalid file chunk.');
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(transfer.id, 'Received an invalid file chunk.'),
      );
      return;
    }
    if (expectedOffset + bytes.lengthInBytes > transfer.fileSize) {
      await _markTransferFailed(
        transfer.id,
        'Received file exceeded the offer size.',
      );
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(
          transfer.id,
          'Received file exceeded the offer size.',
        ),
      );
      return;
    }

    try {
      await _writeReceiveChunk(transfer, bytes);
    } catch (error) {
      const reason = 'Could not write received file chunk.';
      _recordRuntimeEvent(
        category: 'file_transfer',
        name: 'receive_chunk_write_failed',
        severity: 'warning',
        message: _formatTransferError(error),
        context: <String, Object?>{
          'peerId': peerId,
          'transferId': transfer.id,
          'byteCount': bytes.lengthInBytes,
          'offset': expectedOffset,
        },
      );
      await _markTransferFailed(transfer.id, reason);
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(transfer.id, reason),
      );
      return;
    }
    final nextOffset = expectedOffset + bytes.lengthInBytes;
    _receiveProgressOffsets[transfer.id] = nextOffset;
    await _fileProgressBatcher.record(transfer.id, nextOffset);
  }

  Future<void> _handleFileComplete(
    String peerId,
    FileTransferFrame frame,
  ) async {
    final transfer = await fileTransferStore.loadById(frame.transferId);
    if (transfer == null ||
        transfer.peerId != peerId ||
        transfer.direction != FileTransferDirection.incoming ||
        transfer.tempPath == null ||
        transfer.localPath == null) {
      return;
    }
    final expectedHash = frame.sha256;
    if (frame.finalByteCount != transfer.fileSize ||
        expectedHash == null ||
        expectedHash.isEmpty) {
      await _markTransferFailed(
        transfer.id,
        'Received file did not match the offer.',
      );
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(
          transfer.id,
          'Receiver reported incomplete file.',
        ),
      );
      return;
    }
    try {
      await _closeReceiveSink(transfer.id, reason: 'complete');
    } catch (error) {
      const reason = 'Could not finalize received file.';
      _recordRuntimeEvent(
        category: 'file_transfer',
        name: 'receive_sink_close_failed',
        severity: 'warning',
        message: _formatTransferError(error),
        context: <String, Object?>{
          'peerId': peerId,
          'transferId': transfer.id,
          'reason': 'complete',
        },
      );
      await _markTransferFailed(transfer.id, reason);
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(transfer.id, reason),
      );
      return;
    }
    final tempFile = File(transfer.tempPath!);
    if (!await tempFile.exists()) {
      if (transfer.fileSize == 0) {
        final emptyHash = sha256.convert(const <int>[]).toString();
        if (expectedHash != emptyHash) {
          await _markTransferFailed(
            transfer.id,
            'Received file did not match the offer.',
          );
          _sendFileControlIfConnected(
            peerId,
            FileTransferFrame.fail(
              transfer.id,
              'Receiver reported incomplete file.',
            ),
          );
          return;
        }
        final finalFile = File(transfer.localPath!);
        await finalFile.parent.create(recursive: true);
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await finalFile.create();
        await fileTransferStore.markState(
          transfer.id,
          FileTransferState.completed,
          bytesTransferred: 0,
          localPath: finalFile.path,
        );
        _sendFileControlIfConnected(
          peerId,
          FileTransferFrame.received(
            transferId: transfer.id,
            finalByteCount: 0,
            sha256: emptyHash,
          ),
        );
        _clearTransferRuntimeState(transfer.id);
        return;
      }
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
    final actualHash = await _sha256File(tempFile);
    if (actualHash != expectedHash) {
      await _markTransferFailed(
        transfer.id,
        'Received file did not match the offer.',
      );
      _sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(
          transfer.id,
          'Receiver reported incomplete file.',
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
    _clearTransferRuntimeState(transfer.id);
    _sendFileControlIfConnected(
      peerId,
      FileTransferFrame.received(
        transferId: transfer.id,
        finalByteCount: transfer.fileSize,
        sha256: actualHash,
      ),
    );
  }

  Future<void> _handleFileReceived(FileTransferFrame frame) async {
    final transfer = await fileTransferStore.loadById(frame.transferId);
    if (transfer == null ||
        transfer.direction != FileTransferDirection.outgoing) {
      return;
    }
    final expectedHash = _outgoingFileHashes[frame.transferId];
    if (frame.finalByteCount != transfer.fileSize ||
        frame.sha256 == null ||
        frame.sha256!.isEmpty ||
        (expectedHash != null && frame.sha256 != expectedHash)) {
      await _markTransferFailed(
        frame.transferId,
        'Receiver reported incomplete file.',
      );
      return;
    }
    _outgoingFileSources.remove(frame.transferId);
    _outgoingFileHashes.remove(frame.transferId);
    _canceledTransfers.remove(frame.transferId);
    await _localMutations.run(() async {
      await fileTransferStore.markState(
        frame.transferId,
        FileTransferState.completed,
        bytesTransferred: transfer.fileSize,
      );
      await messageStore.markMessageStatus(
        transfer.messageId,
        MessageStatus.delivered,
      );
    });
    _clearTransferRuntimeState(frame.transferId);
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
    if (_isTerminalTransferState(transfer.state)) {
      return;
    }
    _outgoingFileSources.remove(transferId);
    _canceledTransfers.add(transferId);
    _clearTransferRuntimeState(transferId);
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
      final startedSending = await _localMutations.run(() async {
        if (_canceledTransfers.contains(transferId)) {
          return false;
        }
        final markedSending = await fileTransferStore.markStateIfCurrent(
          transferId,
          const <FileTransferState>{FileTransferState.accepted},
          FileTransferState.sending,
          bytesTransferred: 0,
        );
        if (!markedSending) {
          return false;
        }
        await messageStore.markMessageStatus(
          initialMessageId,
          MessageStatus.sending,
        );
        return true;
      });
      if (!startedSending || _canceledTransfers.contains(transferId)) {
        return;
      }
      transfer = await fileTransferStore.loadById(transferId);
      if (transfer == null ||
          _canceledTransfers.contains(transferId) ||
          _isTerminalTransferState(transfer.state)) {
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
      final pending = Uint8List(fileTransferChunkBytes);
      var pendingLength = 0;
      final hashOutput = _DigestSink();
      final hashInput = sha256.startChunkedConversion(hashOutput);
      await for (final bytes in openRead()) {
        hashInput.add(bytes);
        final sourceBytes = bytes is Uint8List
            ? bytes
            : Uint8List.fromList(bytes);
        var cursor = 0;

        if (pendingLength > 0) {
          final needed = fileTransferChunkBytes - pendingLength;
          final available = sourceBytes.lengthInBytes;
          final copied = available < needed ? available : needed;
          pending.setRange(
            pendingLength,
            pendingLength + copied,
            sourceBytes,
            0,
          );
          pendingLength += copied;
          cursor += copied;
          if (pendingLength == fileTransferChunkBytes) {
            await _sendFileChunk(
              transferId,
              peerId,
              Uint8List.sublistView(pending, 0, pendingLength),
              index,
              offset,
            );
            offset += pendingLength;
            index += 1;
            pendingLength = 0;
          }
        }

        while (cursor + fileTransferChunkBytes <= sourceBytes.lengthInBytes) {
          final chunk = Uint8List.sublistView(
            sourceBytes,
            cursor,
            cursor + fileTransferChunkBytes,
          );
          await _sendFileChunk(transferId, peerId, chunk, index, offset);
          offset += chunk.lengthInBytes;
          index += 1;
          cursor += fileTransferChunkBytes;
        }

        if (cursor < sourceBytes.lengthInBytes) {
          pendingLength = sourceBytes.lengthInBytes - cursor;
          pending.setRange(0, pendingLength, sourceBytes, cursor);
        }
      }
      if (pendingLength > 0) {
        final chunk = Uint8List.sublistView(pending, 0, pendingLength);
        await _sendFileChunk(transferId, peerId, chunk, index, offset);
        offset += chunk.lengthInBytes;
      }
      if (_canceledTransfers.contains(transferId)) {
        return;
      }
      if (offset != fileSize) {
        throw StateError('File changed while sending.');
      }
      hashInput.close();
      final digest = hashOutput.value.toString();
      _outgoingFileHashes[transferId] = digest;
      await _fileProgressBatcher.flush(transferId, offset);
      brain!.send(
        peerId,
        SessionChannel.file,
        FileTransferFrame.complete(
          transferId: transferId,
          finalByteCount: offset,
          sha256: digest,
        ).encode(),
      );
      await messageStore.markMessageStatus(messageId, MessageStatus.pendingAck);
    } catch (error) {
      final latestBeforeFail = await fileTransferStore.loadById(transferId);
      if (latestBeforeFail == null ||
          _canceledTransfers.contains(transferId) ||
          _isTerminalTransferState(latestBeforeFail.state)) {
        return;
      }
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
    await _waitForFileBuffer(
      peerId,
      transferId: transferId,
      nextByteCount: offset + chunk.lengthInBytes,
    );
    brain!.send(
      peerId,
      SessionChannel.file,
      FileTransferChunkPacket(
        frame: FileTransferFrame.chunk(
          transferId: transferId,
          index: index,
          offset: offset,
          byteCount: chunk.lengthInBytes,
        ),
        payload: chunk,
      ).encode(),
    );
    await _fileProgressBatcher.record(transferId, offset + chunk.lengthInBytes);
  }

  Future<void> _waitForFileBuffer(
    String peerId, {
    required String transferId,
    required int nextByteCount,
  }) async {
    final startedAt = DateTime.now();
    final deadline = startedAt.add(fileTransferBufferTimeout);
    var waiting = false;
    var samples = 0;
    while (DateTime.now().isBefore(deadline)) {
      if (_connectedSession(peerId) == null) {
        throw StateError('Peer disconnected.');
      }
      final buffered = await brain!.bufferedAmount(peerId, SessionChannel.file);
      samples += 1;
      if (buffered <= fileTransferHighWatermarkBytes) {
        if (waiting) {
          _recordRuntimeEvent(
            category: 'file_transfer',
            name: 'send_backpressure_wait_completed',
            context: <String, Object?>{
              'peerId': peerId,
              'transferId': transferId,
              'bufferedAmountBytes': buffered,
              'highWatermarkBytes': fileTransferHighWatermarkBytes,
              'lowWatermarkBytes': fileTransferLowWatermarkBytes,
              'waitDurationMs': DateTime.now()
                  .difference(startedAt)
                  .inMilliseconds,
              'samples': samples,
              'nextByteCount': nextByteCount,
            },
          );
        }
        return;
      }
      if (!waiting) {
        waiting = true;
        _recordRuntimeEvent(
          category: 'file_transfer',
          name: 'send_backpressure_wait_started',
          severity: 'warning',
          context: <String, Object?>{
            'peerId': peerId,
            'transferId': transferId,
            'bufferedAmountBytes': buffered,
            'highWatermarkBytes': fileTransferHighWatermarkBytes,
            'lowWatermarkBytes': fileTransferLowWatermarkBytes,
            'timeoutMs': fileTransferBufferTimeout.inMilliseconds,
            'nextByteCount': nextByteCount,
          },
        );
      }
      await Future<void>.delayed(fileTransferBufferPollInterval);
      while (DateTime.now().isBefore(deadline)) {
        if (_connectedSession(peerId) == null) {
          throw StateError('Peer disconnected.');
        }
        final drained = await brain!.bufferedAmount(
          peerId,
          SessionChannel.file,
        );
        samples += 1;
        if (drained <= fileTransferLowWatermarkBytes) {
          _recordRuntimeEvent(
            category: 'file_transfer',
            name: 'send_backpressure_wait_completed',
            context: <String, Object?>{
              'peerId': peerId,
              'transferId': transferId,
              'bufferedAmountBytes': drained,
              'highWatermarkBytes': fileTransferHighWatermarkBytes,
              'lowWatermarkBytes': fileTransferLowWatermarkBytes,
              'waitDurationMs': DateTime.now()
                  .difference(startedAt)
                  .inMilliseconds,
              'samples': samples,
              'nextByteCount': nextByteCount,
            },
          );
          return;
        }
        await Future<void>.delayed(fileTransferBufferPollInterval);
      }
    }
    _recordRuntimeEvent(
      category: 'file_transfer',
      name: 'send_backpressure_timeout',
      severity: 'warning',
      context: <String, Object?>{
        'peerId': peerId,
        'transferId': transferId,
        'highWatermarkBytes': fileTransferHighWatermarkBytes,
        'lowWatermarkBytes': fileTransferLowWatermarkBytes,
        'timeoutMs': fileTransferBufferTimeout.inMilliseconds,
        'samples': samples,
        'nextByteCount': nextByteCount,
      },
    );
    throw StateError('File channel is congested. Try again.');
  }

  Future<String> _sha256File(File file) async {
    final output = _DigestSink();
    final input = sha256.startChunkedConversion(output);
    try {
      await for (final chunk in file.openRead()) {
        input.add(chunk);
      }
    } finally {
      input.close();
    }
    return output.value.toString();
  }

  Future<void> _writeReceiveChunk(
    FileTransferRecord transfer,
    Uint8List bytes,
  ) async {
    final sink = await _receiveSinkFor(transfer);
    sink.add(bytes);
    await sink.flush();
  }

  Future<IOSink> _receiveSinkFor(FileTransferRecord transfer) async {
    final tempPath = transfer.tempPath;
    if (tempPath == null || tempPath.isEmpty) {
      throw StateError('Transfer temp path is missing.');
    }
    final existing = _receiveFileSinks[transfer.id];
    if (existing != null && _receiveFileSinkPaths[transfer.id] == tempPath) {
      return existing;
    }
    if (existing != null) {
      await _closeReceiveSink(transfer.id, reason: 'path_changed');
    }

    final tempFile = File(tempPath);
    await tempFile.parent.create(recursive: true);
    final sink = tempFile.openWrite(mode: FileMode.append);
    _receiveFileSinks[transfer.id] = sink;
    _receiveFileSinkPaths[transfer.id] = tempPath;
    _recordRuntimeEvent(
      category: 'file_transfer',
      name: 'receive_sink_opened',
      context: <String, Object?>{
        'peerId': transfer.peerId,
        'transferId': transfer.id,
        'bytesTransferred': transfer.bytesTransferred,
      },
    );
    return sink;
  }

  Future<void> _closeReceiveSink(
    String transferId, {
    required String reason,
  }) async {
    final sink = _receiveFileSinks.remove(transferId);
    _receiveFileSinkPaths.remove(transferId);
    if (sink == null) {
      return;
    }
    await sink.close();
    _recordRuntimeEvent(
      category: 'file_transfer',
      name: 'receive_sink_closed',
      context: <String, Object?>{'transferId': transferId, 'reason': reason},
    );
  }

  Future<void> _closeAllReceiveSinks({required String reason}) async {
    final transferIds = _receiveFileSinks.keys.toList(growable: false);
    for (final transferId in transferIds) {
      try {
        await _closeReceiveSink(transferId, reason: reason);
      } catch (error, stackTrace) {
        _recordRuntimeEvent(
          category: 'file_transfer',
          name: 'receive_sink_close_failed',
          severity: 'warning',
          message: _formatTransferError(error),
          context: <String, Object?>{
            'transferId': transferId,
            'reason': reason,
          },
        );
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'file-transfer-sink-close',
          fatal: false,
        );
      }
    }
  }

  void _clearTransferRuntimeState(String transferId) {
    _receiveProgressOffsets.remove(transferId);
    _outgoingFileHashes.remove(transferId);
    _fileProgressBatcher.clear(transferId);
  }

  bool _isTerminalTransferState(FileTransferState state) {
    return switch (state) {
      FileTransferState.completed ||
      FileTransferState.canceled ||
      FileTransferState.failed ||
      FileTransferState.rejected => true,
      FileTransferState.offered ||
      FileTransferState.accepted ||
      FileTransferState.sending ||
      FileTransferState.receiving => false,
    };
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
    if (_isTerminalTransferState(transfer.state)) {
      return;
    }
    _outgoingFileSources.remove(transferId);
    _canceledTransfers.add(transferId);
    _clearTransferRuntimeState(transferId);
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
    final documents = await _documentsDirectoryProvider();
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
    try {
      await _closeReceiveSink(transfer.id, reason: 'cleanup');
    } catch (error, stackTrace) {
      _recordRuntimeEvent(
        category: 'file_transfer',
        name: 'receive_sink_close_failed',
        severity: 'warning',
        message: _formatTransferError(error),
        context: <String, Object?>{
          'peerId': transfer.peerId,
          'transferId': transfer.id,
          'reason': 'cleanup',
        },
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'file-transfer-temp-cleanup',
        fatal: false,
      );
    }
    final tempPath = transfer.tempPath;
    if (tempPath == null || tempPath.isEmpty) {
      return;
    }
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
      _recordRuntimeEvent(
        category: 'file_transfer',
        name: 'temp_file_deleted',
        context: <String, Object?>{
          'peerId': transfer.peerId,
          'transferId': transfer.id,
        },
      );
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
}

class _OutgoingFileSource {
  const _OutgoingFileSource({required this.openRead, this.localPath});

  final Stream<List<int>> Function() openRead;
  final String? localPath;
}

class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final digest = _value;
    if (digest == null) {
      throw StateError('Digest was not finalized.');
    }
    return digest;
  }

  @override
  void add(Digest data) {
    _value = data;
  }

  @override
  void close() {}
}

class _ReceivePaths {
  const _ReceivePaths({required this.finalPath, required this.tempPath});

  final String finalPath;
  final String tempPath;
}
