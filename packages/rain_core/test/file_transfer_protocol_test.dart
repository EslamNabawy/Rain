import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/rain_core.dart';

void main() {
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
