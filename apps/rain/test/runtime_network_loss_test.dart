import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
    );

    await runtime.handleNetworkLost(
      'Internet connection lost. Transfer canceled.',
    );

    final failed = await transferStore.loadById('transfer-1');
    expect(failed?.state, FileTransferState.failed);
    expect(failed?.error, 'Internet connection lost. Transfer canceled.');
    expect(await tempFile.exists(), isFalse);
  });
}
