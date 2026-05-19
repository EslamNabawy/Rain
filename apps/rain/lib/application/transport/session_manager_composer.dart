import 'package:protocol_brain/protocol_brain.dart';

import 'fallback_session_manager.dart';

SessionManager composeSessionManager({
  required SessionManager webRtc,
  required SessionManager? iroh,
  required bool enableIrohFallback,
  required Duration connectTimeout,
}) {
  if (!enableIrohFallback || iroh == null) {
    return webRtc;
  }

  return FallbackSessionManager(
    webRtc: webRtc,
    iroh: iroh,
    webRtcConnectTimeout: connectTimeout,
    irohConnectTimeout: connectTimeout,
  );
}
