import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'rain_runtime_controller.dart';
import 'runtime_interaction_guard.dart';

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
        sendFileControlIfConnected(
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
      // Prefer the modern atomic packet path (magic + header + payload) so a
      // legacy pending header cannot hijack a valid packet. See C-01.
      final packet = FileTransferChunkPacket.tryParse(binary);
      if (packet != null) {
        await _handleFileChunkPacket(peerId, packet.frame, packet.payload);
        return;
      }
      if (pendingFileChunks.containsKey(peerId)) {
        await _handleFileChunkBytes(peerId, binary);
        return;
      }
      // No pending header and not a packet — treat as legacy raw payload if
      // a pending header exists for another reason, otherwise drop.
      await _handleFileChunkBytes(peerId, binary);
    }
  }

  Future<void> enqueueFileChannelMessage(
    String peerId,
    SessionMessage message,
  ) {
    final previous = fileMessageQueues[peerId] ?? Future<void>.value();
    late final Future<void> queued;
    queued = previous
        .catchError((Object error, StackTrace stackTrace) {})
        .then((_) => _handleFileChannelMessage(peerId, message))
        .catchError((Object error, StackTrace stackTrace) async {
          await failActiveTransfersForPeer(peerId, _formatTransferError(error));
        });
    fileMessageQueues[peerId] = queued;
    unawaited(
      queued.whenComplete(() {
        if (identical(fileMessageQueues[peerId], queued)) {
          fileMessageQueues.remove(peerId);
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
        // Legacy split-header path: header (text) + next binary = payload.
        // Guard against overwrite — if a header is already pending for this
        // peer, the previous chunk's payload never arrived. Fail that transfer
        // instead of silently overwriting (C-01).
        final existingPending = pendingFileChunks[peerId];
        if (existingPending != null &&
            existingPending.transferId != frame.transferId) {
          await markTransferFailed(
            existingPending.transferId,
            'Received file chunk header out of order.',
          );
          sendFileControlIfConnected(
            peerId,
            FileTransferFrame.fail(
              existingPending.transferId,
              'Received file chunk header out of order.',
            ),
          );
        } else if (existingPending != null) {
          // Same transferId overwrite → previous header lost.
          await markTransferFailed(
            existingPending.transferId,
            'Received file chunk header out of order.',
          );
        }
        pendingFileChunks[peerId] = frame;
        break;
      case FileTransferFrame.completeType:
        // If a legacy chunk header is still pending for this transfer, the
        // final payload never arrived — fail before handling complete.
        final pendingFrame = pendingFileChunks[peerId];
        if (pendingFrame != null &&
            pendingFrame.transferId == frame.transferId) {
          pendingFileChunks.remove(peerId);
          await markTransferFailed(
            frame.transferId,
            'Received file chunk payload was missing.',
          );
          sendFileControlIfConnected(
            peerId,
            FileTransferFrame.fail(
              frame.transferId,
              'Received file chunk payload was missing.',
            ),
          );
          return;
        }
        // Clear any unrelated pending header for this peer before completing.
        if (pendingFrame != null) {
          pendingFileChunks.remove(peerId);
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
      sendFileControlIfConnected(
        peerId,
        FileTransferFrame.reject(frame.transferId, 'Malformed file offer.'),
      );
      return;
    }

    final existing = await fileTransferStore.loadById(frame.transferId);
    if (existing != null) {
      return;
    }

    final friend = await localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      sendFileControlIfConnected(
        peerId,
        FileTransferFrame.reject(
          frame.transferId,
          'Only friends can send files.',
        ),
      );
      return;
    }
    if (fileSize > maxFileTransferBytes) {
      sendFileControlIfConnected(
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
      voiceCallState: voiceCallState,
    );
    if (!transferDecision.allowed) {
      sendFileControlIfConnected(
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
      sendFileControlIfConnected(
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

    await localMutations.run(() async {
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
    final frame = pendingFileChunks.remove(peerId);
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
        receiveProgressOffsets[transfer.id] ?? transfer.bytesTransferred;
    if (frame.offset != expectedOffset ||
        frame.byteCount != bytes.lengthInBytes ||
        transfer.tempPath == null) {
      await markTransferFailed(transfer.id, 'Received an invalid file chunk.');
      sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(transfer.id, 'Received an invalid file chunk.'),
      );
      return;
    }
    if (expectedOffset + bytes.lengthInBytes > transfer.fileSize) {
      await markTransferFailed(
        transfer.id,
        'Received file exceeded the offer size.',
      );
      sendFileControlIfConnected(
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
      recordRuntimeEvent(
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
      await markTransferFailed(transfer.id, reason);
      sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(transfer.id, reason),
      );
      return;
    }
    final nextOffset = expectedOffset + bytes.lengthInBytes;
    receiveProgressOffsets[transfer.id] = nextOffset;
    await fileProgressBatcher.record(transfer.id, nextOffset);
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
      await markTransferFailed(
        transfer.id,
        'Received file did not match the offer.',
      );
      sendFileControlIfConnected(
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
      recordRuntimeEvent(
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
      await markTransferFailed(transfer.id, reason);
      sendFileControlIfConnected(
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
          await markTransferFailed(
            transfer.id,
            'Received file did not match the offer.',
          );
          sendFileControlIfConnected(
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
        sendFileControlIfConnected(
          peerId,
          FileTransferFrame.received(
            transferId: transfer.id,
            finalByteCount: 0,
            sha256: emptyHash,
          ),
        );
        clearTransferRuntimeState(transfer.id);
        return;
      }
      await markTransferFailed(transfer.id, 'Received file is missing.');
      sendFileControlIfConnected(
        peerId,
        FileTransferFrame.fail(transfer.id, 'Received file is missing.'),
      );
      return;
    }
    final actualBytes = await tempFile.length();
    if (actualBytes != transfer.fileSize) {
      await markTransferFailed(
        transfer.id,
        'Received file size did not match the offer.',
      );
      sendFileControlIfConnected(
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
      await markTransferFailed(
        transfer.id,
        'Received file did not match the offer.',
      );
      sendFileControlIfConnected(
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
    clearTransferRuntimeState(transfer.id);
    sendFileControlIfConnected(
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
    final expectedHash = outgoingFileHashes[frame.transferId];
    if (frame.finalByteCount != transfer.fileSize ||
        frame.sha256 == null ||
        frame.sha256!.isEmpty ||
        (expectedHash != null && frame.sha256 != expectedHash)) {
      await markTransferFailed(
        frame.transferId,
        'Receiver reported incomplete file.',
      );
      return;
    }
    outgoingFileSources.remove(frame.transferId);
    outgoingFileHashes.remove(frame.transferId);
    canceledTransfers.remove(frame.transferId);
    await localMutations.run(() async {
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
    clearTransferRuntimeState(frame.transferId);
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
    outgoingFileSources.remove(transferId);
    canceledTransfers.add(transferId);
    clearTransferRuntimeState(transferId);
    await deleteTempFile(transfer);
    await localMutations.run(() async {
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
    final source = outgoingFileSources[transferId];
    if (source == null && transfer.localPath == null) {
      await markTransferFailed(
        transferId,
        'Original file is no longer available.',
      );
      return;
    }

    try {
      final initialPeerId = transfer.peerId;
      final initialMessageId = transfer.messageId;
      await ensureFileChannelReady(initialPeerId);
      final startedSending = await localMutations.run(() async {
        if (canceledTransfers.contains(transferId)) {
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
      if (!startedSending || canceledTransfers.contains(transferId)) {
        return;
      }
      transfer = await fileTransferStore.loadById(transferId);
      if (transfer == null ||
          canceledTransfers.contains(transferId) ||
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
      if (canceledTransfers.contains(transferId)) {
        return;
      }
      if (offset != fileSize) {
        throw StateError('File changed while sending.');
      }
      hashInput.close();
      final digest = hashOutput.value.toString();
      outgoingFileHashes[transferId] = digest;
      await fileProgressBatcher.flush(transferId, offset);
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
          canceledTransfers.contains(transferId) ||
          _isTerminalTransferState(latestBeforeFail.state)) {
        return;
      }
      final reason = _formatTransferError(error);
      await markTransferFailed(transferId, reason);
      final latest = await fileTransferStore.loadById(transferId);
      if (latest != null) {
        sendFileControlIfConnected(
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
    if (canceledTransfers.contains(transferId)) {
      throw StateError('Transfer canceled.');
    }
    if (connectedSession(peerId) == null) {
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
    await fileProgressBatcher.record(transferId, offset + chunk.lengthInBytes);
  }

  Future<void> _waitForFileBuffer(
    String peerId, {
    required String transferId,
    required int nextByteCount,
  }) async {
    // C-06: use monotonic Stopwatch, not DateTime, so NTP/clock jumps
    // and suspend/resume do not cause spurious timeout or hang.
    final stopwatch = Stopwatch()..start();
    final startedAt = DateTime.now();
    var waiting = false;
    var samples = 0;
    while (stopwatch.elapsed < fileTransferBufferTimeout) {
      if (connectedSession(peerId) == null) {
        throw StateError('Peer disconnected.');
      }
      final buffered = await brain!.bufferedAmount(peerId, SessionChannel.file);
      samples += 1;
      if (buffered <= fileTransferHighWatermarkBytes) {
        if (waiting) {
          recordRuntimeEvent(
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
        recordRuntimeEvent(
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
      while (stopwatch.elapsed < fileTransferBufferTimeout) {
        if (connectedSession(peerId) == null) {
          throw StateError('Peer disconnected.');
        }
        final drained = await brain!.bufferedAmount(
          peerId,
          SessionChannel.file,
        );
        samples += 1;
        if (drained <= fileTransferLowWatermarkBytes) {
          recordRuntimeEvent(
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
    recordRuntimeEvent(
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
    final existing = receiveFileSinks[transfer.id];
    if (existing != null && receiveFileSinkPaths[transfer.id] == tempPath) {
      return existing;
    }
    if (existing != null) {
      await _closeReceiveSink(transfer.id, reason: 'path_changed');
    }

    final tempFile = File(tempPath);
    await tempFile.parent.create(recursive: true);
    final sink = tempFile.openWrite(mode: FileMode.append);
    receiveFileSinks[transfer.id] = sink;
    receiveFileSinkPaths[transfer.id] = tempPath;
    recordRuntimeEvent(
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
    final sink = receiveFileSinks.remove(transferId);
    receiveFileSinkPaths.remove(transferId);
    if (sink == null) {
      return;
    }
    await sink.close();
    recordRuntimeEvent(
      category: 'file_transfer',
      name: 'receive_sink_closed',
      context: <String, Object?>{'transferId': transferId, 'reason': reason},
    );
  }

  Future<void> closeAllReceiveSinks({required String reason}) async {
    final transferIds = receiveFileSinks.keys.toList(growable: false);
    for (final transferId in transferIds) {
      try {
        await _closeReceiveSink(transferId, reason: reason);
      } catch (error, stackTrace) {
        recordRuntimeEvent(
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

  void clearTransferRuntimeState(String transferId) {
    receiveProgressOffsets.remove(transferId);
    outgoingFileHashes.remove(transferId);
    fileProgressBatcher.clear(transferId);
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

  Future<void> assertCanTransferFile(String peerId) async {
    var friend = await localMutations.run(() => friendStore.loadFriend(peerId));
    if (friend?.state != FriendState.friend) {
      await syncRelationships(onlyUsername: peerId);
      friend = await localMutations.run(() => friendStore.loadFriend(peerId));
    }
    if (friend?.state != FriendState.friend) {
      throw StateError('Only friends can exchange files.');
    }
  }

  Session? connectedSession(String peerId) {
    final session = brain?.getSession(peerId);
    return session?.state == SessionState.connected ? session : null;
  }

  Future<void> ensureFileChannelReady(String peerId) async {
    if (brain == null) {
      throw StateError('Peer connection is unavailable right now.');
    }
    if (connectedSession(peerId) == null) {
      throw StateError('Connect first.');
    }
    await brain!.openChannel(peerId, SessionChannel.file);
    final sw = Stopwatch()..start();
    const openTimeout = Duration(seconds: 5);
    while (sw.elapsed < openTimeout) {
      if (connectedSession(peerId) == null) {
        throw StateError('Connect first.');
      }
      if (brain!.isChannelOpen(peerId, SessionChannel.file)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('File channel did not open. Reconnect and try again.');
  }

  void sendFileControlIfConnected(String peerId, FileTransferFrame frame) {
    if (connectedSession(peerId) == null ||
        !(brain?.isChannelOpen(peerId, SessionChannel.file) ?? false)) {
      return;
    }
    try {
      brain!.send(peerId, SessionChannel.file, frame.encode());
    } catch (_) {
      // Best effort: terminal file controls should not crash the runtime.
    }
  }

  Future<void> markTransferFailed(String transferId, String reason) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      return;
    }
    if (_isTerminalTransferState(transfer.state)) {
      return;
    }
    outgoingFileSources.remove(transferId);
    canceledTransfers.add(transferId);
    clearTransferRuntimeState(transferId);
    await deleteTempFile(transfer);
    await localMutations.run(() async {
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

  Future<void> failActiveTransfersForPeer(String peerId, String reason) async {
    List<FileTransferRecord> active;
    try {
      active = await fileTransferStore.loadActiveTransfers(peerId: peerId);
    } catch (_) {
      return;
    }
    for (final transfer in active) {
      try {
        await markTransferFailed(transfer.id, reason);
      } catch (_) {
        // Transfer cleanup is best effort during shutdown and relationship churn.
      }
    }
    pendingFileChunks.remove(peerId);
  }

  Future<ReceivePaths> prepareReceivePaths(FileTransferRecord transfer) async {
    final documents = await documentsDirectoryProvider();
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
    return ReceivePaths(finalPath: candidate.path, tempPath: tempPath);
  }

  Future<void> deleteTempFile(FileTransferRecord transfer) async {
    try {
      await _closeReceiveSink(transfer.id, reason: 'cleanup');
    } catch (error, stackTrace) {
      recordRuntimeEvent(
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
      recordRuntimeEvent(
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

class OutgoingFileSource {
  const OutgoingFileSource({required this.openRead, this.localPath});

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

class ReceivePaths {
  const ReceivePaths({required this.finalPath, required this.tempPath});

  final String finalPath;
  final String tempPath;
}
