import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('presence while the app is backgrounded', () {
    late RainDatabase db;
    late NoopSignalingAdapter adapter;
    late RainRuntimeController runtime;

    const alice = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: null,
    );

    setUp(() async {
      db = RainDatabase(NativeDatabase.memory());
      adapter = NoopSignalingAdapter();
      runtime = RainRuntimeController(
        selfIdentity: alice,
        adapter: adapter,
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
        heartbeatInterval: const Duration(milliseconds: 10),
      );
      await runtime.start();
    });

    tearDown(() async {
      await runtime.dispose();
      await db.close();
    });

    test('pause without a call marks presence offline', () async {
      runtime.didChangeAppLifecycleState(AppLifecycleState.paused);

      await _waitFor(
        () async => (await adapter.fetchIdentity('alice'))?.online == false,
        'presence to go offline',
      );
    });

    test('pause during an active call keeps presence online', () async {
      runtime.voiceCallState = _activeCall();

      runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect((await adapter.fetchIdentity('alice'))?.online, isTrue);
    });

    test('hidden window during an active file transfer stays online', () async {
      await FileTransferStore(db).upsert(
        const FileTransferRecord(
          id: 'transfer-1',
          peerId: 'bob',
          messageId: 'message-1',
          direction: FileTransferDirection.incoming,
          fileName: 'clip.bin',
          fileSize: 4096,
          bytesTransferred: 10,
          state: FileTransferState.receiving,
          createdAt: 1,
          updatedAt: 1,
        ),
      );

      runtime.didChangeAppLifecycleState(AppLifecycleState.hidden);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect((await adapter.fetchIdentity('alice'))?.online, isTrue);
    });

    test(
      'presence goes offline once the call ends in the background',
      () async {
        runtime.voiceCallState = _activeCall();
        runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect((await adapter.fetchIdentity('alice'))?.online, isTrue);

        runtime.voiceCallState = const VoiceCallState.idle();

        await _waitFor(
          () async => (await adapter.fetchIdentity('alice'))?.online == false,
          'presence to go offline after the call ended',
        );
      },
    );

    test('resuming brings presence back online', () async {
      runtime.didChangeAppLifecycleState(AppLifecycleState.paused);
      await _waitFor(
        () async => (await adapter.fetchIdentity('alice'))?.online == false,
        'presence to go offline',
      );

      runtime.didChangeAppLifecycleState(AppLifecycleState.resumed);

      await _waitFor(
        () async => (await adapter.fetchIdentity('alice'))?.online == true,
        'presence to come back online',
      );
    });
  });
}

VoiceCallState _activeCall() {
  return const VoiceCallState(
    phase: VoiceCallPhase.active,
    peerId: 'bob',
    callId: 'call-1',
    sessionEpoch: 1,
    mediaMode: CallMediaMode.audio,
    isOutgoing: true,
    updatedAt: 1,
  );
}

Future<void> _waitFor(
  Future<bool> Function() condition,
  String description,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $description.');
}
