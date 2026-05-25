import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain_core/rain_core.dart';

void main() {
  test('encodes and decodes invite frame', () {
    const frame = VoiceCallFrame(
      type: VoiceCallFrameType.invite,
      callId: 'call-1',
      from: 'alice',
      to: 'bob',
      sentAt: 10,
      seq: 1,
      sessionEpoch: 1,
    );

    final decoded = VoiceCallFrame.decode(frame.encode());

    expect(decoded.type, VoiceCallFrameType.invite);
    expect(decoded.callId, 'call-1');
    expect(decoded.from, 'alice');
    expect(decoded.to, 'bob');
    expect(decoded.sentAt, 10);
    expect(decoded.seq, 1);
    expect(decoded.sessionEpoch, 1);
  });

  test('video invite round-trips media mode', () {
    const frame = VoiceCallFrame(
      type: VoiceCallFrameType.invite,
      callId: 'call-1',
      from: 'alice',
      to: 'bob',
      sentAt: 10,
      seq: 1,
      sessionEpoch: 1,
      mediaMode: CallMediaMode.video,
    );

    final encoded = jsonDecode(frame.encode()) as Map<String, Object?>;
    final decoded = VoiceCallFrame.decode(frame.encode());

    expect(encoded['mediaMode'], 'video');
    expect(decoded.mediaMode, CallMediaMode.video);
  });

  test('audio invite defaults to audio media mode', () {
    final decoded = VoiceCallFrame.decode(
      jsonEncode(<String, Object?>{
        'type': VoiceCallFrame.wireType,
        'action': 'invite',
        'callId': 'call-1',
        'from': 'alice',
        'to': 'bob',
        'sentAt': 10,
        'seq': 1,
        'sessionEpoch': 1,
      }),
    );

    expect(decoded.mediaMode, CallMediaMode.audio);
    expect(jsonDecode(decoded.encode()), isNot(contains('mediaMode')));
  });

  test('tryDecode ignores non voice control messages', () {
    final rawAck = jsonEncode(<String, String>{
      'type': 'ack',
      'ackId': 'message-1',
    });

    expect(VoiceCallFrame.tryDecode(rawAck), isNull);
  });

  test('rejects unknown voice action', () {
    final raw = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'dance',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 1,
    });

    expect(() => VoiceCallFrame.decode(raw), throwsFormatException);
    expect(VoiceCallFrame.tryDecode(raw), isNull);
  });

  test('requires sdp on media offer and answer', () {
    final raw = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'offer',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 1,
      'mediaSeq': 1,
      'sdpType': 'offer',
    });

    expect(() => VoiceCallFrame.decode(raw), throwsFormatException);
  });

  test('rejects wrong sdp type for answer', () {
    final raw = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'answer',
      'callId': 'call-1',
      'from': 'bob',
      'to': 'alice',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 1,
      'sdp': 'sdp',
      'sdpType': 'offer',
      'mediaSeq': 1,
    });

    expect(() => VoiceCallFrame.decode(raw), throwsFormatException);
  });

  test('preserves session description text exactly', () {
    const sdp =
        'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n';
    final frame = VoiceCallFrame.decode(
      jsonEncode(<String, Object?>{
        'type': VoiceCallFrame.wireType,
        'action': 'offer',
        'callId': 'call-1',
        'from': 'alice',
        'to': 'bob',
        'sentAt': 10,
        'seq': 1,
        'sessionEpoch': 1,
        'sdp': sdp,
        'sdpType': 'offer',
      }),
    );

    expect(frame.sdp, sdp);
  });

  test('media offer and answer require positive media sequence', () {
    final valid = VoiceCallFrame.decode(
      jsonEncode(<String, Object?>{
        'type': VoiceCallFrame.wireType,
        'action': 'offer',
        'callId': 'call-1',
        'from': 'alice',
        'to': 'bob',
        'sentAt': 10,
        'seq': 7,
        'sessionEpoch': 3,
        'sdp': 'sdp',
        'sdpType': 'offer',
      }),
    );
    expect(valid.seq, 7);
    expect(valid.sessionEpoch, 3);

    final missing = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'answer',
      'callId': 'call-1',
      'from': 'bob',
      'to': 'alice',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 1,
      'sdp': 'sdp',
      'sdpType': 'answer',
    });
    expect(VoiceCallFrame.decode(missing).mediaSeq, isNull);

    final nonMediaWithSequence = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'invite',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 1,
      'mediaSeq': 1,
    });
    expect(
      () => VoiceCallFrame.decode(nonMediaWithSequence),
      throwsFormatException,
    );
  });

  test('hangup frame can carry typed failed reason code', () {
    final hangup = VoiceCallFrame.decode(
      jsonEncode(<String, Object?>{
        'type': VoiceCallFrame.wireType,
        'action': 'hangup',
        'callId': 'call-1',
        'from': 'alice',
        'to': 'bob',
        'sentAt': 10,
        'seq': 1,
        'sessionEpoch': 1,
        'reason': 'Media negotiation failed.',
        'reasonCode': 'failed',
      }),
    );

    expect(hangup.reasonCode, 'failed');
  });

  test('requires muted flag only for mute frame', () {
    final mute = VoiceCallFrame.decode(
      jsonEncode(<String, Object?>{
        'type': VoiceCallFrame.wireType,
        'action': 'mute',
        'callId': 'call-1',
        'from': 'alice',
        'to': 'bob',
        'sentAt': 10,
        'seq': 1,
        'sessionEpoch': 1,
        'muted': true,
      }),
    );
    expect(mute.muted, isTrue);

    final inviteWithMuted = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'invite',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 1,
      'muted': true,
    });
    expect(() => VoiceCallFrame.decode(inviteWithMuted), throwsFormatException);
  });

  test('cameraMuted is only allowed on mute frames', () {
    final cameraMute = VoiceCallFrame.decode(
      jsonEncode(<String, Object?>{
        'type': VoiceCallFrame.wireType,
        'action': 'mute',
        'callId': 'call-1',
        'from': 'alice',
        'to': 'bob',
        'sentAt': 10,
        'seq': 1,
        'sessionEpoch': 1,
        'cameraMuted': true,
      }),
    );

    expect(cameraMute.cameraMuted, isTrue);
    expect(cameraMute.muted, isNull);

    final inviteWithCameraMuted = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'invite',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 1,
      'cameraMuted': true,
    });
    expect(
      () => VoiceCallFrame.decode(inviteWithCameraMuted),
      throwsFormatException,
    );
  });

  test('rejects invalid media mode', () {
    final raw = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'invite',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 1,
      'mediaMode': 'screen',
    });

    expect(() => VoiceCallFrame.decode(raw), throwsFormatException);
    expect(VoiceCallFrame.tryDecode(raw), isNull);
  });

  test('requires positive sequence and session epoch on wire frames', () {
    final missingSequence = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'invite',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'sessionEpoch': 1,
    });
    expect(() => VoiceCallFrame.decode(missingSequence), throwsFormatException);

    final zeroEpoch = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'invite',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'seq': 1,
      'sessionEpoch': 0,
    });
    expect(() => VoiceCallFrame.decode(zeroEpoch), throwsFormatException);
  });

  test('candidate frames require candidate routing fields', () {
    final valid = VoiceCallFrame.decode(
      jsonEncode(<String, Object?>{
        'type': VoiceCallFrame.wireType,
        'action': 'candidate',
        'callId': 'call-1',
        'from': 'alice',
        'to': 'bob',
        'sentAt': 10,
        'seq': 2,
        'sessionEpoch': 1,
        'candidate': 'candidate:1 1 udp 1 127.0.0.1 9 typ host',
        'sdpMid': '0',
        'sdpMLineIndex': 0,
      }),
    );

    expect(valid.type, VoiceCallFrameType.candidate);
    expect(valid.candidate, startsWith('candidate:1'));
    expect(valid.sdpMid, '0');
    expect(valid.sdpMLineIndex, 0);

    final missingSdpMid = jsonEncode(<String, Object?>{
      'type': VoiceCallFrame.wireType,
      'action': 'candidate',
      'callId': 'call-1',
      'from': 'alice',
      'to': 'bob',
      'sentAt': 10,
      'seq': 2,
      'sessionEpoch': 1,
      'candidate': 'candidate:1 1 udp 1 127.0.0.1 9 typ host',
      'sdpMLineIndex': 0,
    });
    expect(() => VoiceCallFrame.decode(missingSdpMid), throwsFormatException);
  });
}
