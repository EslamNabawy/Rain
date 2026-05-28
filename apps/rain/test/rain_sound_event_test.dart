import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart' show CallMediaMode;
import 'package:rain/application/audio/rain_sound_event.dart';

void main() {
  group('RainSoundEvent', () {
    test('normalizes blank optional ids to null', () {
      final event = RainSoundEvent.callFailed(
        callId: ' call-1 ',
        peerId: '   ',
        errorKey: ' MediaConnectionFailed ',
      );

      expect(event.callId, 'call-1');
      expect(event.peerId, isNull);
      expect(event.errorKey, 'mediaconnectionfailed');
    });

    test('warning uses stable error keys without raw UI text', () {
      final event = RainSoundEvent.warning(
        errorKey: ' VoiceCall.MediaIceTimeout ',
      );

      expect(event.kind, RainSoundEventKind.warning);
      expect(event.errorKey, 'voicecall.mediaicetimeout');
      expect(event.callId, isNull);
      expect(event.peerId, isNull);
    });

    test('call lifecycle events require a non-blank call id', () {
      expect(
        () => RainSoundEvent.callIncomingStarted(callId: '  '),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RainSoundEvent.callOutgoingStarted(callId: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RainSoundEvent.callConnected(callId: '  '),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RainSoundEvent.callEnded(callId: ''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => RainSoundEvent.callFailed(callId: '  '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('call-state lifecycle events preserve epoch and media mode', () {
      final event = RainSoundEvent.callConnected(
        callId: 'call-2',
        peerId: ' eslam ',
        sessionEpoch: 7,
        mediaMode: CallMediaMode.video,
        occurredAt: DateTime.utc(2026, 5, 24, 12),
      );

      expect(event.kind, RainSoundEventKind.callConnected);
      expect(event.callId, 'call-2');
      expect(event.peerId, 'eslam');
      expect(event.sessionEpoch, 7);
      expect(event.mediaMode, CallMediaMode.video);
      expect(event.isCallLifecycleEvent, isTrue);
      expect(event.occurredAt, DateTime.utc(2026, 5, 24, 12));
    });

    test('camera-control events remain call-control video events', () {
      final muted = RainSoundEvent.callControlCameraMute(
        callId: 'video-call',
        sessionEpoch: 3,
      );
      final unmuted = RainSoundEvent.callControlCameraUnmute(
        callId: 'video-call',
        sessionEpoch: 3,
      );

      expect(muted.kind, RainSoundEventKind.callControlCameraMute);
      expect(muted.mediaMode, CallMediaMode.video);
      expect(muted.isCallControlEvent, isTrue);
      expect(muted.isCallLifecycleEvent, isFalse);
      expect(unmuted.kind, RainSoundEventKind.callControlCameraUnmute);
      expect(unmuted.mediaMode, CallMediaMode.video);
      expect(unmuted.isCallControlEvent, isTrue);
    });

    test('chat events allow missing conversation for global system use', () {
      final send = RainSoundEvent.chatSend();
      final receive = RainSoundEvent.chatReceive(conversationId: '  ');

      expect(send.kind, RainSoundEventKind.chatSend);
      expect(send.conversationId, isNull);
      expect(send.mediaMode, CallMediaMode.audio);
      expect(receive.kind, RainSoundEventKind.chatReceive);
      expect(receive.conversationId, isNull);
      expect(receive.isCallLifecycleEvent, isFalse);
      expect(receive.isCallControlEvent, isFalse);
    });

    test('connection request events require a request id', () {
      final inbound = RainSoundEvent.connectionRequestInbound(
        requestId: ' request-1 ',
        peerId: ' Bob ',
      );

      expect(inbound.kind, RainSoundEventKind.connectionRequestInbound);
      expect(inbound.connectionRequestId, 'request-1');
      expect(inbound.peerId, 'Bob');
      expect(inbound.isConnectionRequestEvent, isTrue);
      expect(inbound.isCallLifecycleEvent, isFalse);
      expect(inbound.isCallControlEvent, isFalse);
      expect(
        () => RainSoundEvent.connectionRequestOutboundAccepted(requestId: ' '),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
