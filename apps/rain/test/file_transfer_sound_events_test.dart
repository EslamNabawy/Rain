import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/audio/rain_sound_event.dart';
import 'package:rain/presentation/widgets/home/file_transfer_sound_events.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  test('first load plays nothing even for finished transfers', () {
    final events = rainFileTransferSoundEventsFor(
      next: <FileTransferRecord>[
        _record('t-1', FileTransferState.completed),
        _record('t-2', FileTransferState.failed),
      ],
    );

    expect(events, isEmpty);
  });

  test('sending to completed plays one completed cue', () {
    final events = rainFileTransferSoundEventsFor(
      previous: <FileTransferRecord>[_record('t-1', FileTransferState.sending)],
      next: <FileTransferRecord>[_record('t-1', FileTransferState.completed)],
    );

    expect(events.single.kind, RainSoundEventKind.fileTransferCompleted);
    expect(events.single.transferId, 't-1');
    expect(events.single.peerId, 'bob');
  });

  test('receiving to failed plays one failed cue', () {
    final events = rainFileTransferSoundEventsFor(
      previous: <FileTransferRecord>[
        _record('t-1', FileTransferState.receiving),
      ],
      next: <FileTransferRecord>[_record('t-1', FileTransferState.failed)],
    );

    expect(events.single.kind, RainSoundEventKind.fileTransferFailed);
  });

  test('unchanged list plays nothing', () {
    final records = <FileTransferRecord>[
      _record('t-1', FileTransferState.completed),
      _record('t-2', FileTransferState.sending),
    ];

    expect(
      rainFileTransferSoundEventsFor(previous: records, next: records),
      isEmpty,
    );
  });

  test('canceled and rejected transfers stay silent', () {
    final events = rainFileTransferSoundEventsFor(
      previous: <FileTransferRecord>[
        _record('t-1', FileTransferState.sending),
        _record('t-2', FileTransferState.offered),
      ],
      next: <FileTransferRecord>[
        _record('t-1', FileTransferState.canceled),
        _record('t-2', FileTransferState.rejected),
      ],
    );

    expect(events, isEmpty);
  });
}

FileTransferRecord _record(String id, FileTransferState state) {
  final now = DateTime.utc(2026, 10, 26).millisecondsSinceEpoch;
  return FileTransferRecord(
    id: id,
    peerId: 'bob',
    messageId: 'm-$id',
    direction: FileTransferDirection.outgoing,
    fileName: 'notes.txt',
    fileSize: 100,
    bytesTransferred: 0,
    state: state,
    createdAt: now,
    updatedAt: now,
  );
}
