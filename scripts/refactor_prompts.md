# Voice Call Runtime Refactor — Codex Prompts

## PROMPT 1: Create voice_call/ directory + Recreate VoiceCallStateCoordinator

Fix a missing file in the Rain Flutter project at C:\Users\eslam\OneDrive\Desktop\GoodStuff\Rain, branch dev. You have FULL autonomy. Do not ask questions. Just do it.

### CONTEXT

The file voice_call_runtime.dart references VoiceCallStateCoordinator.instance in 14 places but the class file doesn't exist. There IS a test file at apps/rain/test/voice_call_state_coordinator_test.dart that validates the expected behavior. The test expects the class at: package:rain/application/runtime/voice_call/voice_call_state_coordinator.dart

Also, the rain_runtime_controller.dart imports 'voice_call/voice_call_state_coordinator.dart' but the voice_call/ directory doesn't exist yet. Other extracted coordinators (VoiceCallRoomCoordinator, VoiceCallErrorCoordinator) are sitting directly in the runtime/ directory — they should be moved into voice_call/ too.

Also, VoiceCallErrorCoordinator references VoiceCallStateCoordinator and needs to import it via the voice_call/ path.

### YOUR TASK

#### Step 1: Create the voice_call/ directory and move existing coordinators
```powershell
mkdir apps\rain\lib\application\runtime\voice_call\
# Move these files (NOT copy — move):
#   voice_call_room_coordinator.dart -> voice_call/voice_call_room_coordinator.dart
#   voice_call_error_coordinator.dart -> voice_call/voice_call_error_coordinator.dart
#   voice_call_diagnostics.dart -> voice_call/voice_call_diagnostics.dart
#   voice_call_terminal_reconciler.dart -> voice_call/voice_call_terminal_reconciler.dart
```

Update all import paths that reference the moved files. Key files that import them:
- rain_runtime_controller.dart (lines ~25-31)
- voice_call_runtime.dart (grep for the filenames)

#### Step 2: Create VoiceCallStateCoordinator
Create: apps/rain/lib/application/runtime/voice_call/voice_call_state_coordinator.dart

This is a STATLESS coordinator class (singleton instance pattern). Read the test file at apps/rain/test/voice_call_state_coordinator_test.dart to understand the exact API surface.

Required method signatures (from the 14 call sites in voice_call_runtime.dart + the test file):

1. startPreflightState(VoiceCallState state, {required Duration expiry, required int nowMs}) → VoiceCallState
   - If state is locally expired (nowMs >= state.sessionEpoch + expiry.inMilliseconds), return VoiceCallState.idle()
   - Otherwise return state unchanged

2. isLocallyExpiredStartBlock(VoiceCallState state, {required Duration expiry, required int nowMs}) → bool
   - Returns true if state has a sessionEpoch and nowMs >= sessionEpoch + expiry.inMilliseconds

3. canClearExpiredStartBlock(VoiceCallPhase phase) → bool
   - Returns true if phase is one of: connectingMedia, outgoingRinging, incomingRinging, active

4. mapSessionPhase(VoiceCallSessionPhase phase) → VoiceCallPhase
   - Straight mapping: connectingMedia→connectingMedia, outgoingRinging→outgoingRinging, incomingRinging→incomingRinging, active→active, ending→ending, ended→ended, failed→failed

5. failureReasonForSessionState(VoiceCallSessionState state, {required VoiceCallFailureReason? Function(Object) localMediaFailureReason}) → VoiceCallFailureReason?

6. detailForSessionState(VoiceCallSessionState state, {required String? Function(Object) localMediaFailureDetail, required String Function(Object) errorMessage}) → String?

7. preflightDetail(CallMediaMode mediaMode) → String
   - audio → "Checking microphone permission."
   - video → "Checking camera and microphone permission."

8. isRemoteMediaPermissionCode(String? reasonCode) → bool
9. remoteMediaPermissionFailure(String? reasonCode) → VoiceCallFailureReason
10. remoteMediaPermissionDetail(String? reasonCode) → String

11. stateAfterTerminalWriteFailure(VoiceCallState current, {Object? error, required int nowMs}) → VoiceCallState
    - Sets phase to failed, detail to "Could not notify peer that the call ended. Try again."
    - Sets failureReason to signalingFailed
    - Resets volatile flags: isCameraMuted=false, isDeafened=false, isRemoteCameraMuted=false, hasLocalVideo=false, hasRemoteVideo=false, videoFirstFrameTimedOut=false, mediaReconnecting=false, outputRoute=systemDefault
    - updatedAt = nowMs, clears outputRouteWarning, outputRouteTarget, reconnectingSince

12. isSameLiveSessionState(VoiceCallState latest, {required bool runtimeShutDown, required bool ownsRuntimeSession, String? callId, int? sessionEpoch}) → bool
    - Returns false if runtimeShutDown or !ownsRuntimeSession
    - Returns true if latest.callId == callId && latest.sessionEpoch == sessionEpoch && latest.phase != idle && latest.phase != failed

13. isSameLiveState(VoiceCallState latest, VoiceCallState expected) → bool
    - Returns true if latest.callId == expected.callId && latest.sessionEpoch == expected.sessionEpoch && latest.phase != idle && latest.phase != failed

14. stateAfterLocalEnd(VoiceCallState current, {required String detail, VoiceCallFailureReason? failureReason, String? failureDetail, required int nowMs}) → VoiceCallState
    - If failureReason is null, return VoiceCallState.idle()
    - Otherwise: phase=failed, detail=failureDetail ?? detail, failureReason=failureReason
    - Reset same volatile fields as stateAfterTerminalWriteFailure

The class should:
- Be a `final class` with `const` constructor
- Have `static const VoiceCallStateCoordinator.instance = VoiceCallStateCoordinator()`
- Follow the exact same pattern as VoiceCallRoomCoordinator and VoiceCallErrorCoordinator

For the implementation logic in methods 5, 6, 8, 9, 10 — read CallErrorClassifier from package:rain/application/runtime/call_error_classifier.dart for the error code constants and mapping logic.

#### Step 3: Update import in voice_call_runtime.dart
Since it's a `part of` file, the coordinator classes accessed via their singleton instances should be resolved through the parent file's imports. Verify that rain_runtime_controller.dart imports voice_call/voice_call_state_coordinator.dart (it already does based on our check).

But also update the import for voice_call_room_coordinator and voice_call_error_coordinator in rain_runtime_controller.dart to use the voice_call/ prefix path.

#### Step 4: Verify
Run: cd apps/rain && dart analyze
Must get ZERO errors. Only warnings acceptable.
If errors, fix immediately.

#### Step 5: Run tests
Run: dart run melos run test
All tests must pass. If voice_call_state_coordinator_test.dart fails, fix the implementation.

#### Step 6: Commit and push
- Stage all changed files
- Commit: "Phase 3a: Create voice_call/ directory, move coordinators, recreate VoiceCallStateCoordinator"
- Push to origin/dev
- Trigger CI: gh workflow run ci.yml --ref dev
- Report CI status when done

GO.

---

## PROMPT 2: Extract VoiceCallReconnectCoordinator + PreflightCoordinator

Extract two more coordinators from voice_call_runtime.dart in the Rain Flutter project at C:\Users\eslam\OneDrive\Desktop\GoodStuff/Rain, branch dev. FULL autonomy. Just do it.

### CONTEXT
voice_call_runtime.dart is ~4,511 lines. Previous prompt already created VoiceCallStateCoordinator and moved existing coordinators into voice_call/ subdir. VoiceCallErrorCoordinator, VoiceCallRoomCoordinator, and VoiceCallStateCoordinator are all at apps/rain/lib/application/runtime/voice_call/.

### YOUR TASK

#### Extraction 1: VoiceCallReconnectCoordinator
Create: apps/rain/lib/application/runtime/voice_call/voice_call_reconnect_coordinator.dart

Extract these methods from voice_call_runtime.dart:
- _failVoiceCallForPeer (line ~3886) — marks peer as failed
- _markVoiceCallReconnectingForPeer (line ~3906) — marks peer reconnecting
- _clearVoiceCallReconnectingForPeer (line ~3938) — clears reconnecting state
- _armVoiceCallReconnectGrace (line ~3965) — arms reconnect grace timer
- _cancelVoiceCallReconnectGrace (line ~3996) — cancels grace timer

These manage reconnect grace timers and state. They access private fields on RainRuntimeController. Pass these as function parameters following the coordinator pattern.

The coordinator needs:
- failVoiceCallForPeer(String peerId, String message, {required Map<String, VoiceCallState> voiceCallStateByPeerId, required void Function(String, VoiceCallState) setVoiceCallState, required Future<void> Function() reloadContactIfNeeded})
- markVoiceCallReconnectingForPeer(String peerId, {required Map<String, VoiceCallState> voiceCallStateByPeerId, required void Function(String, VoiceCallState) setVoiceCallState})
- clearVoiceCallReconnectingForPeer(String peerId, {required Map<String, VoiceCallState> voiceCallStateByPeerId, required void Function(String, VoiceCallState) setVoiceCallState})
- armVoiceCallReconnectGrace(VoiceCallState call, {required Map<String, Timer?> reconnectGraceTimerByCallId, required void Function() cancelReconnectGrace, required Duration gracePeriod, required Future<void> Function(String peerId, String message) failPeer, required Future<void> Function(String peerId) markReconnectingPeer})
- cancelVoiceCallReconnectGrace({required Map<String, Timer?> reconnectGraceTimerByCallId, required void Function() cancelReconnectGrace})

WAIT — do NOT over-abstract. Instead, read each method carefully, understand exactly what private fields it touches, and design the function parameters to match. The key principle: the coordinator is stateless, all mutable state comes via params.

#### Extraction 2: VoiceCallPreflightCoordinator
Create: apps/rain/lib/application/runtime/voice_call/voice_call_preflight_coordinator.dart

Extract these methods from voice_call_runtime.dart:
- _assertVoiceCallCanStart (line ~4059)
- _assertVoiceCallPeerIsFriend (line ~4065)
- _fetchVoiceCallPeerPresence (line ~4078)
- _canReplaceVoiceCallWithRetry (line ~1044)
- _replaceStaleVoiceCallForRetry (line ~1049)

These handle call-start validation and presence checking. Same pattern: stateless coordinator, pass runtime dependencies as function params.

#### Step 3: Replace with thin delegation
In voice_call_runtime.dart, replace each extracted method body with a delegation call to the corresponding coordinator instance.

#### Step 4: Add imports to rain_runtime_controller.dart
Add: import 'voice_call/voice_call_reconnect_coordinator.dart';
Add: import 'voice_call/voice_call_preflight_coordinator.dart';

#### Step 5: Verify
- dart analyze: zero errors
- melos test: all pass
- Commit: "Phase 3b: Extract VoiceCallReconnectCoordinator and VoiceCallPreflightCoordinator"
- Push to origin/dev
- Trigger CI: gh workflow run ci.yml --ref dev
- Report CI status

GO.

---

## PROMPT 3: Extract Media Coordination + Session State + Signaling Cleanup

Extract three more coordinators from voice_call_runtime.dart in the Rain Flutter project at C:\Users\eslam\OneDrive\Desktop\GoodStuff/Rain, branch dev. FULL autonomy. Just do it.

### CONTEXT
voice_call_runtime.dart is still very large. Previous prompts extracted VoiceCallRoomCoordinator, VoiceCallErrorCoordinator, VoiceCallStateCoordinator, VoiceCallReconnectCoordinator, VoiceCallPreflightCoordinator. All are in voice_call/ subdir. Move all remaining suitable method groups into coordinators to get the file under 2,500 lines.

### YOUR TASK

#### Extraction 1: VoiceCallMediaCoordinator
Create: apps/rain/lib/application/runtime/voice_call/voice_call_media_coordinator.dart

Extract media lifecycle methods:
- _handleVideoRendererState (line ~3029)
- _handleVideoRendererFailure (line ~3081)
- _handleVoiceCallAppLifecycleState (line ~3152)
- _setVideoCallCameraMutedInSignaling (line ~3210)
- _disposeVideoCallResources (line ~3228)
- _createVideoVoiceMediaConnection (line ~2955)
- _createAudioVoiceMediaConnection (line ~3005)
- _createVoiceCallSession (line ~1100) — only if it's primarily about media setup, otherwise leave it

#### Extraction 2: VoiceCallSessionStateCoordinator
Create: apps/rain/lib/application/runtime/voice_call/voice_call_session_state_coordinator.dart

Extract session state mapping methods:
- _applyVoiceSessionState (line ~2242) — large method (~140 lines), maps session events to runtime state
- _finalizeFailedVoiceCallSession (line ~2388)
- _recordVoiceCallSessionFailure (line ~2451)
- _recordVoiceCallRuntimeFailure (line ~2492)
- _recordVoiceCallStartFailureDiagnostics (line ~2521)
- _recordVoiceCallDiagnostics (line ~2558)
- _recordPeerUiStateSplitIfNeeded (line ~4355)

#### Extraction 3: VoiceCallSignalingCleanupCoordinator
Create: apps/rain/lib/application/runtime/voice_call/voice_call_signaling_cleanup_coordinator.dart

Extract signaling lifecycle methods:
- _cleanupStaleVoiceCallArtifacts (line ~3275)
- _cancelVoiceSignalingSubscriptions (line ~3333)
- _endVoiceCallInSignaling (line ~3350)
- _recordVoiceSignalingError (line ~3309)
- _recordVoiceRoomStatusTransition (line ~3442)
- _voiceRoomStatusTimeline (line ~3464)
- _recordTerminalAlreadyClosed (line ~3489)
- _isDurableVoiceCallTerminalStateError (line ~3470)
- _isVoiceTerminalAlreadyClosedError (line ~3476)
- _isVoiceTerminalAlreadyClosedMessage (line ~3482)

#### Step 4: Replace with delegation
In voice_call_runtime.dart replace each extracted method with thin delegation.

#### Step 5: Add imports to rain_runtime_controller.dart
Add imports for all 3 new coordinators.

#### Step 6: Verify
- dart analyze: zero errors
- melos test: all pass  
- Check line count: wc -l apps/rain/lib/application/runtime/voice_call_runtime.dart — should be under 3,000
- Commit: "Phase 3c: Extract MediaCoordinator, SessionStateCoordinator, SignalingCleanupCoordinator"
- Push to origin/dev
- Trigger CI
- Report CI status and final line count

GO.

---

## PROMPT 4: Convert part-of → imports + Final Cleanup

Convert part-of extensions to proper imports across the Rain runtime files at C:\Users\eslam\OneDrive\Desktop\GoodStuff/Rain, branch dev. FULL autonomy. Just do it.

### CONTEXT
These files currently use `part of 'rain_runtime_controller.dart'`:
- voice_call_runtime.dart
- connection_request_runtime.dart
- file_transfer_runtime.dart
- friend_runtime.dart

The voice_call_runtime.dart file should now be much smaller after previous extraction phases. The goal is to convert ALL four files from `part of` to proper Dart files with imports, and remove the `part` directives from rain_runtime_controller.dart.

### YOUR TASK

#### Step 1: Analyze what private members each part-of file accesses
For each file, search for references to private members of RainRuntimeController (members starting with _):
```powershell
grep -n "\(this\.\)\?_[a-zA-Z]" apps/rain/lib/application/runtime/voice_call_runtime.dart | head -50
grep -n "\(this\.\)\?_[a-zA-Z]" apps/rain/lib/application/runtime/connection_request_runtime.dart | head -50
grep -n "\(this\.\)\?_[a-zA-Z]" apps/rain/lib/application/runtime/file_transfer_runtime.dart | head -50
grep -n "\(this\.\)\?_[a-zA-Z]" apps/rain/lib/application/runtime/friend_runtime.dart | head -50
```

#### Step 2: Create public API on RainRuntimeController
For each private member accessed by multiple part-of files, create a public getter/method on rain_runtime_controller.dart instead of making the field public. Keep encapsulation.

Example:
```dart
// Instead of exposing _voiceCallState directly:
VoiceCallState get voiceCallState => _voiceCallState;
set voiceCallState(VoiceCallState value) => _voiceCallState = value;
```

For members only used by one file, consider moving the logic entirely out of RainRuntimeController.

#### Step 3: Convert each part-of file
For each file:
1. Replace `part of 'rain_runtime_controller.dart';` with `import 'package:rain/application/runtime/rain_runtime_controller.dart';` (and any other needed imports)
2. Update the extension/class to not reference `this.` for RainRuntimeController members — instead receive the controller instance as a parameter or access via the now-public getters
3. Alternative approach: since these are all extension methods ON RainRuntimeController, keep them as extensions but convert from `part of` to proper extension files with imports: `extension VoiceCallRuntime on RainRuntimeController { ... }`

The extensions approach is better — just convert:
- `part of 'rain_runtime_controller.dart';` → remove
- Add: `import 'package:rain/application/runtime/rain_runtime_controller.dart';`
- Extension methods keep their `this.` references
- For private members accessed via `this._privateField`, add public getters on RainRuntimeController

#### Step 4: Update rain_runtime_controller.dart
Remove the `part` directives for the four files. Add the public getters needed by the extensions.

#### Step 5: Verify everything
- dart analyze: zero errors across all packages
- melos test: all pass
- dart format all changed files
- Commit: "Phase 4: Convert runtime extensions from part-of to proper imports"
- Push to origin/dev
- Trigger CI
- Report final CI status and line counts

GO.
