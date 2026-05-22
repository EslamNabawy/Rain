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
    );

    final decoded = VoiceCallFrame.decode(frame.encode());

    expect(decoded.type, VoiceCallFrameType.invite);
    expect(decoded.callId, 'call-1');
    expect(decoded.from, 'alice');
    expect(decoded.to, 'bob');
    expect(decoded.sentAt, 10);
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
      'sdp': 'sdp',
      'sdpType': 'offer',
    });

    expect(() => VoiceCallFrame.decode(raw), throwsFormatException);
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
      'muted': true,
    });
    expect(() => VoiceCallFrame.decode(inviteWithMuted), throwsFormatException);
  });
}
