import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/state/file_transfer_view.dart';
import 'package:rain/infrastructure/services/received_file_export_service.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileTransferSpeedTracker', () {
    test('calculates speed from transfer progress samples', () {
      var now = DateTime.fromMillisecondsSinceEpoch(1000);
      final tracker = FileTransferSpeedTracker(now: () => now);

      final initial = tracker.apply(<FileTransferRecord>[
        _transfer(bytesTransferred: 0, state: FileTransferState.sending),
      ]);
      expect(initial.single.speedBytesPerSecond, isNull);

      now = now.add(const Duration(seconds: 1));
      final updated = tracker.apply(<FileTransferRecord>[
        _transfer(bytesTransferred: 2048, state: FileTransferState.sending),
      ]);

      expect(updated.single.speedBytesPerSecond, 2048);
      expect(updated.single.eta, const Duration(seconds: 1));
    });

    test('clears speed samples when transfer reaches terminal state', () {
      var now = DateTime.fromMillisecondsSinceEpoch(1000);
      final tracker = FileTransferSpeedTracker(now: () => now);

      tracker.apply(<FileTransferRecord>[
        _transfer(bytesTransferred: 0, state: FileTransferState.receiving),
      ]);
      now = now.add(const Duration(seconds: 1));
      tracker.apply(<FileTransferRecord>[
        _transfer(bytesTransferred: 1024, state: FileTransferState.receiving),
      ]);

      final completed = tracker.apply(<FileTransferRecord>[
        _transfer(bytesTransferred: 4096, state: FileTransferState.completed),
      ]);
      expect(completed.single.speedBytesPerSecond, isNull);

      now = now.add(const Duration(seconds: 1));
      final restarted = tracker.apply(<FileTransferRecord>[
        _transfer(bytesTransferred: 2048, state: FileTransferState.receiving),
      ]);
      expect(restarted.single.speedBytesPerSecond, isNull);
    });
  });

  group('ReceivedFileExportService', () {
    test('rejects incomplete received files', () async {
      final service = ReceivedFileExportService(saveFilePicker: _neverPick);

      expect(
        () => service.saveReceivedFile(
          _transfer(
            direction: FileTransferDirection.incoming,
            state: FileTransferState.receiving,
            localPath: 'missing.bin',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects completed records whose local file is missing', () async {
      final service = ReceivedFileExportService(saveFilePicker: _neverPick);

      expect(
        () => service.saveReceivedFile(
          _transfer(
            direction: FileTransferDirection.incoming,
            state: FileTransferState.completed,
            localPath: 'missing.bin',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('copies completed received file to selected path', () async {
      final temp = await Directory.systemTemp.createTemp('rain-export-test-');
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });
      final source = File('${temp.path}${Platform.pathSeparator}source.txt');
      final destination = File(
        '${temp.path}${Platform.pathSeparator}saved.txt',
      );
      await source.writeAsString('rain-file');
      final service = ReceivedFileExportService(
        saveFilePicker:
            ({
              String? dialogTitle,
              String? fileName,
              String? initialDirectory,
              FileType type = FileType.any,
              List<String>? allowedExtensions,
              Uint8List? bytes,
              bool lockParentWindow = false,
            }) async => destination.path,
      );

      final result = await service.saveReceivedFile(
        _transfer(
          direction: FileTransferDirection.incoming,
          state: FileTransferState.completed,
          localPath: source.path,
          fileName: 'source.txt',
        ),
      );

      expect(result.saved, isTrue);
      expect(await destination.readAsString(), 'rain-file');
    });
  });
}

Future<String?> _neverPick({
  String? dialogTitle,
  String? fileName,
  String? initialDirectory,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  Uint8List? bytes,
  bool lockParentWindow = false,
}) async {
  fail('Save picker should not open for invalid transfers.');
}

FileTransferRecord _transfer({
  int bytesTransferred = 0,
  FileTransferState state = FileTransferState.offered,
  FileTransferDirection direction = FileTransferDirection.outgoing,
  String? localPath,
  String fileName = 'clip.bin',
}) {
  return FileTransferRecord(
    id: 'transfer-1',
    peerId: 'bob',
    messageId: 'message-1',
    direction: direction,
    fileName: fileName,
    fileSize: 4096,
    bytesTransferred: bytesTransferred,
    state: state,
    localPath: localPath,
    createdAt: 1,
    updatedAt: 1,
  );
}
