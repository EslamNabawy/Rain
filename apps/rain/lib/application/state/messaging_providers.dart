import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'core_providers.dart';
import 'file_transfer_view.dart';
import 'runtime_providers.dart';

final messagesProvider =
    AsyncNotifierProvider.family<
      MessagesController,
      List<StoredMessage>,
      String
    >(MessagesController.new);

class MessagesController extends AsyncNotifier<List<StoredMessage>> {
  MessagesController(this._peerId);

  final String _peerId;
  StreamSubscription<List<StoredMessage>>? _subscription;

  @override
  Future<List<StoredMessage>> build() {
    final completer = Completer<List<StoredMessage>>();
    var completed = false;
    _subscription = ref
        .watch(messageStoreProvider)
        .watchConversation(_peerId)
        .listen(
          (List<StoredMessage> messages) {
            state = AsyncValue.data(messages);
            if (!completed) {
              completed = true;
              completer.complete(messages);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
            if (!completed) {
              completed = true;
              completer.completeError(error, stackTrace);
            }
          },
        );
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return completer.future;
  }

  Future<void> markRead() async {
    await _runtime().markConversationRead(_peerId);
  }

  Future<void> resend(String messageId) async {
    assertNetworkReady(ref);
    await _runtime().resendMessage(messageId);
  }

  Future<void> send(String content) async {
    assertNetworkReady(ref);
    await _runtime().sendMessage(_peerId, content);
  }

  Future<void> sendFile({
    required String fileName,
    required int fileSize,
    required Stream<List<int>> Function() openRead,
    String? localPath,
    String? mimeType,
  }) async {
    assertNetworkReady(ref);
    await _runtime().sendFile(
      peerId: _peerId,
      fileName: fileName,
      fileSize: fileSize,
      openRead: openRead,
      localPath: localPath,
      mimeType: mimeType,
    );
  }

  RainRuntimeController _runtime() {
    final runtime = ref.read(runtimeControllerProvider).value;
    if (runtime == null) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }
}

final fileTransfersProvider =
    AsyncNotifierProvider.family<
      FileTransfersController,
      List<FileTransferRecord>,
      String
    >(FileTransfersController.new);

class FileTransfersController extends AsyncNotifier<List<FileTransferRecord>> {
  FileTransfersController(this._peerId);

  final String _peerId;
  StreamSubscription<List<FileTransferRecord>>? _subscription;

  @override
  Future<List<FileTransferRecord>> build() {
    final completer = Completer<List<FileTransferRecord>>();
    var completed = false;
    _subscription = ref
        .watch(fileTransferStoreProvider)
        .watchPeerTransfers(_peerId)
        .listen(
          (List<FileTransferRecord> transfers) {
            state = AsyncValue.data(transfers);
            if (!completed) {
              completed = true;
              completer.complete(transfers);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            state = AsyncValue.error(error, stackTrace);
            if (!completed) {
              completed = true;
              completer.completeError(error, stackTrace);
            }
          },
        );
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    return completer.future;
  }

  Future<void> accept(String transferId) async {
    assertNetworkReady(ref);
    await _runtime().acceptFileTransfer(transferId);
  }

  Future<void> reject(String transferId) async {
    assertNetworkReady(ref);
    await _runtime().rejectFileTransfer(transferId);
  }

  Future<void> cancel(String transferId) async {
    assertNetworkReady(ref);
    await _runtime().cancelFileTransfer(transferId);
  }

  Future<void> retry(FileTransferRecord transfer) async {
    assertNetworkReady(ref);
    final localPath = transfer.localPath;
    if (transfer.direction != FileTransferDirection.outgoing ||
        localPath == null ||
        localPath.isEmpty) {
      throw StateError('Original file is no longer available.');
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('Original file is no longer available.');
    }
    await _runtime().sendFile(
      peerId: _peerId,
      fileName: transfer.fileName,
      fileSize: await file.length(),
      openRead: file.openRead,
      localPath: localPath,
      mimeType: transfer.mimeType,
    );
  }

  RainRuntimeController _runtime() {
    final runtime = ref.read(runtimeControllerProvider).value;
    if (runtime == null) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }
}

final fileTransferViewsProvider =
    NotifierProvider.family<
      FileTransferViewsController,
      AsyncValue<List<FileTransferView>>,
      String
    >(FileTransferViewsController.new);

class FileTransferViewsController
    extends Notifier<AsyncValue<List<FileTransferView>>> {
  FileTransferViewsController(this._peerId);

  final String _peerId;
  final FileTransferSpeedTracker _speedTracker = FileTransferSpeedTracker();

  @override
  AsyncValue<List<FileTransferView>> build() {
    final transfers = ref.watch(fileTransfersProvider(_peerId));
    return transfers.whenData(_speedTracker.apply);
  }
}
