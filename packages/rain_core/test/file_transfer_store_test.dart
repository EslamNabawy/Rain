import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  late RainDatabase database;
  late FileTransferStore store;

  setUp(() {
    database = RainDatabase(NativeDatabase.memory());
    store = FileTransferStore(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('stores and updates file transfer progress', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.upsert(
      FileTransferRecord(
        id: 'transfer-1',
        peerId: 'alice',
        messageId: 'message-1',
        direction: FileTransferDirection.outgoing,
        fileName: 'clip.mp4',
        fileSize: 100,
        localPath: 'C:\\tmp\\clip.mp4',
        bytesTransferred: 0,
        state: FileTransferState.offered,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await store.markState('transfer-1', FileTransferState.sending);
    await store.markProgress('transfer-1', 50);

    final transfer = await store.loadById('transfer-1');

    expect(transfer, isNotNull);
    expect(transfer!.state, FileTransferState.sending);
    expect(transfer.bytesTransferred, 50);
    expect(transfer.progress, 0.5);
    expect(await store.hasActiveTransferForPeer('alice'), isTrue);
  });

  test('terminal states are not active', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await store.upsert(
      FileTransferRecord(
        id: 'transfer-1',
        peerId: 'alice',
        messageId: 'message-1',
        direction: FileTransferDirection.incoming,
        fileName: 'clip.mp4',
        fileSize: 100,
        bytesTransferred: 20,
        state: FileTransferState.receiving,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await store.markState(
      'transfer-1',
      FileTransferState.failed,
      error: 'Disconnected.',
    );

    final transfer = await store.loadById('transfer-1');

    expect(transfer!.isActive, isFalse);
    expect(transfer.error, 'Disconnected.');
    expect(await store.hasActiveTransferForPeer('alice'), isFalse);
  });
}
