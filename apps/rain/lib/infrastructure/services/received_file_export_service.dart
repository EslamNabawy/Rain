import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:rain_core/rain_core.dart';

class ReceivedFileExportResult {
  const ReceivedFileExportResult._({required this.saved});

  const ReceivedFileExportResult.saved() : this._(saved: true);
  const ReceivedFileExportResult.canceled() : this._(saved: false);

  final bool saved;
}

class ReceivedFileExportService {
  ReceivedFileExportService({
    MethodChannel? androidChannel,
    Future<String?> Function({
      String? dialogTitle,
      String? fileName,
      String? initialDirectory,
      FileType type,
      List<String>? allowedExtensions,
      Uint8List? bytes,
      bool lockParentWindow,
    })?
    saveFilePicker,
  }) : _androidChannel =
           androidChannel ?? const MethodChannel('rain/file_export'),
       _saveFilePicker = saveFilePicker ?? FilePicker.platform.saveFile;

  final MethodChannel _androidChannel;
  final Future<String?> Function({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow,
  })
  _saveFilePicker;

  Future<ReceivedFileExportResult> saveReceivedFile(
    FileTransferRecord transfer,
  ) async {
    final source = await _validatedSource(transfer);
    if (Platform.isAndroid) {
      return _saveOnAndroid(source, transfer);
    }
    return _saveOnFileSystem(source, transfer.fileName);
  }

  Future<File> _validatedSource(FileTransferRecord transfer) async {
    if (transfer.direction != FileTransferDirection.incoming ||
        transfer.state != FileTransferState.completed) {
      throw StateError('Only completed received files can be saved.');
    }
    final localPath = transfer.localPath;
    if (localPath == null || localPath.isEmpty) {
      throw StateError('Received file is not available.');
    }
    final file = File(localPath);
    if (!await file.exists()) {
      throw StateError('Received file is not available.');
    }
    return file;
  }

  Future<ReceivedFileExportResult> _saveOnAndroid(
    File source,
    FileTransferRecord transfer,
  ) async {
    try {
      final saved = await _androidChannel
          .invokeMethod<bool>('saveReceivedFile', <String, Object?>{
            'sourcePath': source.path,
            'fileName': transfer.fileName,
            'mimeType': transfer.mimeType ?? 'application/octet-stream',
          });
      return saved == true
          ? const ReceivedFileExportResult.saved()
          : const ReceivedFileExportResult.canceled();
    } on PlatformException catch (error) {
      throw StateError(
        error.message ?? 'Could not save file. Choose another location.',
      );
    }
  }

  Future<ReceivedFileExportResult> _saveOnFileSystem(
    File source,
    String fileName,
  ) async {
    final destinationPath = await _saveFilePicker(
      dialogTitle: 'Save received file',
      fileName: fileName,
      type: FileType.any,
      lockParentWindow: true,
    );
    if (destinationPath == null || destinationPath.isEmpty) {
      return const ReceivedFileExportResult.canceled();
    }

    final destination = File(destinationPath);
    if (destination.path == source.path) {
      return const ReceivedFileExportResult.saved();
    }
    await destination.parent.create(recursive: true);
    final sink = destination.openWrite();
    try {
      await source.openRead().pipe(sink);
    } on FileSystemException catch (_) {
      throw StateError('Could not save file. Choose another location.');
    } catch (_) {
      throw StateError('Could not save file. Choose another location.');
    }
    return const ReceivedFileExportResult.saved();
  }
}
