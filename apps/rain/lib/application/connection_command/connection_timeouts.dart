class ConnectionTimeouts {
  const ConnectionTimeouts._();

  static const Duration webRtcDirect = Duration(seconds: 12);
  static const Duration webRtcPrimaryRelay = Duration(seconds: 30);
  static const Duration webRtcBackupRelay = Duration(seconds: 20);
  static const Duration webRtcFullRestart = Duration(seconds: 25);
  static const Duration iroh = Duration(seconds: 25);

  static const Duration globalBudget = Duration(seconds: 90);

  static const Duration retryBaseDelay = Duration(milliseconds: 1200);
  static const Duration retryMaxJitter = Duration(milliseconds: 600);
}
