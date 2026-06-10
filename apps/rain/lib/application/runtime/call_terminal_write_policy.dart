final class CallTerminalWritePolicy {
  const CallTerminalWritePolicy({
    this.maxAttempts = 3,
    this.initialRetryDelay = const Duration(milliseconds: 50),
    this.maxRetryDelay = const Duration(milliseconds: 200),
  }) : assert(maxAttempts > 0);

  final int maxAttempts;
  final Duration initialRetryDelay;
  final Duration maxRetryDelay;

  bool canRetryAfterAttempt(int attempt) => attempt < maxAttempts;

  Duration retryDelayAfterAttempt(int attempt) {
    if (attempt <= 0 || !canRetryAfterAttempt(attempt)) {
      return Duration.zero;
    }
    var delay = initialRetryDelay;
    for (var i = 1; i < attempt; i += 1) {
      delay *= 2;
      if (delay >= maxRetryDelay) {
        return maxRetryDelay;
      }
    }
    return delay > maxRetryDelay ? maxRetryDelay : delay;
  }
}
