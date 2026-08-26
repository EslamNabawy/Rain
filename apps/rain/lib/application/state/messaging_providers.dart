/// # messaging_providers.dart
///
/// Riverpod providers for per-peer message lists. [MessagesController] watches
/// the message store for conversation tail updates, supports loading older
/// messages, and merges overlapping pages for efficient chat history display.
///
/// **Key types:** [MessagesController]
///
/// **Depends on:** rain_core, core providers, identity providers
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'core_providers.dart';
import 'file_transfer_view.dart';
import 'identity_providers.dart';
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
  List<StoredMessage> _olderMessages = const <StoredMessage>[];
  List<StoredMessage> _tailMessages = const <StoredMessage>[];
  bool _loadedOlderOnce = false;
  bool _hasOlderMessages = true;

  @override
  Future<List<StoredMessage>> build() async {
    final session = ref.watch(authenticatedSessionProvider);
    await _subscription?.cancel();
    _subscription = null;
    _olderMessages = const <StoredMessage>[];
    _tailMessages = const <StoredMessage>[];
    _loadedOlderOnce = false;
    _hasOlderMessages = true;
    if (session == null) {
      return const <StoredMessage>[];
    }
    final completer = Completer<List<StoredMessage>>();
    var completed = false;
    _subscription = ref
        .watch(messageStoreProvider)
        .watchConversationTail(_peerId)
        .listen(
          (List<StoredMessage> messages) {
            if (_loadedOlderOnce && _tailMessages.isNotEmpty) {
              _olderMessages = _mergeStoredMessages(<List<StoredMessage>>[
                _olderMessages,
                _messagesBefore(_tailMessages, messages),
              ]);
            }
            _tailMessages = messages;
            if (messages.length < defaultConversationPageSize) {
              _hasOlderMessages = false;
            }
            final merged = _currentMessages();
            state = AsyncValue.data(merged);
            if (!completed) {
              completed = true;
              completer.complete(merged);
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

  Future<void> loadOlder() async {
    if (!_hasOlderMessages) {
      return;
    }
    final current = _currentMessages();
    if (current.isEmpty) {
      _hasOlderMessages = false;
      return;
    }
    final older = await ref
        .read(messageStoreProvider)
        .loadConversationPage(
          _peerId,
          before: MessagePageCursor.fromMessage(current.first),
        );
    _loadedOlderOnce = true;
    if (older.isEmpty) {
      _hasOlderMessages = false;
      return;
    }
    if (older.length < defaultConversationPageSize) {
      _hasOlderMessages = false;
    }
    _olderMessages = _mergeStoredMessages(<List<StoredMessage>>[
      older,
      _olderMessages,
    ]);
    state = AsyncValue.data(_currentMessages());
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
    final session = ref.read(authenticatedSessionProvider);
    final runtime = ref.read(runtimeControllerProvider).value;
    if (runtime == null ||
        session == null ||
        runtime.selfIdentity.username != session.identity.username ||
        runtime.sessionGeneration != session.sessionGeneration) {
      throw StateError('Rain is still starting. Try again in a moment.');
    }
    return runtime;
  }

  List<StoredMessage> _currentMessages() {
    return _mergeStoredMessages(<List<StoredMessage>>[
      _olderMessages,
      _tailMessages,
    ]);
  }

  List<StoredMessage> _messagesBefore(
    List<StoredMessage> previousTail,
    List<StoredMessage> nextTail,
  ) {
    if (nextTail.isEmpty) {
      return previousTail;
    }
    final oldestNext = nextTail.first;
    return previousTail
        .where((message) => _compareMessages(message, oldestNext) < 0)
        .toList(growable: false);
  }

  List<StoredMessage> _mergeStoredMessages(List<List<StoredMessage>> groups) {
    final byId = <String, StoredMessage>{};
    for (final group in groups) {
      for (final message in group) {
        byId[message.id] = message;
      }
    }
    final messages = byId.values.toList(growable: false)
      ..sort(_compareMessages);
    return messages;
  }

  int _compareMessages(StoredMessage left, StoredMessage right) {
    final bySentAt = left.sentAt.compareTo(right.sentAt);
    if (bySentAt != 0) {
      return bySentAt;
    }
    final bySeq = left.seq.compareTo(right.seq);
    if (bySeq != 0) {
      return bySeq;
    }
    return left.id.compareTo(right.id);
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
  Future<List<FileTransferRecord>> build() async {
    final session = ref.watch(authenticatedSessionProvider);
    await _subscription?.cancel();
    _subscription = null;
    if (session == null) {
      return const <FileTransferRecord>[];
    }
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
    final session = ref.read(authenticatedSessionProvider);
    final runtime = ref.read(runtimeControllerProvider).value;
    if (runtime == null ||
        session == null ||
        runtime.selfIdentity.username != session.identity.username ||
        runtime.sessionGeneration != session.sessionGeneration) {
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
    final connection = ref.watch(
      connectionsProvider.select((state) => state.peer(_peerId)),
    );
    if (!connection.isConnected) {
      _speedTracker.reset();
    }
    final transfers = ref.watch(fileTransfersProvider(_peerId));
    return transfers.whenData(_speedTracker.apply);
  }
}
