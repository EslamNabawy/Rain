import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/audio/rain_sound_event.dart';
import 'package:rain/application/audio/sound_event_router.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/infrastructure/services/sound_effects_service.dart';

void main() {
  group('SoundEventRouter', () {
    test('maps chat send and receive events to message effects', () async {
      final effects = _RecordingSoundEffectsService();
      final router = _router(effects);

      await router.dispatch(RainSoundEvent.chatSend(conversationId: 'bob'));
      await router.dispatch(RainSoundEvent.chatReceive(conversationId: 'bob'));

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.send,
        RainSoundEffect.receive,
      ]);
    });

    test('five sends in 200 ms produce one send sound', () async {
      final effects = _RecordingSoundEffectsService();
      final base = DateTime.utc(2026, 5, 24, 12);
      final router = _router(effects);

      for (var index = 0; index < 5; index += 1) {
        await router.dispatch(
          RainSoundEvent.chatSend(
            conversationId: 'bob',
            occurredAt: base.add(Duration(milliseconds: index * 50)),
          ),
        );
      }

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.send,
      ]);
    });

    test('five sends over 1200 ms produce spaced send sounds', () async {
      final effects = _RecordingSoundEffectsService();
      final base = DateTime.utc(2026, 5, 24, 12);
      final router = _router(effects);

      for (var index = 0; index < 5; index += 1) {
        await router.dispatch(
          RainSoundEvent.chatSend(
            conversationId: 'bob',
            occurredAt: base.add(Duration(milliseconds: index * 350)),
          ),
        );
      }

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.send,
        RainSoundEffect.send,
        RainSoundEffect.send,
        RainSoundEffect.send,
        RainSoundEffect.send,
      ]);
    });

    test('ten receives in one chat are grouped but not silenced', () async {
      final effects = _RecordingSoundEffectsService();
      final base = DateTime.utc(2026, 5, 24, 12);
      final router = _router(effects);

      for (var index = 0; index < 10; index += 1) {
        await router.dispatch(
          RainSoundEvent.chatReceive(
            conversationId: 'bob',
            occurredAt: base.add(Duration(milliseconds: index * 300)),
          ),
        );
      }

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.receive,
        RainSoundEffect.receive,
        RainSoundEffect.receive,
        RainSoundEffect.receive,
      ]);
    });

    test('receives from multiple chats are capped globally', () async {
      final effects = _RecordingSoundEffectsService();
      final base = DateTime.utc(2026, 5, 24, 12);
      final router = _router(effects);

      await router.dispatch(
        RainSoundEvent.chatReceive(conversationId: 'bob', occurredAt: base),
      );
      await router.dispatch(
        RainSoundEvent.chatReceive(
          conversationId: 'alice',
          occurredAt: base.add(const Duration(milliseconds: 100)),
        ),
      );
      await router.dispatch(
        RainSoundEvent.chatReceive(
          conversationId: 'alice',
          occurredAt: base.add(const Duration(milliseconds: 400)),
        ),
      );
      await router.dispatch(
        RainSoundEvent.chatReceive(
          conversationId: 'carol',
          occurredAt: base.add(const Duration(milliseconds: 800)),
        ),
      );
      await router.dispatch(
        RainSoundEvent.chatReceive(
          conversationId: 'dan',
          occurredAt: base.add(const Duration(milliseconds: 1200)),
        ),
      );
      await router.dispatch(
        RainSoundEvent.chatReceive(
          conversationId: 'erin',
          occurredAt: base.add(const Duration(milliseconds: 1600)),
        ),
      );

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.receive,
        RainSoundEffect.receive,
        RainSoundEffect.receive,
        RainSoundEffect.receive,
      ]);
    });

    test('receive without conversation id is ignored', () async {
      final effects = _RecordingSoundEffectsService();
      final router = _router(effects);

      await router.dispatch(RainSoundEvent.chatReceive());

      expect(effects.played, isEmpty);
    });

    test('maps warning events to error effect', () async {
      final effects = _RecordingSoundEffectsService();
      final router = _router(effects);

      await router.dispatch(
        RainSoundEvent.warning(errorKey: 'voice.media.failed'),
      );

      expect(effects.played.single.effect, RainSoundEffect.error);
      expect(effects.played.single.voiceCallActive, isFalse);
    });

    test('same error repeated rapidly plays one warning sound', () async {
      final effects = _RecordingSoundEffectsService();
      final base = DateTime.utc(2026, 5, 24, 12);
      final router = _router(effects);

      for (var index = 0; index < 3; index += 1) {
        await router.dispatch(
          RainSoundEvent.warning(
            errorKey: 'media-ice-timeout',
            occurredAt: base.add(Duration(milliseconds: index * 500)),
          ),
        );
      }

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.error,
      ]);
    });

    test('different errors respect global warning ceiling', () async {
      final effects = _RecordingSoundEffectsService();
      final base = DateTime.utc(2026, 5, 24, 12);
      final router = _router(effects);

      for (var index = 0; index < 4; index += 1) {
        await router.dispatch(
          RainSoundEvent.warning(
            errorKey: 'error-$index',
            occurredAt: base.add(Duration(milliseconds: index * 100)),
          ),
        );
      }

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.error,
        RainSoundEffect.error,
        RainSoundEffect.error,
      ]);
    });

    test('maps call controls to dedicated control effects', () async {
      final effects = _RecordingSoundEffectsService();
      final router = _router(effects);

      await router.dispatch(RainSoundEvent.callControlMute(callId: 'call-1'));
      await router.dispatch(RainSoundEvent.callControlUnmute(callId: 'call-1'));
      await router.dispatch(RainSoundEvent.callControlDeafen(callId: 'call-1'));
      await router.dispatch(
        RainSoundEvent.callControlUndeafen(callId: 'call-1'),
      );

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.mute,
        RainSoundEffect.unmute,
        RainSoundEffect.deafen,
        RainSoundEffect.undeafen,
      ]);
      expect(effects.played.every((entry) => entry.allowDuringCall), isTrue);
    });

    test('allows camera controls as quiet call-control actions', () async {
      final effects = _RecordingSoundEffectsService();
      final router = _router(
        effects,
        callState: const VoiceCallState(
          phase: VoiceCallPhase.active,
          callId: 'video-call',
          mediaMode: CallMediaMode.video,
        ),
      );

      await router.dispatch(
        RainSoundEvent.callControlCameraMute(callId: 'video-call'),
      );
      await router.dispatch(
        RainSoundEvent.callControlCameraUnmute(callId: 'video-call'),
      );
      await router.dispatch(
        RainSoundEvent.callRouteChanged(callId: 'video-call'),
      );

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.action,
        RainSoundEffect.action,
        RainSoundEffect.action,
      ]);
      expect(effects.played.every((entry) => entry.voiceCallActive), isTrue);
      expect(effects.played.every((entry) => entry.allowDuringCall), isTrue);
    });

    test('maps call lifecycle events to call effects', () async {
      final effects = _RecordingSoundEffectsService();
      final router = _router(effects);

      await router.dispatch(
        RainSoundEvent.callIncomingStarted(callId: 'call-1'),
      );
      await router.dispatch(
        RainSoundEvent.callOutgoingStarted(callId: 'call-1'),
      );
      await router.dispatch(RainSoundEvent.callConnected(callId: 'call-1'));
      await router.dispatch(RainSoundEvent.callEnded(callId: 'call-1'));
      await router.dispatch(RainSoundEvent.callFailed(callId: 'call-1'));

      expect(effects.played.map((entry) => entry.effect), <RainSoundEffect>[
        RainSoundEffect.callIncoming,
        RainSoundEffect.callOutgoing,
        RainSoundEffect.callConnected,
        RainSoundEffect.callEnded,
        RainSoundEffect.callFailed,
      ]);
    });

    test('respects sound and call sound settings at dispatch time', () async {
      final effects = _RecordingSoundEffectsService();
      var settings = const AppAudioSettings(soundEffectsEnabled: false);
      final router = _router(effects, settingsLoader: () => settings);

      await router.dispatch(RainSoundEvent.chatSend());
      expect(effects.played, isEmpty);

      settings = const AppAudioSettings(callSoundsEnabled: false);
      await router.dispatch(RainSoundEvent.callConnected(callId: 'call-1'));
      await router.dispatch(RainSoundEvent.chatSend());

      expect(effects.played.single.effect, RainSoundEffect.send);
    });

    test(
      'catches sound-service failures without throwing into UI flows',
      () async {
        final effects = _RecordingSoundEffectsService()..throwOnPlay = true;
        final router = _router(effects);

        await router.dispatch(RainSoundEvent.warning(errorKey: 'boom'));

        expect(effects.playAttempts, 1);
        expect(effects.played, isEmpty);
      },
    );

    test('ignores events after dispose', () async {
      final effects = _RecordingSoundEffectsService();
      final router = _router(effects);

      await router.dispose();
      await router.dispatch(RainSoundEvent.chatSend());

      expect(effects.played, isEmpty);
    });
  });
}

SoundEventRouter _router(
  _RecordingSoundEffectsService effects, {
  AppAudioSettings Function()? settingsLoader,
  VoiceCallState callState = const VoiceCallState.idle(),
}) {
  return SoundEventRouter(
    effects: effects,
    settingsLoader: settingsLoader ?? () => const AppAudioSettings(),
    callStateReader: () => callState,
    clock: () => DateTime.utc(2026, 5, 24, 12),
  );
}

final class _PlayedSound {
  const _PlayedSound({
    required this.effect,
    required this.voiceCallActive,
    required this.allowDuringCall,
  });

  final RainSoundEffect effect;
  final bool voiceCallActive;
  final bool allowDuringCall;
}

final class _RecordingSoundEffectsService extends SoundEffectsService {
  _RecordingSoundEffectsService() : super();

  final List<_PlayedSound> played = <_PlayedSound>[];
  var playAttempts = 0;
  var throwOnPlay = false;

  @override
  Future<void> play(
    RainSoundEffect effect, {
    bool voiceCallActive = false,
    bool allowDuringCall = false,
  }) async {
    playAttempts += 1;
    if (throwOnPlay) {
      throw StateError('sound device unavailable');
    }
    played.add(
      _PlayedSound(
        effect: effect,
        voiceCallActive: voiceCallActive,
        allowDuringCall: allowDuringCall,
      ),
    );
  }
}
