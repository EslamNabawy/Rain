# Tracing Implementation Guide — How to Wire

This guide shows where to copy scaffold files from `D:\Software Projects\Rain\lib\infrastructure\diagnostics\tracing\` into real repo `apps/rain/lib/...` and minimal wiring.

## 1. Copy files

Source: `D:\Software Projects\Rain\lib\infrastructure\diagnostics\tracing\`

Destination: `apps/rain/lib/infrastructure/diagnostics/tracing/`

- `trace_context.dart` -> same
- `interaction_logger.dart` -> same
- `app_navigation_observer.dart` -> same
- `throttled_provider_observer.dart` -> replace observer registration in `main.dart`
- `voice_call_tracing_patch.dart` -> reference for edits, not copied as-is

## 2. Wire in `main.dart`

```dart
void main() {
  final diagnostics = CrashDiagnosticsService(...);
  final log = CrashDiagnosticsDebugLogService(diagnostics: diagnostics, enabled: true);

  // Throttled observer replaces RainDebugProviderObserver
  final observer = ThrottledProviderObserver(log);

  runApp(
    ProviderScope(
      observers: [observer],
      child: InteractionLogger(
        log: log,
        child: MaterialApp(
          navigatorObservers: [AppNavigationObserver(log)],
          ...
        ),
      ),
    ),
  );
}
```

Add `trace_context.dart` import to `identity_providers.dart`, `call_runtime`, `connection_manager`.

## 3. Add traceId to key flows

### Register flow (`identity_providers.dart:147`)
```dart
Future<void> register(String username, String password) async {
  final trace = TraceContext.create();
  return TraceContext.runAsync(trace, () async {
    InteractionTrace.tap(ref.read(logProvider), 'onboarding_submit_button', context: {'username': username});
    log.event(category:'auth', name:'register_started', context:{...trace.toContext(), 'username': username});
    try {
      await _inner.register(username, password);
      log.event(category:'auth', name:'register_success', context: trace.toContext());
    } catch (e, st) {
      log.error(e, st, source:'signaling.register', context: trace.toContext());
      // Show suggestion dialog if "already taken or locked"
      rethrow;
    }
  });
}
```

### Call flow (`call_runtime` / `voice_call_controller.dart`)
```dart
final trace = TraceContext.create();
log.event(category:'call', name:'start_requested', context:{...trace.toContext(), 'peerId': peerId, 'mediaMode': 'audio'});
final room = await tracedCall(trace, () => signaling.createOutgoingCall(...));
// After localMediaReady:
final offer = await pc.createOffer(...);
await pc.setLocalDescription(offer);
await signaling.writeVoiceOffer(...);
log.event(category:'call', name:'voice_offer_created', context:{...trace.toContext(), 'hasOffer': true});
```

## 4. Presence fix

In `connection_manager.dart` where `watchPresence` triggers `end_for_peer_requested`:

```dart
watchPresence(peerId).listen((online) async {
  if (!online) {
    final sessionState = ref.read(connectionState).sessionState; // 'connected'?
    if (!shouldFailOnPresenceExpiry(presenceOnline: online, sessionState: sessionState, timeSinceLastDataMessage: timeSinceLastChat)) {
      log.event(category:'connection', name:'presence_split_brain_delayed', context: {'peerId': peerId, ...trace.toContext()});
      await Future.delayed(Duration(seconds: 5));
      // re-check
      return;
    }
    // proceed to endCall with taxonomy presenceExpired
  }
});
```

## 5. Fix cleanup hang

In `voice_call_controller.dart` where `voice_signaling_subscription_cancel_timeout` logs:

Replace sequential loop:
```dart
for (final s in subs) await s.cancel().timeout(Duration(seconds:2));
```
With:
```dart
await cancelAllParallel(subs, timeout: Duration(milliseconds:500));
```

## 6. Verify

1. Tap onboarding submit -> diagnostics json contains `interaction/tap` + `auth/register_started` same traceId.
2. Make audio call -> `voice_offer_created` appears, `iceCandidateWriteCount >0`, `watchVoiceOffer` fires, call reaches `connected`.
3. Kill peer app 35s -> presence offline but `presence_split_brain_delayed` logged, call not failed immediately.
4. Hangup -> no `voice_signaling_subscription_cancel_timeout` warning, cancel <600ms.
5. Diagnostics export size ~200-300KB, share works.

## 7. Next PRs

- PR1: tracing scaffold + observer throttle + navigation (no logic change)
- PR2: voice SDP + failure taxonomy + presence grace
- PR3: interaction tap wiring on onboarding + call buttons
- Each PR adds test: `traceId` propagation, `tap` event, `sdp_missing` taxonomy.
