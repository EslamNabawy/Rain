import 'dart:convert';

import 'package:collection/collection.dart';

const int fileTransferProtocolVersion = 1;
const int maxFileTransferBytes = 100 * 1024 * 1024;
const int fileTransferChunkBytes = 64 * 1024;
const int fileTransferHighWatermarkBytes = 4 * 1024 * 1024;
const int fileTransferLowWatermarkBytes = 1024 * 1024;

class FileTransferFrame {
  const FileTransferFrame({
    required this.type,
    required this.transferId,
    this.messageId,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.sentAt,
    this.seq,
    this.index,
    this.offset,
    this.byteCount,
    this.reason,
  });

  static const String offerType = 'file.offer';
  static const String acceptType = 'file.accept';
  static const String rejectType = 'file.reject';
  static const String chunkType = 'file.chunk';
  static const String completeType = 'file.complete';
  static const String receivedType = 'file.received';
  static const String cancelType = 'file.cancel';
  static const String failType = 'file.fail';

  final String type;
  final String transferId;
  final String? messageId;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final int? sentAt;
  final int? seq;
  final int? index;
  final int? offset;
  final int? byteCount;
  final String? reason;

  factory FileTransferFrame.offer({
    required String transferId,
    required String messageId,
    required String fileName,
    required int fileSize,
    required int sentAt,
    required int seq,
    String? mimeType,
  }) {
    return FileTransferFrame(
      type: offerType,
      transferId: transferId,
      messageId: messageId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      sentAt: sentAt,
      seq: seq,
    );
  }

  factory FileTransferFrame.accept(String transferId) {
    return FileTransferFrame(type: acceptType, transferId: transferId);
  }

  factory FileTransferFrame.reject(String transferId, String reason) {
    return FileTransferFrame(
      type: rejectType,
      transferId: transferId,
      reason: reason,
    );
  }

  factory FileTransferFrame.chunk({
    required String transferId,
    required int index,
    required int offset,
    required int byteCount,
  }) {
    return FileTransferFrame(
      type: chunkType,
      transferId: transferId,
      index: index,
      offset: offset,
      byteCount: byteCount,
    );
  }

  factory FileTransferFrame.complete(String transferId) {
    return FileTransferFrame(type: completeType, transferId: transferId);
  }

  factory FileTransferFrame.received(String transferId) {
    return FileTransferFrame(type: receivedType, transferId: transferId);
  }

  factory FileTransferFrame.cancel(String transferId, String reason) {
    return FileTransferFrame(
      type: cancelType,
      transferId: transferId,
      reason: reason,
    );
  }

  factory FileTransferFrame.fail(String transferId, String reason) {
    return FileTransferFrame(
      type: failType,
      transferId: transferId,
      reason: reason,
    );
  }

  static FileTransferFrame parse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('File transfer frame must be a JSON object.');
    }
    final version = (decoded['v'] as num?)?.toInt();
    if (version != fileTransferProtocolVersion) {
      throw FormatException('Unsupported file transfer version: $version');
    }
    final type = decoded['type'] as String?;
    final transferId = decoded['id'] as String?;
    if (type == null ||
        type.isEmpty ||
        transferId == null ||
        transferId.isEmpty) {
      throw const FormatException('File transfer frame is missing type or id.');
    }
    if (!_knownTypes.contains(type)) {
      throw FormatException('Unknown file transfer frame type: $type');
    }
    return FileTransferFrame(
      type: type,
      transferId: transferId,
      messageId: decoded['messageId'] as String?,
      fileName: decoded['fileName'] as String?,
      fileSize: (decoded['fileSize'] as num?)?.toInt(),
      mimeType: decoded['mimeType'] as String?,
      sentAt: (decoded['sentAt'] as num?)?.toInt(),
      seq: (decoded['seq'] as num?)?.toInt(),
      index: (decoded['index'] as num?)?.toInt(),
      offset: (decoded['offset'] as num?)?.toInt(),
      byteCount: (decoded['byteCount'] as num?)?.toInt(),
      reason: decoded['reason'] as String?,
    ).._validate();
  }

  static const Set<String> _knownTypes = <String>{
    offerType,
    acceptType,
    rejectType,
    chunkType,
    completeType,
    receivedType,
    cancelType,
    failType,
  };

  String encode() => jsonEncode(toJson());

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'v': fileTransferProtocolVersion,
      'type': type,
      'id': transferId,
      if (messageId != null) 'messageId': messageId,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      if (mimeType != null) 'mimeType': mimeType,
      if (sentAt != null) 'sentAt': sentAt,
      if (seq != null) 'seq': seq,
      if (index != null) 'index': index,
      if (offset != null) 'offset': offset,
      if (byteCount != null) 'byteCount': byteCount,
      if (reason != null) 'reason': reason,
    };
  }

  void _validate() {
    switch (type) {
      case offerType:
        if (messageId == null ||
            fileName == null ||
            fileSize == null ||
            sentAt == null ||
            seq == null) {
          throw const FormatException('File offer is missing required fields.');
        }
        if (fileSize! < 0) {
          throw const FormatException('File offer size cannot be negative.');
        }
        break;
      case chunkType:
        if (index == null || offset == null || byteCount == null) {
          throw const FormatException('File chunk is missing required fields.');
        }
        if (index! < 0 || offset! < 0 || byteCount! <= 0) {
          throw const FormatException('File chunk has invalid counters.');
        }
        break;
    }
  }
}

class FileMessageContent {
  const FileMessageContent({
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    this.mimeType,
  });

  final String transferId;
  final String fileName;
  final int fileSize;
  final String? mimeType;

  String encode() {
    return jsonEncode(<String, Object?>{
      'transferId': transferId,
      'fileName': fileName,
      'fileSize': fileSize,
      if (mimeType != null) 'mimeType': mimeType,
    });
  }

  static FileMessageContent parse(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return FileMessageContent(
      transferId: decoded['transferId'] as String,
      fileName: decoded['fileName'] as String,
      fileSize: (decoded['fileSize'] as num).toInt(),
      mimeType: decoded['mimeType'] as String?,
    );
  }
}

String sanitizeFileName(String rawName) {
  final tail =
      rawName.split(RegExp(r'[\\/]')).where((part) {
        return part.trim().isNotEmpty;
      }).lastOrNull ??
      'file';
  final sanitized = tail
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
      .trim();
  final fallback =
      sanitized.isEmpty ||
          sanitized == '.' ||
          sanitized == '..' ||
          RegExp(r'^_+$').hasMatch(sanitized)
      ? 'file'
      : sanitized;
  return fallback.length <= 120 ? fallback : fallback.substring(0, 120);
}

String formatFileTransferSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}
