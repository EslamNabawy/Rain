import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/src/voice_call_cleanup_janitor.dart';
import 'package:protocol_brain/src/voice_signaling_contract.dart';

VoiceCallRoom _room({
  required VoiceCallSignalingStatus status,
  int expiresAt = 2000,
  String callId = 'call-1',
}) {
  return VoiceCallRoom(
    v: VoiceCallRoom.version,
    callId: callId,
    pairId: voiceCallPairId('alice', 'bob'),
    caller: 'alice',
    callee: 'bob',
    status: status,
    createdAt: 1000,
    updatedAt: 1000,
    expiresAt: expiresAt,
  );
}

void main() {
  group('decideVoiceCallRoomCleanup', () {
    test('missing room is reported so matching locks can be removed', () {
      expect(
        decideVoiceCallRoomCleanup(room: null, now: 5000),
        VoiceCallRoomCleanupVerdict.missingRoom,
      );
    });

    test('terminal room is reclaimed even before it expires', () {
      for (final status in <VoiceCallSignalingStatus>[
        VoiceCallSignalingStatus.ended,
        VoiceCallSignalingStatus.failed,
        VoiceCallSignalingStatus.expired,
      ]) {
        expect(
          decideVoiceCallRoomCleanup(
            room: _room(status: status, expiresAt: 9000),
            now: 5000,
          ),
          VoiceCallRoomCleanupVerdict.terminal,
          reason: status.name,
        );
      }
    });

    test('expired setup room is reclaimed', () {
      expect(
        decideVoiceCallRoomCleanup(
          room: _room(status: VoiceCallSignalingStatus.ringing),
          now: 5000,
        ),
        VoiceCallRoomCleanupVerdict.expiredSetup,
      );
    });

    test(
      'connected room past expiresAt is reclaimed when not the live call',
      () {
        expect(
          decideVoiceCallRoomCleanup(
            room: _room(status: VoiceCallSignalingStatus.connected),
            now: 5000,
            liveCallId: 'other-call',
          ),
          VoiceCallRoomCleanupVerdict.expiredConnected,
        );
        expect(
          decideVoiceCallRoomCleanup(
            room: _room(status: VoiceCallSignalingStatus.connected),
            now: 5000,
          ),
          VoiceCallRoomCleanupVerdict.expiredConnected,
        );
      },
    );

    test('connected room is kept when it is the live local call', () {
      expect(
        decideVoiceCallRoomCleanup(
          room: _room(status: VoiceCallSignalingStatus.connected),
          now: 5000,
          liveCallId: 'call-1',
        ),
        VoiceCallRoomCleanupVerdict.keep,
      );
    });

    test('live local call is kept even when its setup room has expired', () {
      expect(
        decideVoiceCallRoomCleanup(
          room: _room(status: VoiceCallSignalingStatus.negotiating),
          now: 5000,
          liveCallId: 'call-1',
        ),
        VoiceCallRoomCleanupVerdict.keep,
      );
    });

    test('unexpired room is kept', () {
      expect(
        decideVoiceCallRoomCleanup(
          room: _room(
            status: VoiceCallSignalingStatus.connected,
            expiresAt: 9000,
          ),
          now: 5000,
        ),
        VoiceCallRoomCleanupVerdict.keep,
      );
    });
  });

  test('cleanup action names include the expired connected room action', () {
    expect(
      VoiceCallCleanupAction.values.map((VoiceCallCleanupAction a) => a.name),
      contains('deleteExpiredConnectedRoom'),
    );
  });
}
