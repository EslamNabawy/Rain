import 'package:drift/drift.dart';

import '../database/rain_database.dart';

enum FileTransferState {
  offered,
  accepted,
  sending,
  receiving,
  completed,
  canceled,
  failed,
  rejected,
}

enum FileTransferDirection { incoming, outgoing }

class FileTransferRecord {
  const FileTransferRecord({
    required this.id,
    required this.peerId,
    required this.messageId,
    required this.direction,
    required this.fileName,
    required this.fileSize,
    required this.bytesTransferred,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
    this.mimeType,
    this.localPath,
    this.tempPath,
    this.error,
  });

  final String id;
  final String peerId;
  final String messageId;
  final FileTransferDirection direction;
  final String fileName;
  final int fileSize;
  final int bytesTransferred;
  final FileTransferState state;
  final int createdAt;
  final int updatedAt;
  final String? mimeType;
  final String? localPath;
  final String? tempPath;
  final String? error;

  bool get isActive {
    return switch (state) {
      FileTransferState.offered ||
      FileTransferState.accepted ||
      FileTransferState.sending ||
      FileTransferState.receiving => true,
      FileTransferState.completed ||
      FileTransferState.canceled ||
      FileTransferState.failed ||
      FileTransferState.rejected => false,
    };
  }

  double get progress {
    if (fileSize <= 0) {
      return 0;
    }
    return (bytesTransferred / fileSize).clamp(0, 1).toDouble();
  }

  FileTransferRecord copyWith({
    int? bytesTransferred,
    FileTransferState? state,
    int? updatedAt,
    String? localPath,
    String? tempPath,
    String? error,
    bool clearError = false,
  }) {
    return FileTransferRecord(
      id: id,
      peerId: peerId,
      messageId: messageId,
      direction: direction,
      fileName: fileName,
      fileSize: fileSize,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      state: state ?? this.state,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mimeType: mimeType,
      localPath: localPath ?? this.localPath,
      tempPath: tempPath ?? this.tempPath,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class FileTransferStore {
  FileTransferStore(this._database);

  final RainDatabase _database;

  Stream<List<FileTransferRecord>> watchPeerTransfers(String peerId) {
    final query = _database.select(_database.fileTransfers)
      ..where((FileTransfers row) => row.peerId.equals(peerId))
      ..orderBy(<OrderingTerm Function(FileTransfers)>[
        (FileTransfers row) => OrderingTerm.asc(row.createdAt),
      ]);
    return query.watch().map(
      (List<FileTransfer> rows) => rows.map(_map).toList(growable: false),
    );
  }

  Future<List<FileTransferRecord>> loadPeerTransfers(String peerId) async {
    final query = _database.select(_database.fileTransfers)
      ..where((FileTransfers row) => row.peerId.equals(peerId))
      ..orderBy(<OrderingTerm Function(FileTransfers)>[
        (FileTransfers row) => OrderingTerm.asc(row.createdAt),
      ]);
    return (await query.get()).map(_map).toList(growable: false);
  }

  Future<FileTransferRecord?> loadById(String id) async {
    final query = _database.select(_database.fileTransfers)
      ..where((FileTransfers row) => row.id.equals(id))
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _map(row);
  }

  Future<FileTransferRecord?> loadByMessageId(String messageId) async {
    final query = _database.select(_database.fileTransfers)
      ..where((FileTransfers row) => row.messageId.equals(messageId))
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _map(row);
  }

  Future<List<FileTransferRecord>> loadActiveTransfers({String? peerId}) async {
    final activeStates = <String>[
      FileTransferState.offered.name,
      FileTransferState.accepted.name,
      FileTransferState.sending.name,
      FileTransferState.receiving.name,
    ];
    final query = _database.select(_database.fileTransfers)
      ..where((FileTransfers row) {
        final active = row.state.isIn(activeStates);
        if (peerId == null) {
          return active;
        }
        return active & row.peerId.equals(peerId);
      });
    return (await query.get()).map(_map).toList(growable: false);
  }

  Future<bool> hasActiveTransferForPeer(String peerId) async {
    return (await loadActiveTransfers(peerId: peerId)).isNotEmpty;
  }

  Future<void> upsert(FileTransferRecord record) {
    return _database.serializedTransaction(() async {
      await _database
          .into(_database.fileTransfers)
          .insertOnConflictUpdate(
            FileTransfersCompanion.insert(
              id: record.id,
              peerId: record.peerId,
              messageId: record.messageId,
              direction: record.direction.name,
              fileName: record.fileName,
              fileSize: record.fileSize,
              mimeType: Value<String?>(record.mimeType),
              localPath: Value<String?>(record.localPath),
              tempPath: Value<String?>(record.tempPath),
              bytesTransferred: Value<int>(record.bytesTransferred),
              state: record.state.name,
              error: Value<String?>(record.error),
              createdAt: record.createdAt,
              updatedAt: record.updatedAt,
            ),
          );
    });
  }

  Future<void> markState(
    String id,
    FileTransferState state, {
    String? error,
    int? bytesTransferred,
    String? localPath,
    String? tempPath,
  }) {
    return _database.serializedTransaction(() async {
      await (_database.update(
        _database.fileTransfers,
      )..where((FileTransfers row) => row.id.equals(id))).write(
        FileTransfersCompanion(
          state: Value<String>(state.name),
          error: Value<String?>(error),
          bytesTransferred: bytesTransferred == null
              ? const Value<int>.absent()
              : Value<int>(bytesTransferred),
          localPath: localPath == null
              ? const Value<String?>.absent()
              : Value<String?>(localPath),
          tempPath: tempPath == null
              ? const Value<String?>.absent()
              : Value<String?>(tempPath),
          updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    });
  }

  Future<bool> markStateIfCurrent(
    String id,
    Set<FileTransferState> currentStates,
    FileTransferState state, {
    String? error,
    int? bytesTransferred,
    String? localPath,
    String? tempPath,
  }) {
    final expectedStateNames = currentStates
        .map((FileTransferState state) => state.name)
        .toList(growable: false);
    return _database.serializedTransaction(() async {
      final updatedRows =
          await (_database.update(_database.fileTransfers)..where(
                (FileTransfers row) =>
                    row.id.equals(id) & row.state.isIn(expectedStateNames),
              ))
              .write(
                FileTransfersCompanion(
                  state: Value<String>(state.name),
                  error: Value<String?>(error),
                  bytesTransferred: bytesTransferred == null
                      ? const Value<int>.absent()
                      : Value<int>(bytesTransferred),
                  localPath: localPath == null
                      ? const Value<String?>.absent()
                      : Value<String?>(localPath),
                  tempPath: tempPath == null
                      ? const Value<String?>.absent()
                      : Value<String?>(tempPath),
                  updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
                ),
              );
      return updatedRows > 0;
    });
  }

  Future<void> markProgress(String id, int bytesTransferred) {
    return _database.serializedTransaction(() async {
      await (_database.update(
        _database.fileTransfers,
      )..where((FileTransfers row) => row.id.equals(id))).write(
        FileTransfersCompanion(
          bytesTransferred: Value<int>(bytesTransferred),
          updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    });
  }

  Future<void> failActiveForPeer(String peerId, String reason) async {
    final active = await loadActiveTransfers(peerId: peerId);
    for (final transfer in active) {
      await markState(transfer.id, FileTransferState.failed, error: reason);
    }
  }

  FileTransferRecord _map(FileTransfer row) {
    return FileTransferRecord(
      id: row.id,
      peerId: row.peerId,
      messageId: row.messageId,
      direction: FileTransferDirection.values.byName(row.direction),
      fileName: row.fileName,
      fileSize: row.fileSize,
      mimeType: row.mimeType,
      localPath: row.localPath,
      tempPath: row.tempPath,
      bytesTransferred: row.bytesTransferred,
      state: FileTransferState.values.byName(row.state),
      error: row.error,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}
