/// # voice_call_reconnect_coordinator_test.dart
///
/// Tests VoiceCallReconnectCoordinator which manages voice call reconnection state, including failing only matching live peer calls, marking reconnecting state, and clearing reconnect state through callbacks.
///
/// **Key types:** VoiceCallReconnectCoordinator, VoiceCallState
///
/// **Depends on:** package:rain/application/runtime/voice_call/voice_call_reconnect_coordinator.dart, package:rain/application/runtime/voice_call_state.dart
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:rain/application/runtime/voice_call/voice_call_reconnect_coordinator.dart';
import 'package:rain/application/runtime/voice_call_state.dart';

void main() {
  group('VoiceCallReconnectCoordinator', () {
    const coordinator = VoiceCallReconnectCoordinator.instance;

    test('fails only matching live peer calls', () async {
      final failures = <String>[];
      const current = VoiceCallState(
        phase: VoiceCallPhase.active,
        peerId: 'bob',
        callId: 'call-1',
      );

      coordinator.failVoiceCallForPeer(
        ' Bob ',
        'Network lost.',
        normalizeUsername: (value) => value.trim().toLowerCase(),
        currentState: current,
        failPeer: (peerId, message) async {
          failures.add('$peerId:$message');
        },
      );
      await Future<void>.delayed(Duration.zero);

      coordinator.failVoiceCallForPeer(
        'alice',
        'Network lost.',
        normalizeUsername: (value) => value.trim().toLowerCase(),
        currentState: current,
        failPeer: (peerId, message) async {
          failures.add('$peerId:$message');
        },
      );
      await Future<void>.delayed(Duration.zero);

      expect(failures, <String>['bob:Network lost.']);
    });

    test('marks and clears reconnecting state through callbacks', () {
      final events = <String>[];
      final states = <VoiceCallState>[];
      VoiceCallState? armedCall;
      var cancelCount = 0;
      const current = VoiceCallState(
        phase: VoiceCallPhase.active,
        peerId: 'bob',
        callId: 'call-1',
        sessionEpoch: 7,
      );

      coordinator.markVoiceCallReconnectingForPeer(
        'bob',
        normalizeUsername: (value) => value,
        currentState: current,
        currentSession: null,
        recordRuntimeEvent:
            ({
              required category,
              required name,
              severity = 'info',
              message,
              context = const <String, Object?>{},
            }) {
              events.add(name);
            },
        eventContext: (_) => const <String, Object?>{},
        setVoiceCallState: states.add,
        armReconnectGrace: (state) {
          armedCall = state;
        },
        reconnectingDetail: 'Reconnecting voice call.',
        nowMs: 100,
      );

      expect(events, <String>['media_reconnecting_started']);
      expect(states.single.mediaReconnecting, isTrue);
      expect(states.single.reconnectingSince, 100);
      expect(armedCall?.updatedAt, 100);

      coordinator.clearVoiceCallReconnectingForPeer(
        'bob',
        normalizeUsername: (value) => value,
        currentState: states.single,
        currentSession: null,
        recordRuntimeEvent:
            ({
              required category,
              required name,
              severity = 'info',
              message,
              context = const <String, Object?>{},
            }) {
              events.add(name);
            },
        eventContext: (_) => const <String, Object?>{},
        setVoiceCallState: states.add,
        cancelReconnectGrace: () {
          cancelCount++;
        },
        nowMs: 120,
      );

      expect(events.last, 'media_reconnecting_cleared');
      expect(cancelCount, 1);
      expect(states.last.mediaReconnecting, isFalse);
      expect(states.last.reconnectingSince, isNull);
      expect(states.last.updatedAt, 120);
    });

    test(
      'reconnect grace timer fails still-reconnecting active call',
      () async {
        Timer? timer;
        final failures = <String>[];
        var current = const VoiceCallState(
          phase: VoiceCallPhase.active,
          peerId: 'bob',
          callId: 'call-1',
          sessionEpoch: 7,
          mediaReconnecting: true,
        );

        coordinator.armVoiceCallReconnectGrace(
          current,
          gracePeriod: const Duration(milliseconds: 1),
          reconnectGraceTimer: timer,
          setReconnectGraceTimer: (value) {
            timer = value;
          },
          currentState: () => current,
          failPeer: (peerId, message) async {
            failures.add('$peerId:$message');
          },
          networkLostMessage: 'Network lost.',
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(failures, <String>['bob:Network lost.']);

        current = current.copyWith(mediaReconnecting: false);
        coordinator.armVoiceCallReconnectGrace(
          current.copyWith(mediaReconnecting: true),
          gracePeriod: const Duration(milliseconds: 1),
          reconnectGraceTimer: timer,
          setReconnectGraceTimer: (value) {
            timer = value;
          },
          currentState: () => current,
          failPeer: (peerId, message) async {
            failures.add('$peerId:$message');
          },
          networkLostMessage: 'Network lost.',
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(failures, <String>['bob:Network lost.']);
        timer?.cancel();
      },
    );

    test('cancel clears and cancels reconnect grace timer', () async {
      var fired = false;
      Timer? timer = Timer(const Duration(milliseconds: 1), () {
        fired = true;
      });

      coordinator.cancelVoiceCallReconnectGrace(
        reconnectGraceTimer: timer,
        setReconnectGraceTimer: (value) {
          timer = value;
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(timer, isNull);
      expect(fired, isFalse);
    });
  });
}
