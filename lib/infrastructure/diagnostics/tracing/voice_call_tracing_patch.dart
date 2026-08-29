// Patch sketch for voice call mediaConnectionFailed + presence + cleanup.
// Apply to: apps/rain/lib/application/runtime/voice_call_controller.dart (or call_runtime)
// and packages/protocol_brain lib

import 'package:protocol_brain/protocol_brain.dart';

/// 1. SDP creation fix: ensure voice PC creates offer after localMediaReady
/// Before:
///   state = localMediaReady; // stop
/// After:
///   state = localMediaReady;
///   final offer = await pc.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': mediaMode == video});
///   await pc.setLocalDescription(offer);
///   final envelope = await encryptSdp(offer);
///   await voiceAdapter.writeVoiceOffer(callId: callId, caller: self, offer: envelope, updatedAt: now);
///   log.event(category:'call', name:'voice_offer_created', context:{'callId':callId, 'hasSdp': true, 'traceId': traceId});

/// 2. Presence grace: don't fail on expiry if data session still connected
bool shouldFailOnPresenceExpiry({
  required bool presenceOnline,
  required String sessionState, // 'connected' | 'disconnected'
  required Duration timeSinceLastDataMessage,
}) {
  if (presenceOnline) return false;
  if (sessionState == 'connected' && timeSinceLastDataMessage < Duration(seconds: 5)) {
    // split-brain: delay 5s, re-check
    return false; // caller should schedule re-check
  }
  return true;
}

/// 3. Failure taxonomy classifier
enum VoiceFailureTaxonomy {
  sdpMissing,
  sdpExchangeFailed,
  iceGatheringFailed,
  iceTimeout,
  dtlsFailed,
  presenceExpired,
  presenceSplitBrain,
  peerOffline,
  ringingTimeout,
  cleanupTimeout,
  unknown,
}

VoiceFailureTaxonomy classifyFailure({
  required bool hasOffer,
  required bool hasAnswer,
  required int iceWriteCount,
  required int iceReadCount,
  required bool presenceOnline,
  required String sessionState,
  required String? peerConnectionState,
}) {
  if (!hasOffer || !hasAnswer) return VoiceFailureTaxonomy.sdpMissing;
  if (iceWriteCount == 0 && iceReadCount == 0) return VoiceFailureTaxonomy.iceGatheringFailed;
  if (peerConnectionState == 'failed') return VoiceFailureTaxonomy.dtlsFailed;
  if (!presenceOnline && sessionState == 'connected') return VoiceFailureTaxonomy.presenceSplitBrain;
  if (!presenceOnline) return VoiceFailureTaxonomy.presenceExpired;
  return VoiceFailureTaxonomy.unknown;
}

/// 4. Parallel subscription cancel (fix 8s hang)
Future<void> cancelAllParallel(List<StreamSubscription> subs, {Duration timeout = const Duration(milliseconds: 500)}) async {
  await Future.wait(subs.map((s) => s.cancel().timeout(timeout).catchError((_) {})));
  // Log once, not 4 warnings
}

/// 5. Heartbeat jitter + coalesce
Duration heartbeatIntervalWithJitter() {
  // 10s +/- 20% => 8..12s
  final base = 10000;
  final jitter = (base * 0.2).toInt();
  final delta = (DateTime.now().millisecondsSinceEpoch % (jitter * 2)) - jitter;
  return Duration(milliseconds: base + delta);
}
Future<void> coalescedHeartbeat(String username, {required Future<void> Function() sendPresenceUpdate}) async {
  // Skip if last write <8s ago (cache)
  // Otherwise single update with presence + heartbeat fields
}
