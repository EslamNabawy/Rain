import 'package:flutter_test/flutter_test.dart';
import 'package:rain/presentation/feedback/rain_error_text.dart';

void main() {
  test('strips Exception, Bad state and StateError prefixes', () {
    expect(
      rainUserFacingError(Exception('Username is taken.')),
      'Username is taken.',
    );
    expect(
      rainUserFacingError(StateError('Pick a friend first.')),
      'Pick a friend first.',
    );
    expect(
      rainUserFacingError('StateError: Nothing selected.'),
      'Nothing selected.',
    );
  });

  test('maps known runtime phrases', () {
    expect(
      rainUserFacingError(Exception('Active file transfer in progress')),
      'Finish the active file transfer first.',
    );
    expect(
      rainUserFacingError('Finish the call before sending files'),
      'Finish the call before sending files.',
    );
    expect(
      rainUserFacingError('Microphone permission denied'),
      'Microphone permission required.',
    );
    expect(rainUserFacingError('Peer is busy'), 'Peer is already in a call.');
    expect(rainUserFacingError('call declined by peer'), 'Call declined.');
    expect(
      rainUserFacingError('internet connection lost'),
      'Network connection lost. Call ended.',
    );
    expect(rainUserFacingError('operation timed out'), 'Call timed out.');
    expect(
      rainUserFacingError('voice signaling failed'),
      'Call setup failed. Try again.',
    );
    expect(
      rainUserFacingError('ICE timeout'),
      'Call media could not connect. Try again.',
    );
  });

  test('maps account permission denied to account guidance', () {
    expect(
      rainUserFacingError('firebase_database/permission denied'),
      startsWith('Rain could not create that account data.'),
    );
  });

  test('never returns raw exception, path, hash or stack text', () {
    const fallback = rainDefaultErrorText;
    expect(
      rainUserFacingError('SocketException: Failed host lookup'),
      fallback,
    );
    expect(rainUserFacingError('FormatException: bad'), fallback);
    expect(rainUserFacingError('Error: boom'), fallback);
    expect(rainUserFacingError(r'Cannot open C:\Users\me\file.txt'), fallback);
    expect(rainUserFacingError('Cannot open /data/user/0/rain/file'), fallback);
    expect(rainUserFacingError('Issue #42 happened'), fallback);
    expect(rainUserFacingError('#0 main (package:rain/main.dart:1)'), fallback);
    expect(rainUserFacingError(null), fallback);
    expect(rainUserFacingError(''), fallback);
  });

  test('long text falls back and custom fallback is honoured', () {
    expect(rainUserFacingError('x' * 141), rainDefaultErrorText);
    expect(rainUserFacingError('x' * 140), 'x' * 140);
    expect(
      rainUserFacingError('Error: boom', fallback: 'Try later.'),
      'Try later.',
    );
  });

  test('callContext false skips voice-call phrases', () {
    expect(
      rainUserFacingError('operation timed out', callContext: false),
      'operation timed out',
    );
    expect(
      rainUserFacingError('firebase unreachable', callContext: false),
      rainDefaultErrorText,
    );
    expect(
      rainUserFacingError('Active file transfer', callContext: false),
      'Finish the active file transfer first.',
    );
  });
}
