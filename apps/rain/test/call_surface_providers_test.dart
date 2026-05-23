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
    expect(harness.surface.dock, CallSurfaceDock.chatCenter);
    expect(harness.surface.peerId, 'bob');
    expect(harness.surface.callId, 'call-1');
  });

  test('new outgoing call expands the call surface', () {
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
    expect(harness.surface.dock, CallSurfaceDock.chatCenter);
    expect(harness.surface.callId, 'call-2');
  });

  test('active call can minimize and stays minimized for the same call', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall());
    harness.container.read(callSurfaceProvider.notifier).minimize();

    expect(harness.surface.mode, CallSurfaceMode.minimized);
    expect(harness.surface.dock, CallSurfaceDock.bottomSafe);

    harness.setVoiceCall(_voiceCall(updatedAt: 2));

    expect(harness.surface.isVisible, isTrue);
    expect(harness.surface.mode, CallSurfaceMode.minimized);
    expect(harness.surface.dock, CallSurfaceDock.bottomSafe);
    expect(harness.surface.callId, 'call-1');
  });

  test('failed and ended calls clear the call surface state', () {
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

    expect(harness.surface, const CallSurfaceState.hidden());

    harness.setVoiceCall(_voiceCall());
    harness.setVoiceCall(const VoiceCallState.idle());

    expect(harness.surface, const CallSurfaceState.hidden());
  });

  test('call surface controls never mutate the voice call state', () {
    final harness = _CallSurfaceHarness();
    addTearDown(harness.dispose);

    harness.setVoiceCall(_voiceCall());
    final before = harness.voiceCall;

    harness.container.read(callSurfaceProvider.notifier).minimize();
    harness.container
        .read(callSurfaceProvider.notifier)
        .expand(dock: CallSurfaceDock.chatTop);

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
    expect(harness.surface.mode, CallSurfaceMode.minimized);
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
}) {
  return VoiceCallState(
    phase: phase,
    peerId: peerId,
    callId: callId,
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
