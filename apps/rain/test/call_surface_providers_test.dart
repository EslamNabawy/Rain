import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/call_surface_providers.dart';

void main() {
  test('new incoming call expands the call surface', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    expect(harness.surface.isVisible, isFalse);

    harness.setVoiceCall(
      _voiceCall(phase: VoiceCallPhase.incomingRinging, isOutgoing: false),
    );

    expect(harness.surface.isVisible, isTrue);
    expect(harness.surface.mode, CallSurfaceMode.expanded);
    expect(harness.surface.restoreMode, CallSurfaceMode.expanded);
    expect(harness.surface.mediaMode, CallMediaMode.audio);
    expect(harness.surface.peerId, 'bob');
    expect(harness.surface.callId, 'call-1');
  });

  test('new outgoing call expands and resets older surface mode', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall());
    harness.container.read(callSurfaceProvider.notifier).minimize();

    harness.setVoiceCall(
      _voiceCall(
        phase: VoiceCallPhase.outgoingRinging,
        callId: 'call-2',
        isOutgoing: true,
      ),
    );

    expect(harness.surface.isVisible, isTrue);
    expect(harness.surface.mode, CallSurfaceMode.expanded);
    expect(harness.surface.restoreMode, CallSurfaceMode.expanded);
    expect(harness.surface.callId, 'call-2');
  });

  test('voice call minimize becomes manager-only and restores expanded', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall());
    harness.container.read(callSurfaceProvider.notifier).minimize();

    expect(harness.surface.mode, CallSurfaceMode.managerOnly);
    expect(harness.surface.restoreMode, CallSurfaceMode.expanded);
    expect(harness.surface.hasMediaPanel, isFalse);

    harness.setVoiceCall(_voiceCall(updatedAt: 2));

    expect(harness.surface.isVisible, isTrue);
    expect(harness.surface.mode, CallSurfaceMode.managerOnly);
    expect(harness.surface.restoreMode, CallSurfaceMode.expanded);
    expect(harness.surface.callId, 'call-1');

    harness.container.read(callSurfaceProvider.notifier).restore();

    expect(harness.surface.mode, CallSurfaceMode.expanded);
    expect(harness.surface.hasMediaPanel, isTrue);
  });

  test('video call minimize moves through pip then manager-only', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall(mediaMode: CallMediaMode.video));

    harness.container.read(callSurfaceProvider.notifier).minimize();

    expect(harness.surface.mode, CallSurfaceMode.pip);
    expect(harness.surface.restoreMode, CallSurfaceMode.pip);
    expect(harness.surface.hasMediaPanel, isTrue);

    harness.container.read(callSurfaceProvider.notifier).minimize();

    expect(harness.surface.mode, CallSurfaceMode.managerOnly);
    expect(harness.surface.restoreMode, CallSurfaceMode.pip);
    expect(harness.surface.hasMediaPanel, isFalse);

    harness.container.read(callSurfaceProvider.notifier).restore();

    expect(harness.surface.mode, CallSurfaceMode.pip);
  });

  test('fullscreen returns to the previous useful video mode', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall(mediaMode: CallMediaMode.video));

    harness.container.read(callSurfaceProvider.notifier).enterFullscreen();

    expect(harness.surface.mode, CallSurfaceMode.fullscreen);
    expect(harness.surface.restoreMode, CallSurfaceMode.expanded);

    harness.container.read(callSurfaceProvider.notifier).exitFullscreen();

    expect(harness.surface.mode, CallSurfaceMode.expanded);

    harness.container.read(callSurfaceProvider.notifier).minimize();
    harness.container.read(callSurfaceProvider.notifier).enterFullscreen();
    harness.container.read(callSurfaceProvider.notifier).restore();

    expect(harness.surface.mode, CallSurfaceMode.pip);
  });

  test('back intent exits fullscreen before minimizing video', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall(mediaMode: CallMediaMode.video));
    final controller = harness.container.read(callSurfaceProvider.notifier);

    controller.enterFullscreen();

    expect(harness.surface.mode, CallSurfaceMode.fullscreen);
    expect(controller.handleBackIntent(), isTrue);
    expect(harness.surface.mode, CallSurfaceMode.expanded);

    expect(controller.handleBackIntent(), isTrue);
    expect(harness.surface.mode, CallSurfaceMode.pip);

    expect(controller.handleBackIntent(), isTrue);
    expect(harness.surface.mode, CallSurfaceMode.managerOnly);

    expect(controller.handleBackIntent(), isFalse);
    expect(harness.surface.mode, CallSurfaceMode.managerOnly);
  });

  test('back intent minimizes voice calls to manager only', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall());
    final controller = harness.container.read(callSurfaceProvider.notifier);

    expect(controller.handleBackIntent(), isTrue);
    expect(harness.surface.mode, CallSurfaceMode.managerOnly);

    expect(controller.handleBackIntent(), isFalse);
    expect(harness.surface.mode, CallSurfaceMode.managerOnly);
  });

  test('failed call expands for action and ended call clears the surface', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall());
    harness.container.read(callSurfaceProvider.notifier).minimize();

    harness.setVoiceCall(
      _voiceCall(
        phase: VoiceCallPhase.failed,
        failureReason: VoiceCallFailureReason.mediaConnectionFailed,
      ),
    );

    expect(harness.surface.isVisible, isTrue);
    expect(harness.surface.mode, CallSurfaceMode.expanded);
    expect(harness.surface.restoreMode, CallSurfaceMode.expanded);
    expect(harness.surface.callId, 'call-1');

    harness.setVoiceCall(_voiceCall());
    harness.setVoiceCall(const VoiceCallState.idle());

    expect(harness.surface, const CallSurfaceState.hidden());
  });

  test('audio call strips video-only pip and fullscreen modes', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall(mediaMode: CallMediaMode.video));
    harness.container.read(callSurfaceProvider.notifier).minimize();

    expect(harness.surface.mode, CallSurfaceMode.pip);

    harness.setVoiceCall(_voiceCall(mediaMode: CallMediaMode.audio));

    expect(harness.surface.mode, CallSurfaceMode.expanded);
    expect(harness.surface.restoreMode, CallSurfaceMode.expanded);
    expect(harness.surface.mediaMode, CallMediaMode.audio);
  });

  test('call surface controls never mutate the voice call state', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall(mediaMode: CallMediaMode.video));
    final before = harness.voiceCall;

    harness.container.read(callSurfaceProvider.notifier).minimize();
    harness.container.read(callSurfaceProvider.notifier).enterFullscreen();
    harness.container.read(callSurfaceProvider.notifier).exitFullscreen();
    harness.container.read(callSurfaceProvider.notifier).expand();

    expect(identical(harness.voiceCall, before), isTrue);
    expect(harness.voiceCall.phase, VoiceCallPhase.active);
    expect(harness.voiceCall.callId, 'call-1');
  });

  test('switching selected chat does not hide the active call surface', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall());
    harness.container.read(callSurfaceProvider.notifier).minimize();

    harness.container.read(_selectedChatProvider.notifier).set('alice');

    expect(harness.surface.isVisible, isTrue);
    expect(harness.surface.mode, CallSurfaceMode.managerOnly);
    expect(harness.surface.peerId, 'bob');
  });
}

final _testVoiceCallProvider =
    NotifierProvider<_TestVoiceCallController, VoiceCallState>(
      _TestVoiceCallController.new,
    );

final _selectedChatProvider =
    NotifierProvider<_SelectedChatController, String?>(
      _SelectedChatController.new,
    );

VoiceCallState _voiceCall({
  VoiceCallPhase phase = VoiceCallPhase.active,
  String peerId = 'bob',
  String callId = 'call-1',
  bool isOutgoing = false,
  int updatedAt = 1,
  VoiceCallFailureReason? failureReason,
  CallMediaMode mediaMode = CallMediaMode.audio,
}) {
  return VoiceCallState(
    phase: phase,
    peerId: peerId,
    callId: callId,
    mediaMode: mediaMode,
    isOutgoing: isOutgoing,
    startedAt: phase == VoiceCallPhase.active ? 1 : null,
    updatedAt: updatedAt,
    failureReason: failureReason,
  );
}

class _CallSurfaceHarness {
  _CallSurfaceHarness() {
    container = ProviderContainer(
      overrides: [
        voiceCallStateForCallSurfaceProvider.overrideWith(
          (Ref ref) => ref.watch(_testVoiceCallProvider),
        ),
      ],
    );
  }

  late final ProviderContainer container;

  VoiceCallState get voiceCall => container.read(_testVoiceCallProvider);

  CallSurfaceState get surface => container.read(callSurfaceProvider);

  void setVoiceCall(VoiceCallState state) {
    container.read(_testVoiceCallProvider.notifier).set(state);
  }

  void dispose() => container.dispose();
}

class _TestVoiceCallController extends Notifier<VoiceCallState> {
  @override
  VoiceCallState build() => const VoiceCallState.idle();

  void set(VoiceCallState next) => state = next;
}

class _SelectedChatController extends Notifier<String?> {
  @override
  String? build() => 'bob';

  void set(String? next) => state = next;
}
