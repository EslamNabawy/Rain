/// # file_transfer_sound_events.dart
///
/// Pure diff that turns file transfer list changes for the open conversation
/// into completed/failed sound events.
///
/// **Key types:** rainFileTransferSoundEventsFor
///
/// **Depends on:** rain_core (FileTransferRecord), RainSoundEvent
library;

import 'package:rain/application/audio/rain_sound_event.dart';
import 'package:rain_core/rain_core.dart';

/// Returns one event per transfer whose state moved into completed or failed
/// between [previous] and [next]. First load ([previous] null) yields none so
/// opening a chat never replays old outcomes.
List<RainSoundEvent> rainFileTransferSoundEventsFor({
  List<FileTransferRecord>? previous,
  required List<FileTransferRecord> next,
}) {
  if (previous == null) {
    return const <RainSoundEvent>[];
  }
  final previousStates = <String, FileTransferState>{
    for (final record in previous) record.id: record.state,
  };
  final events = <RainSoundEvent>[];
  for (final record in next) {
    final before = previousStates[record.id];
    if (before == record.state) {
      continue;
    }
    if (record.state == FileTransferState.completed) {
      events.add(
        RainSoundEvent.fileTransferCompleted(
          transferId: record.id,
          peerId: record.peerId,
        ),
      );
    } else if (record.state == FileTransferState.failed) {
      events.add(
        RainSoundEvent.fileTransferFailed(
          transferId: record.id,
          peerId: record.peerId,
        ),
      );
    }
  }
  return events;
}
