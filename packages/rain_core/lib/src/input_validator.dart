class InputValidator {
  InputValidator._();

  static final RegExp _usernameRegex = RegExp(r'^[a-z0-9_]{3,24}$');
  static final RegExp _displayNameRegex = RegExp(r'^[\w\s\-]{1,32}$');
  static final RegExp _messageRegex = RegExp(r'^.{1,4000}$', dotAll: true);
  static final RegExp _searchRegex = RegExp(r'^[\w\s\-]{2,50}$');
  static final RegExp _sanitizationRegex = RegExp(r'[<>{}\\]');
  static final RegExp _whitespaceCollapseRegex = RegExp(r'\s+');

  static const int usernameMinLength = 3;
  static const int usernameMaxLength = 24;
  static const int displayNameMinLength = 1;
  static const int displayNameMaxLength = 32;
  static const int messageMaxLength = 4000;
  static const int searchMinLength = 2;
  static const int searchMaxLength = 50;

  static bool isValidUsername(String? username) {
    if (username == null || username.isEmpty) return false;
    return _usernameRegex.hasMatch(username);
  }

  static String? usernameError(String? username) {
    if (username == null || username.isEmpty) {
      return 'Username is required';
    }
    if (username.length < usernameMinLength) {
      return 'Username must be at least $usernameMinLength characters';
    }
    if (username.length > usernameMaxLength) {
      return 'Username must be at most $usernameMaxLength characters';
    }
    if (!_usernameRegex.hasMatch(username)) {
      return 'Username can only contain lowercase letters, numbers, and underscores';
    }
    return null;
  }

  static bool isValidDisplayName(String? displayName) {
    if (displayName == null || displayName.isEmpty) return false;
    final sanitized = sanitizeInput(displayName);
    return _displayNameRegex.hasMatch(sanitized);
  }

  static String? displayNameError(String? displayName) {
    if (displayName == null || displayName.isEmpty) {
      return 'Display name is required';
    }
    if (displayName.length < displayNameMinLength) {
      return 'Display name must be at least $displayNameMinLength character';
    }
    if (displayName.length > displayNameMaxLength) {
      return 'Display name must be at most $displayNameMaxLength characters';
    }
    final sanitized = sanitizeInput(displayName);
    if (!_displayNameRegex.hasMatch(sanitized)) {
      return 'Display name can only contain letters, numbers, spaces, and hyphens';
    }
    return null;
  }

  static bool isValidMessage(String? message) {
    if (message == null || message.isEmpty) return false;
    return _messageRegex.hasMatch(message);
  }

  static String? messageError(String? message) {
    if (message == null || message.isEmpty) {
      return 'Message cannot be empty';
    }
    if (message.length > messageMaxLength) {
      return 'Message must be at most $messageMaxLength characters';
    }
    return null;
  }

  static bool isValidSearchQuery(String? query) {
    if (query == null || query.length < searchMinLength) return false;
    return _searchRegex.hasMatch(query);
  }

  static String sanitizeInput(String input) {
    return input.replaceAll(_sanitizationRegex, '');
  }

  static String normalizeUsername(String username) {
    return username.trim().toLowerCase();
  }

  static String normalizeDisplayName(String displayName) {
    final trimmed = displayName.trim();
    return _whitespaceCollapseRegex.allMatches(trimmed).isNotEmpty
        ? trimmed.split(RegExp(r'\s+')).join(' ')
        : trimmed;
  }

  static String truncateMessage(
    String message, {
    int maxLength = messageMaxLength,
  }) {
    if (message.length <= maxLength) return message;
    return '${message.substring(0, maxLength - 3)}...';
  }

  static String formatUsername(String username) {
    return '@$username';
  }
}
