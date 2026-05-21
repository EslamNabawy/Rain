import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';

const int fileTransferProtocolVersion = 1;
const int maxFileTransferBytes = 100 * 1024 * 1024;
const int fileTransferChunkBytes = 32 * 1024;
const int fileTransferHighWatermarkBytes = 4 * 1024 * 1024;
const int fileTransferLowWatermarkBytes = 1024 * 1024;

const List<int> _fileChunkPacketMagic = <int>[
  0x52,
  0x41,
  0x49,
  0x4E,
  0x46,
  0x49,
  0x4C,
  0x45,
  0x31,
]; // RAINFILE1

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
    this.finalByteCount,
    this.sha256,
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
  final int? finalByteCount;
  final String? sha256;
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

  factory FileTransferFrame.complete({
    required String transferId,
    required int finalByteCount,
    required String sha256,
  }) {
    return FileTransferFrame(
      type: completeType,
      transferId: transferId,
      finalByteCount: finalByteCount,
      sha256: sha256,
    );
  }

  factory FileTransferFrame.received({
    required String transferId,
    required int finalByteCount,
    required String sha256,
  }) {
    return FileTransferFrame(
      type: receivedType,
      transferId: transferId,
      finalByteCount: finalByteCount,
      sha256: sha256,
    );
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
      finalByteCount: (decoded['finalByteCount'] as num?)?.toInt(),
      sha256: decoded['sha256'] as String?,
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
      if (finalByteCount != null) 'finalByteCount': finalByteCount,
      if (sha256 != null) 'sha256': sha256,
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
      case completeType:
      case receivedType:
        if (finalByteCount == null || sha256 == null || sha256!.isEmpty) {
          throw const FormatException(
            'File completion frame is missing integrity fields.',
          );
        }
        if (finalByteCount! < 0) {
          throw const FormatException(
            'File completion byte count cannot be negative.',
          );
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

class FileTransferChunkPacket {
  const FileTransferChunkPacket({required this.frame, required this.payload});

  final FileTransferFrame frame;
  final Uint8List payload;

  Uint8List encode() {
    if (frame.type != FileTransferFrame.chunkType) {
      throw StateError('File chunk packet requires a chunk frame.');
    }
    if (frame.byteCount != payload.lengthInBytes) {
      throw StateError('File chunk packet byte count does not match payload.');
    }
    final header = Uint8List.fromList(utf8.encode(frame.encode()));
    final bytes = Uint8List(
      _fileChunkPacketMagic.length + 4 + header.lengthInBytes + payload.length,
    );
    bytes.setRange(0, _fileChunkPacketMagic.length, _fileChunkPacketMagic);
    final data = ByteData.sublistView(bytes);
    data.setUint32(_fileChunkPacketMagic.length, header.lengthInBytes);
    final headerOffset = _fileChunkPacketMagic.length + 4;
    bytes.setRange(headerOffset, headerOffset + header.lengthInBytes, header);
    bytes.setRange(
      headerOffset + header.lengthInBytes,
      bytes.lengthInBytes,
      payload,
    );
    return bytes;
  }

  static FileTransferChunkPacket? tryParse(Uint8List bytes) {
    if (!_hasMagic(bytes)) {
      return null;
    }
    final headerLengthOffset = _fileChunkPacketMagic.length;
    if (bytes.lengthInBytes < headerLengthOffset + 4) {
      throw const FormatException('File chunk packet header is missing.');
    }
    final data = ByteData.sublistView(bytes);
    final headerLength = data.getUint32(headerLengthOffset);
    final headerOffset = headerLengthOffset + 4;
    final payloadOffset = headerOffset + headerLength;
    if (headerLength <= 0 || payloadOffset > bytes.lengthInBytes) {
      throw const FormatException('File chunk packet header is invalid.');
    }
    final header = utf8.decode(bytes.sublist(headerOffset, payloadOffset));
    final frame = FileTransferFrame.parse(header);
    if (frame.type != FileTransferFrame.chunkType) {
      throw const FormatException('File chunk packet must contain a chunk.');
    }
    final payload = Uint8List.sublistView(bytes, payloadOffset);
    if (frame.byteCount != payload.lengthInBytes) {
      throw const FormatException(
        'File chunk packet byte count does not match payload.',
      );
    }
    return FileTransferChunkPacket(frame: frame, payload: payload);
  }

  static bool _hasMagic(Uint8List bytes) {
    if (bytes.lengthInBytes < _fileChunkPacketMagic.length) {
      return false;
    }
    for (var index = 0; index < _fileChunkPacketMagic.length; index++) {
      if (bytes[index] != _fileChunkPacketMagic[index]) {
        return false;
      }
    }
    return true;
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
