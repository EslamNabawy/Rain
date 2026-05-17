import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/file_transfer_progress_batcher.dart';

void main() {
  test(
    'batches fast progress writes and flushes final exact byte count',
    () async {
      var now = DateTime.fromMillisecondsSinceEpoch(1000);
      final writes = <int>[];
      final batcher = FileTransferProgressBatcher(
        now: () => now,
        markProgress: (_, bytesTransferred) async {
          writes.add(bytesTransferred);
        },
      );

      await batcher.record('transfer-1', 64 * 1024);
      expect(writes, <int>[64 * 1024]);

      now = now.add(const Duration(milliseconds: 100));
      await batcher.record('transfer-1', 256 * 1024);
      expect(writes, <int>[64 * 1024]);

      now = now.add(const Duration(milliseconds: 20));
      await batcher.record('transfer-1', 640 * 1024);
      expect(writes, <int>[64 * 1024, 640 * 1024]);

      now = now.add(const Duration(milliseconds: 20));
      await batcher.record('transfer-1', 700 * 1024);
      expect(writes, <int>[64 * 1024, 640 * 1024]);

      await batcher.flush('transfer-1', 700 * 1024);
      expect(writes, <int>[64 * 1024, 640 * 1024, 700 * 1024]);
    },
  );

  test('interval flush keeps slow transfers visibly moving', () async {
    var now = DateTime.fromMillisecondsSinceEpoch(1000);
    final writes = <int>[];
    final batcher = FileTransferProgressBatcher(
      now: () => now,
      markProgress: (_, bytesTransferred) async {
        writes.add(bytesTransferred);
      },
    );

    await batcher.record('transfer-1', 64 * 1024);
    now = now.add(const Duration(milliseconds: 300));
    await batcher.record('transfer-1', 96 * 1024);

    expect(writes, <int>[64 * 1024, 96 * 1024]);
  });
}
