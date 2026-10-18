const String rainDefaultErrorText = 'Something went wrong. Try again.';

const int _maxErrorLength = 140;

const List<String> _stripPrefixes = <String>[
  'Exception: ',
  'Bad state: ',
  'StateError: ',
];

final RegExp _unsafeText = RegExp(
  r'(exception:|error:|firebase|#|[A-Za-z]:\\|\\\\|package:|\.dart\b|(?:^|\s)/[\w.-]+/)',
  caseSensitive: false,
);

/// Turns any thrown object into one calm sentence that is safe to show.
///
/// Known runtime phrases map to friendly copy. Anything else is shown only
/// when it already reads like a plain sentence; raw exception text, Firebase
/// codes, paths, stack frames and long text fall back to [fallback].
///
/// [callContext] enables the voice-call phrase mappings (busy, declined,
/// timeouts, signaling, media). Turn it off outside call flows so a generic
/// failure is never reported as a call problem.
String rainUserFacingError(
  Object? error, {
  String fallback = rainDefaultErrorText,
  bool callContext = true,
}) {
  if (error == null) {
    return fallback;
  }
  final raw = error.toString().trim();
  var message = raw;
  for (final prefix in _stripPrefixes) {
    if (raw.startsWith(prefix)) {
      message = raw.substring(prefix.length).trim();
      break;
    }
  }
  final mapped = _friendlyMessageFor(message.toLowerCase(), callContext);
  final result = mapped ?? message;
  if (result.isEmpty ||
      result.length > _maxErrorLength ||
      _unsafeText.hasMatch(result)) {
    return fallback;
  }
  return result;
}

String? _friendlyMessageFor(String normalized, bool callContext) {
  if ((normalized.contains('firebase_database') ||
          normalized.contains('firebase database error')) &&
      normalized.contains('permission denied')) {
    return 'Rain could not create that account data. The username may '
        'already be taken or locked. Try signing in or choose another '
        'username.';
  }
  if (normalized.contains('active file transfer')) {
    return 'Finish the active file transfer first.';
  }
  if (normalized.contains('finish the call before') ||
      normalized == 'finish the call first.') {
    return 'Finish the call before sending files.';
  }
  if (normalized.contains('microphone') &&
      (normalized.contains('permission') || normalized.contains('denied'))) {
    return 'Microphone permission required.';
  }
  if (!callContext) {
    return null;
  }
  if (normalized.contains('peer is busy') ||
      normalized == 'busy.' ||
      normalized.contains('active voice call already exists') ||
      normalized.contains('activevoicepairs') ||
      normalized.contains('active voice pair')) {
    return 'Peer is already in a call.';
  }
  if (normalized == 'rejected.' ||
      normalized.contains('call declined') ||
      normalized.contains('call rejected')) {
    return 'Call declined.';
  }
  if (normalized.contains('network connection lost') ||
      normalized.contains('network lost') ||
      normalized.contains('internet connection') ||
      normalized.contains('network is unavailable') ||
      normalized.contains('network unavailable')) {
    return 'Network connection lost. Call ended.';
  }
  if (normalized.contains('timed out') ||
      normalized.contains('voice call expired') ||
      normalized.contains('call room expired')) {
    return 'Call timed out.';
  }
  if (normalized.contains('voice signaling') ||
      normalized.contains('firebase') ||
      normalized.contains('unknown voice call') ||
      normalized.contains('voice call already exists') ||
      normalized.contains('already ended') ||
      normalized.contains('permission-denied') ||
      normalized.contains('database')) {
    return 'Call setup failed. Try again.';
  }
  if (normalized.contains('ice timeout') ||
      normalized.contains('no remote audio') ||
      normalized.contains('rtcrtptransceiver') ||
      normalized.contains('setdirection') ||
      normalized.contains('setremotedescription') ||
      normalized.contains('peerconnectionsetremotedescription') ||
      normalized.contains('m-line') ||
      normalized.contains('peer connection changed while')) {
    return 'Call media could not connect. Try again.';
  }
  return null;
}
