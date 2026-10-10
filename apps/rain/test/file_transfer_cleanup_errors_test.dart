import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

class _ThrowingTransferStore extends FileTransferStore {
  _ThrowingTransferStore(super.database);

  @override
  Future<List<FileTransferRecord>> loadActiveTransfers({String? peerId}) {
    throw StateError('disk I/O error');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failActiveTransfersForPeer records a failed store read', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final events = <String>[];
    final errors = <Object>[];
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
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
      fileTransferStore: _ThrowingTransferStore(db),
      eventRecorder:
          ({
            required String category,
            required String name,
            String severity = 'info',
            String? message,
            Map<String, Object?> context = const <String, Object?>{},
          }) {
            events.add(name);
          },
      errorRecorder:
          (
            Object error,
            StackTrace? stackTrace, {
            required String source,
            required bool fatal,
            String? flutterLibrary,
            String? flutterContext,
          }) {
            errors.add(error);
          },
    );

    await runtime.failActiveTransfersForPeer('bob', 'Peer disconnected.');

    expect(events, contains('fail_active_transfers_load_failed'));
    expect(errors, hasLength(1));
  });
}
