import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  group('file transfer throughput settings', () {
    test(
      'uses mobile-safe chunks and buffer room for reliable P2P transfers',
      () {
        expect(fileTransferChunkBytes, 32 * 1024);
        expect(fileTransferLowWatermarkBytes, 1024 * 1024);
        expect(fileTransferHighWatermarkBytes, 4 * 1024 * 1024);
        expect(
          fileTransferLowWatermarkBytes,
          lessThan(fileTransferHighWatermarkBytes),
        );
      },
    );
  });

  group('FileTransferFrame', () {
    test('round-trips a valid offer frame', () {
      final frame = FileTransferFrame.offer(
        transferId: 'transfer-1',
        messageId: 'message-1',
        fileName: 'report.pdf',
        fileSize: 42,
        mimeType: 'application/pdf',
        sentAt: 123,
        seq: 7,
      );

      final parsed = FileTransferFrame.parse(frame.encode());

      expect(parsed.type, FileTransferFrame.offerType);
      expect(parsed.transferId, 'transfer-1');
      expect(parsed.messageId, 'message-1');
      expect(parsed.fileName, 'report.pdf');
      expect(parsed.fileSize, 42);
      expect(parsed.mimeType, 'application/pdf');
      expect(parsed.sentAt, 123);
      expect(parsed.seq, 7);
    });

    test('rejects unknown versions and frame types', () {
      expect(
        () => FileTransferFrame.parse(
          jsonEncode(<String, Object?>{
            'v': 99,
            'type': FileTransferFrame.acceptType,
            'id': 'transfer-1',
          }),
        ),
        throwsFormatException,
      );

      expect(
        () => FileTransferFrame.parse(
          jsonEncode(<String, Object?>{
            'v': fileTransferProtocolVersion,
            'type': 'file.execute',
            'id': 'transfer-1',
          }),
        ),
        throwsFormatException,
      );
    });

    test('rejects invalid chunk counters', () {
      expect(
        () => FileTransferFrame.parse(
          jsonEncode(<String, Object?>{
            'v': fileTransferProtocolVersion,
            'type': FileTransferFrame.chunkType,
            'id': 'transfer-1',
            'index': 0,
            'offset': 0,
            'byteCount': 0,
          }),
        ),
        throwsFormatException,
      );
    });

    test('completion frames require final byte count and hash', () {
      final frame = FileTransferFrame.complete(
        transferId: 'transfer-1',
        finalByteCount: 4,
        sha256:
            '63d987d1c6d69751c17297f410f5b3547a65d096a8993b35bcb4f9cad054f176',
      );

      final parsed = FileTransferFrame.parse(frame.encode());

      expect(parsed.type, FileTransferFrame.completeType);
      expect(parsed.finalByteCount, 4);
      expect(
        parsed.sha256,
        '63d987d1c6d69751c17297f410f5b3547a65d096a8993b35bcb4f9cad054f176',
      );
      expect(
        () => FileTransferFrame.parse(
          jsonEncode(<String, Object?>{
            'v': fileTransferProtocolVersion,
            'type': FileTransferFrame.receivedType,
            'id': 'transfer-1',
          }),
        ),
        throwsFormatException,
      );
    });

    test('packs chunk metadata and bytes into one binary message', () {
      final payload = Uint8List.fromList(<int>[1, 2, 3, 4]);
      final frame = FileTransferFrame.chunk(
        transferId: 'transfer-1',
        index: 2,
        offset: 8192,
        byteCount: payload.lengthInBytes,
      );

      final encoded = FileTransferChunkPacket(
        frame: frame,
        payload: payload,
      ).encode();
      final parsed = FileTransferChunkPacket.tryParse(encoded);

      expect(parsed, isNotNull);
      expect(parsed!.frame.transferId, 'transfer-1');
      expect(parsed.frame.index, 2);
      expect(parsed.frame.offset, 8192);
      expect(parsed.payload, payload);
    });
  });

  group('file message content', () {
    test('round-trips compact chat content', () {
      final content = FileMessageContent(
        transferId: 'transfer-1',
        fileName: 'image.png',
        fileSize: 2048,
        mimeType: 'image/png',
      );

      final parsed = FileMessageContent.parse(content.encode());

      expect(parsed.transferId, content.transferId);
      expect(parsed.fileName, content.fileName);
      expect(parsed.fileSize, content.fileSize);
      expect(parsed.mimeType, content.mimeType);
    });
  });

  group('sanitizeFileName', () {
    test('removes paths, control characters, and unsafe filename chars', () {
      expect(
        sanitizeFileName('C:\\Users\\me\\bad<name>\u0000.txt'),
        'bad_name_.txt',
      );
      expect(sanitizeFileName('../secret.txt'), 'secret.txt');
      expect(sanitizeFileName('\u0000<>:"/\\|?*'), 'file');
    });
  });
}
