import 'dart:convert';

final class DiagnosticsSanitizer {
  const DiagnosticsSanitizer._();

  static const String redacted = '[redacted]';
  static const int maxDepth = 8;
  static const int maxItems = 20;
  static const int maxStringLength = 512;

  static final RegExp _alreadySanitizedPattern = RegExp(
    r'^\[(id|path|file|firebase-path):[0-9a-f]{8}\]$',
  );
  static final RegExp _sdpMarkerPattern = RegExp(
    r'(^|\r?\n)(v=0|a=ice-ufrag:|a=fingerprint:|m=(audio|video)\b)',
    caseSensitive: false,
  );
  static final RegExp _iceCandidatePattern = RegExp(
    r'(^|\s)candidate:\S+',
    caseSensitive: false,
  );
  static final RegExp _quotedSecretAssignmentPattern = RegExp(
    r'''\b(password|token|secret|credential|api[_-]?key|authorization)\s*[:=]\s*["'][^"']*["']''',
    caseSensitive: false,
  );
  static final RegExp _unquotedSecretAssignmentPattern = RegExp(
    r'\b(password|token|secret|credential|api[_-]?key|authorization)\s*[:=]\s*[^\s,;)}\]\[]+',
    caseSensitive: false,
  );
  static final RegExp _standaloneSecretValuePattern = RegExp(
    r'\b(?=[A-Za-z0-9._-]*(?:[-_.]|\d))(?=[A-Za-z0-9._-]*(?:password|token|secret|credential|api[_-]?key))[A-Za-z0-9._-]+\b',
    caseSensitive: false,
  );
  static final RegExp _bearerPattern = RegExp(
    r'\bBearer\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );
  static final RegExp _fileAssignmentPattern = RegExp(
    r'''\b(fileName|filename|file|localPath|tempPath|path)\s*[:=]\s*["']?([^"',;)}\]\[\s]+)["']?''',
    caseSensitive: false,
  );
  static final RegExp _firebasePathPattern = RegExp(
    r'(^|[\s:])/?(voiceCalls|voiceCallInboxes|activeVoicePairs|activeVoiceUsers|users|presence|friendships|connectionRequests|userSearch|blocks|blockedUsers)(/[^\s,;)}\]]*)?',
    caseSensitive: false,
  );
  static final RegExp _windowsPathPattern = RegExp(
    r'[A-Za-z]:[\\/][^\s,;)}\]]+',
  );
  static final RegExp _androidPathPattern = RegExp(
    r'/(storage|document|tree|data/user|sdcard)/[^\s,;)}\]]+',
    caseSensitive: false,
  );
  static final RegExp _emailPattern = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );

  static Map<String, Object?> sanitizeMap(
    Map<String, Object?> value, {
    int depth = 0,
  }) {
    if (depth >= maxDepth) {
      return const <String, Object?>{};
    }
    final sanitized = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      sanitized[key] = sanitizeValue(entry.value, key: key, depth: depth + 1);
    }
    return sanitized;
  }

  static Object? sanitizeValue(Object? value, {String? key, int depth = 0}) {
    if (value == null || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }
    if (value is Enum) {
      return value.name;
    }
    final normalizedKey = _normalizeKey(key);
    if (value is String) {
      return _sanitizeStringForKey(value, normalizedKey);
    }
    if (value is Iterable) {
      if (_isFullyRedactedKey(normalizedKey) ||
          _isMessageContentKey(normalizedKey)) {
        return redacted;
      }
      if (depth >= maxDepth) {
        return const <Object?>[];
      }
      return value
          .take(maxItems)
          .map((Object? item) => sanitizeValue(item, depth: depth + 1))
          .toList(growable: false);
    }
    if (value is Map) {
      if (_isFullyRedactedKey(normalizedKey) ||
          _isMessageContentKey(normalizedKey)) {
        return redacted;
      }
      if (depth >= maxDepth) {
        return const <String, Object?>{};
      }
      return sanitizeMap(
        value.map<String, Object?>(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
        depth: depth,
      );
    }
    return _sanitizeStringForKey(value.toString(), normalizedKey);
  }

  static String sanitizeString(String value, {String? key}) {
    return _sanitizeStringForKey(value, _normalizeKey(key));
  }

  static String _sanitizeStringForKey(String value, String normalizedKey) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _isAlreadySanitized(trimmed)) {
      return trimmed;
    }
    final decoded = _tryDecodeJsonContainer(trimmed);
    if (decoded != null) {
      return jsonEncode(sanitizeValue(decoded, depth: 0));
    }
    if (_isSecretKey(normalizedKey)) {
      return redacted;
    }
    if (_isSdpKey(normalizedKey)) {
      return '[redacted:sdp]';
    }
    if (_isIceCandidateKey(normalizedKey)) {
      return '[redacted:ice-candidate]';
    }
    if (_isMessageContentKey(normalizedKey)) {
      return redacted;
    }
    if (_isFileNameKey(normalizedKey)) {
      return _pseudonym('file', trimmed);
    }
    if (_isPathKey(normalizedKey)) {
      return _pseudonym(
        _looksLikeFirebasePath(trimmed) ? 'firebase-path' : 'path',
        trimmed,
      );
    }
    if (_isIdentityKey(normalizedKey)) {
      return _pseudonym('id', trimmed);
    }
    return _trim(_sanitizeFreeText(trimmed));
  }

  static String _sanitizeFreeText(String value) {
    if (_sdpMarkerPattern.hasMatch(value)) {
      return '[redacted:sdp]';
    }
    if (_iceCandidatePattern.hasMatch(value)) {
      return '[redacted:ice-candidate]';
    }
    var sanitized = value;
    sanitized = sanitized.replaceAllMapped(
      _quotedSecretAssignmentPattern,
      (match) => '${match.group(1)}=$redacted',
    );
    sanitized = sanitized.replaceAllMapped(
      _unquotedSecretAssignmentPattern,
      (match) => '${match.group(1)}=$redacted',
    );
    sanitized = sanitized.replaceAll(_bearerPattern, 'Bearer $redacted');
    sanitized = sanitized.replaceAll(_standaloneSecretValuePattern, redacted);
    final beforeFileAssignments = sanitized;
    sanitized = sanitized.replaceAllMapped(_fileAssignmentPattern, (match) {
      final previous = match.start > 0
          ? beforeFileAssignments[match.start - 1]
          : '';
      if (previous == '[' || previous == '-') {
        return match.group(0) ?? '';
      }
      final key = match.group(1) ?? 'file';
      final raw = match.group(2) ?? '';
      final normalizedKey = _normalizeKey(key);
      final kind = _isFileNameKey(normalizedKey)
          ? 'file'
          : _looksLikeFirebasePath(raw)
          ? 'firebase-path'
          : 'path';
      return '$key=${_pseudonym(kind, raw)}';
    });
    sanitized = sanitized.replaceAllMapped(_firebasePathPattern, (match) {
      final prefix = match.group(1) ?? '';
      final path = match.group(0)?.substring(prefix.length) ?? '';
      return '$prefix${_pseudonym('firebase-path', path)}';
    });
    sanitized = sanitized.replaceAllMapped(
      _windowsPathPattern,
      (match) => _pseudonym('path', match.group(0) ?? ''),
    );
    sanitized = sanitized.replaceAllMapped(
      _androidPathPattern,
      (match) => _pseudonym('path', match.group(0) ?? ''),
    );
    sanitized = sanitized.replaceAllMapped(
      _emailPattern,
      (match) => _pseudonym('id', match.group(0) ?? ''),
    );
    return sanitized;
  }

  static Object? _tryDecodeJsonContainer(String value) {
    if (!((value.startsWith('{') && value.endsWith('}')) ||
        (value.startsWith('[') && value.endsWith(']')))) {
      return null;
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map || decoded is List) {
        return decoded;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static bool _isAlreadySanitized(String value) {
    return value == redacted ||
        value.startsWith('[redacted:') ||
        _alreadySanitizedPattern.hasMatch(value);
  }

  static String _normalizeKey(String? key) {
    return (key ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );
  }

  static bool _isSecretKey(String key) {
    return key.contains('password') ||
        key.contains('token') ||
        key.contains('credential') ||
        key.contains('secret') ||
        key.contains('apikey') ||
        key.contains('privatekey') ||
        key == 'authorization' ||
        key == 'authheader';
  }

  static bool _isSdpKey(String key) {
    return key == 'sdp' || key == 'sessiondescription';
  }

  static bool _isIceCandidateKey(String key) {
    return key == 'candidate' || key == 'icecandidate' || key == 'rawcandidate';
  }

  static bool _isFullyRedactedKey(String key) {
    return _isSecretKey(key) ||
        _isSdpKey(key) ||
        _isIceCandidateKey(key) ||
        key == 'ciphertext' ||
        key == 'nonce' ||
        key == 'mac' ||
        key == 'filebytes';
  }

  static bool _isMessageContentKey(String key) {
    return key == 'messagetext' ||
        key == 'messagebody' ||
        key == 'plaintext' ||
        key == 'chattext' ||
        key == 'content' ||
        key == 'body' ||
        key == 'text';
  }

  static bool _isFileNameKey(String key) {
    return key == 'file' || key == 'filename' || key.endsWith('filename');
  }

  static bool _isPathKey(String key) {
    return key == 'path' ||
        key.endsWith('path') ||
        key == 'firebasepath' ||
        key == 'lockpath';
  }

  static bool _isIdentityKey(String key) {
    return const <String>{
      'id',
      'peerid',
      'callid',
      'roomid',
      'requestid',
      'transferid',
      'sessionid',
      'uid',
      'userid',
      'username',
      'displayname',
      'caller',
      'callee',
      'from',
      'to',
      'pairid',
      'calleruserlock',
      'calleeuserlock',
      'lockcallid',
      'owner',
      'sender',
      'recipient',
    }.contains(key);
  }

  static bool _looksLikeFirebasePath(String value) {
    final normalized = value.replaceAll(r'\', '/');
    return normalized.startsWith('/voiceCalls/') ||
        normalized.startsWith('voiceCalls/') ||
        normalized.startsWith('/voiceCallInboxes/') ||
        normalized.startsWith('voiceCallInboxes/') ||
        normalized.startsWith('/activeVoicePairs/') ||
        normalized.startsWith('activeVoicePairs/') ||
        normalized.startsWith('/activeVoiceUsers/') ||
        normalized.startsWith('activeVoiceUsers/') ||
        normalized.startsWith('/users/') ||
        normalized.startsWith('users/') ||
        normalized.startsWith('/presence/') ||
        normalized.startsWith('presence/') ||
        normalized.startsWith('/friendships/') ||
        normalized.startsWith('friendships/') ||
        normalized.startsWith('/connectionRequests/') ||
        normalized.startsWith('connectionRequests/');
  }

  static String _pseudonym(String kind, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _isAlreadySanitized(trimmed)) {
      return trimmed;
    }
    return '[$kind:${_fingerprint(trimmed)}]';
  }

  static String _fingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String _trim(String value) {
    if (value.length <= maxStringLength) {
      return value;
    }
    return '${value.substring(0, maxStringLength)}...';
  }
}
