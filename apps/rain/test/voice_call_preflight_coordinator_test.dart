/// # voice_call_preflight_coordinator_test.dart
///
/// Tests VoiceCallPreflightCoordinator which validates preconditions before starting a voice call, including peer connection availability, friend relationship checks, and presence snapshot resolution.
///
/// **Key types:** VoiceCallPreflightCoordinator
///
/// **Depends on:** package:rain/application/runtime/voice_call/voice_call_preflight_coordinator.dart, package:rain/application/runtime/voice_call_state.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:rain/application/runtime/voice_call/voice_call_preflight_coordinator.dart';
import 'package:rain/application/runtime/voice_call_state.dart';

void main() {
  group('VoiceCallPreflightCoordinator', () {
    const coordinator = VoiceCallPreflightCoordinator.instance;

    test('throws when peer connection is unavailable', () {
      expect(
        () =>
            coordinator.assertVoiceCallCanStart(peerConnectionAvailable: false),
        throwsStateError,
      );
    });

    test('syncs relationships once before rejecting non-friend peer', () async {
      var syncCount = 0;
      var friend = false;

      await expectLater(
        coordinator.assertVoiceCallPeerIsFriend(
          'bob',
          isAcceptedFriend: (_) async => friend,
          syncRelationships: (_) async {
            syncCount++;
          },
        ),
        throwsStateError,
      );

      expect(syncCount, 1);

      friend = true;
      await coordinator.assertVoiceCallPeerIsFriend(
        'bob',
        isAcceptedFriend: (_) async => friend,
        syncRelationships: (_) async {
          syncCount++;
        },
      );
      expect(syncCount, 1);
    });

    test(
      'returns unknown presence snapshot and records nonfatal error',
      () async {
        final events = <Map<String, Object?>>[];
        final errors = <Object>[];

        final snapshot = await coordinator.fetchVoiceCallPeerPresence(
          ' Bob ',
          mediaMode: CallMediaMode.audio,
          normalizeUsername: (value) => value.trim().toLowerCase(),
          fetchPresence: (_, {required String action}) {
            throw StateError('backend unavailable');
          },
          recordRuntimeEvent:
              ({
                required category,
                required name,
                severity = 'info',
                message,
                context = const <String, Object?>{},
              }) {
                events.add(<String, Object?>{
                  'category': category,
                  'name': name,
                  'severity': severity,
                  'message': message,
                  ...context,
                });
              },
          errorRecorder:
              (error, stackTrace, {required source, required fatal}) {
                errors.add(error);
                expect(source, 'voice-call-presence');
                expect(fatal, isFalse);
              },
        );

        expect(snapshot.peerOnline, isNull);
        expect(snapshot.diagnostics['presenceSource'], 'backend');
        expect(snapshot.diagnostics['presenceError'], contains('backend'));
        expect(events.single['name'], 'call_start_presence_unknown');
        expect(events.single['peerId'], 'bob');
        expect(errors, hasLength(1));
      },
    );

    test('records confirmed and offline presence decisions', () async {
      final events = <String>[];

      final online = await coordinator.fetchVoiceCallPeerPresence(
        'bob',
        mediaMode: CallMediaMode.video,
        normalizeUsername: (value) => value,
        fetchPresence: (_, {required String action}) async {
          expect(action, 'callStart');
          return const VoiceCallPeerPresence(
            online: true,
            diagnostics: <String, Object?>{'presenceSource': 'backend'},
          );
        },
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
        errorRecorder: null,
      );

      final offline = await coordinator.fetchVoiceCallPeerPresence(
        'bob',
        mediaMode: CallMediaMode.video,
        normalizeUsername: (value) => value,
        fetchPresence: (_, {required String action}) async {
          return const VoiceCallPeerPresence(
            online: false,
            diagnostics: <String, Object?>{'presenceSource': 'backend'},
          );
        },
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
        errorRecorder: null,
      );

      expect(online.peerOnline, isTrue);
      expect(offline.peerOnline, isFalse);
      expect(events, <String>[
        'call_start_presence_confirmed',
        'call_start_blocked_offline',
      ]);
    });

    test(
      'replaces stale incoming retry by sending hangup and clearing state',
      () async {
        const current = VoiceCallState(
          phase: VoiceCallPhase.incomingRinging,
          peerId: 'bob',
          callId: 'call-1',
        );
        final sentHangups = <String>[];
        var disposed = false;
        VoiceCallState? nextState;

        expect(coordinator.canReplaceVoiceCallWithRetry(current), isTrue);

        await coordinator.replaceStaleVoiceCallForRetry(
          current,
          currentSession: null,
          runBoundedCleanupStep:
              (_, cleanup, {context = const <String, Object?>{}}) {
                fail('cleanup should not run without matching current session');
              },
          sendHangupFrame:
              ({
                required String peerId,
                required String callId,
                required String reason,
              }) async {
                sentHangups.add('$peerId:$callId:$reason');
              },
          disposeCurrentVoiceCallSession: () async {
            disposed = true;
          },
          setVoiceCallState: (state) {
            nextState = state;
          },
        );

        expect(sentHangups.single, startsWith('bob:call-1:'));
        expect(disposed, isTrue);
        expect(nextState, const VoiceCallState.idle());
      },
    );
  });
}
