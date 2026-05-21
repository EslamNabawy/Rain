import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/connection_command/connection_command_models.dart';
import 'package:rain/application/connection_command/connection_command_orchestrator.dart';
import 'package:rain/application/connection_command/fake_connection_transport.dart';

void main() {
  group('ConnectionCommandOrchestrator', () {
    test('connect emits an initial preflight timeline', () async {
      final orchestrator = ConnectionCommandOrchestrator(
        now: () => 100,
        runIdFactory: () => 'run-1',
      );
      final timelines = <ConnectionTimeline>[];
      final subscription = orchestrator
          .timelineStream('bob')
          .listen(timelines.add);
      addTearDown(subscription.cancel);
      addTearDown(orchestrator.dispose);

      await orchestrator.connect('bob');

      expect(timelines, hasLength(2));
      expect(timelines.first.peerId, 'bob');
      expect(timelines.first.attemptId, 'run-1');
      expect(timelines.first.steps.single.state, ConnectionStepState.pending);
      expect(timelines.last.steps.single.state, ConnectionStepState.running);
      expect(timelines.last.activeLayer, ConnectionLayer.preflight);
      expect(timelines.last.canCancel, isTrue);
      expect(timelines.last, isNot(same(timelines.first)));
    });

    test(
      'connect while peer is already connecting returns the existing run',
      () async {
        var nextRunId = 0;
        final orchestrator = ConnectionCommandOrchestrator(
          now: () => 100,
          runIdFactory: () => 'run-${nextRunId += 1}',
        );
        addTearDown(orchestrator.dispose);

        await orchestrator.connect('bob');
        await orchestrator.connect('bob');

        final timeline = orchestrator.currentTimeline('bob');

        expect(timeline, isNotNull);
        expect(timeline!.attemptId, 'run-1');
        expect(timeline.steps, hasLength(1));
      },
    );

    test('remembered policy is in-memory and peer specific', () {
      final orchestrator = ConnectionCommandOrchestrator();
      addTearDown(orchestrator.dispose);
      const policy = ConnectionPolicy(
        mode: ConnectionMode.webRtcRelayOnly,
        rememberForSession: true,
      );

      orchestrator.rememberPolicyForSession('bob', policy);

      expect(orchestrator.policyForPeer('bob'), policy);
      expect(orchestrator.policyForPeer('alice').mode, ConnectionMode.auto);

      orchestrator.clearSessionPolicy('bob');

      expect(orchestrator.policyForPeer('bob').mode, ConnectionMode.auto);
    });

    test('dispose clears active runs and remembered policies', () async {
      final orchestrator = ConnectionCommandOrchestrator(
        runIdFactory: () => 'run-1',
      );
      const policy = ConnectionPolicy(
        mode: ConnectionMode.irohFallback,
        rememberForSession: true,
      );

      orchestrator.rememberPolicyForSession('bob', policy);
      await orchestrator.connect('bob');
      orchestrator.dispose();

      expect(orchestrator.currentTimeline('bob'), isNull);
      expect(orchestrator.policyForPeer('bob').mode, ConnectionMode.auto);
    });

    test('builds exact layer sequence for each policy mode', () {
      expect(
        ConnectionCommandOrchestrator.layersForPolicy(
          const ConnectionPolicy.defaults(),
        ),
        <ConnectionLayer>[
          ConnectionLayer.preflight,
          ConnectionLayer.webRtcDirect,
          ConnectionLayer.webRtcPrimaryRelay,
          ConnectionLayer.webRtcBackupRelay,
          ConnectionLayer.webRtcFullRestart,
          ConnectionLayer.iroh,
        ],
      );
      expect(
        ConnectionCommandOrchestrator.layersForPolicy(
          const ConnectionPolicy(mode: ConnectionMode.webRtcAuto),
        ),
        <ConnectionLayer>[
          ConnectionLayer.preflight,
          ConnectionLayer.webRtcDirect,
          ConnectionLayer.webRtcPrimaryRelay,
          ConnectionLayer.webRtcBackupRelay,
          ConnectionLayer.webRtcFullRestart,
        ],
      );
      expect(
        ConnectionCommandOrchestrator.layersForPolicy(
          const ConnectionPolicy(mode: ConnectionMode.webRtcDirectOnly),
        ),
        <ConnectionLayer>[
          ConnectionLayer.preflight,
          ConnectionLayer.webRtcDirect,
        ],
      );
      expect(
        ConnectionCommandOrchestrator.layersForPolicy(
          const ConnectionPolicy(mode: ConnectionMode.webRtcRelayOnly),
        ),
        <ConnectionLayer>[
          ConnectionLayer.preflight,
          ConnectionLayer.webRtcPrimaryRelay,
          ConnectionLayer.webRtcBackupRelay,
          ConnectionLayer.webRtcFullRestart,
        ],
      );
      expect(
        ConnectionCommandOrchestrator.layersForPolicy(
          const ConnectionPolicy(mode: ConnectionMode.irohFallback),
        ),
        <ConnectionLayer>[ConnectionLayer.preflight, ConnectionLayer.iroh],
      );
    });

    test('auto advances through failed layers until iroh succeeds', () async {
      final transport = FakeConnectionTransport(
        scriptedResults: <ConnectionLayer, List<ConnectionLayerResult>>{
          ConnectionLayer.preflight: <ConnectionLayerResult>[
            const ConnectionLayerResult.succeeded(),
          ],
          ConnectionLayer.webRtcDirect: <ConnectionLayerResult>[
            const ConnectionLayerResult.failed(
              ConnectionFailureCode.directPathBlocked,
            ),
          ],
          ConnectionLayer.webRtcPrimaryRelay: <ConnectionLayerResult>[
            const ConnectionLayerResult.failed(
              ConnectionFailureCode.turnProviderTimedOut,
            ),
          ],
          ConnectionLayer.webRtcBackupRelay: <ConnectionLayerResult>[
            const ConnectionLayerResult.failed(
              ConnectionFailureCode.turnProviderTimedOut,
            ),
          ],
          ConnectionLayer.webRtcFullRestart: <ConnectionLayerResult>[
            const ConnectionLayerResult.failed(
              ConnectionFailureCode.dataChannelTimeout,
            ),
            const ConnectionLayerResult.failed(
              ConnectionFailureCode.dataChannelTimeout,
            ),
          ],
          ConnectionLayer.iroh: <ConnectionLayerResult>[
            const ConnectionLayerResult.succeeded(),
          ],
        },
      );
      final orchestrator = ConnectionCommandOrchestrator(
        transport: transport,
        runIdFactory: () => 'run-1',
        timeouts: const ConnectionCommandTimeoutConfig(
          retryBaseDelay: Duration.zero,
          retryMaxJitter: Duration.zero,
        ),
      );
      addTearDown(orchestrator.dispose);

      await orchestrator.connect('bob');
      await transport.waitForIdle();

      expect(transport.calls.map((call) => call.layer), <ConnectionLayer>[
        ConnectionLayer.preflight,
        ConnectionLayer.webRtcDirect,
        ConnectionLayer.webRtcPrimaryRelay,
        ConnectionLayer.webRtcBackupRelay,
        ConnectionLayer.webRtcFullRestart,
        ConnectionLayer.webRtcFullRestart,
        ConnectionLayer.iroh,
      ]);
      expect(orchestrator.currentTimeline('bob')!.canCancel, isFalse);
      expect(
        orchestrator.currentTimeline('bob')!.steps.last.state,
        ConnectionStepState.succeeded,
      );
    });

    test(
      'global budget cancels the active layer and fails the timeline',
      () async {
        final transport = FakeConnectionTransport.hanging();
        final orchestrator = ConnectionCommandOrchestrator(
          transport: transport,
          runIdFactory: () => 'run-1',
          timeouts: const ConnectionCommandTimeoutConfig(
            globalBudget: Duration(milliseconds: 5),
          ),
        );
        addTearDown(orchestrator.dispose);

        await orchestrator.connect('bob');
        await Future<void>.delayed(const Duration(milliseconds: 30));

        final timeline = orchestrator.currentTimeline('bob')!;
        expect(timeline.globalBudgetExceeded, isTrue);
        expect(timeline.canCancel, isFalse);
        expect(timeline.steps.last.state, ConnectionStepState.failed);
        expect(
          timeline.steps.last.failureCode,
          ConnectionFailureCode.globalBudgetExceeded,
        );
        expect(transport.cancelCalls, <ConnectionLayer>[
          ConnectionLayer.preflight,
        ]);
      },
    );

    test('retry delay stays inside the configured jitter range', () {
      final delays = List<Duration>.generate(
        40,
        (index) => ConnectionCommandOrchestrator.retryDelay(Random(index)),
      );

      for (final delay in delays) {
        expect(delay, greaterThanOrEqualTo(const Duration(milliseconds: 1200)));
        expect(delay, lessThanOrEqualTo(const Duration(milliseconds: 1800)));
      }
    });

    test(
      'retryable failure retries the same layer once before advancing',
      () async {
        final transport = FakeConnectionTransport(
          scriptedResults: <ConnectionLayer, List<ConnectionLayerResult>>{
            ConnectionLayer.preflight: <ConnectionLayerResult>[
              const ConnectionLayerResult.succeeded(),
            ],
            ConnectionLayer.webRtcDirect: <ConnectionLayerResult>[
              const ConnectionLayerResult.failed(
                ConnectionFailureCode.dataChannelTimeout,
              ),
              const ConnectionLayerResult.failed(
                ConnectionFailureCode.directPathBlocked,
              ),
            ],
            ConnectionLayer.webRtcPrimaryRelay: <ConnectionLayerResult>[
              const ConnectionLayerResult.succeeded(),
            ],
          },
        );
        final orchestrator = ConnectionCommandOrchestrator(
          transport: transport,
          runIdFactory: () => 'run-1',
          timeouts: const ConnectionCommandTimeoutConfig(
            retryBaseDelay: Duration.zero,
            retryMaxJitter: Duration.zero,
          ),
        );
        addTearDown(orchestrator.dispose);

        await orchestrator.connect('bob');
        await transport.waitForIdle();

        expect(transport.calls.map((call) => call.layer), <ConnectionLayer>[
          ConnectionLayer.preflight,
          ConnectionLayer.webRtcDirect,
          ConnectionLayer.webRtcDirect,
          ConnectionLayer.webRtcPrimaryRelay,
        ]);
        final directSteps = orchestrator
            .currentTimeline('bob')!
            .fullHistory
            .where((step) => step.layer == ConnectionLayer.webRtcDirect)
            .toList();
        expect(directSteps.last.retryCount, 1);
      },
    );

    test(
      'non-retryable failure advances without retrying the same layer',
      () async {
        final transport = FakeConnectionTransport(
          scriptedResults: <ConnectionLayer, List<ConnectionLayerResult>>{
            ConnectionLayer.preflight: <ConnectionLayerResult>[
              const ConnectionLayerResult.succeeded(),
            ],
            ConnectionLayer.webRtcDirect: <ConnectionLayerResult>[
              const ConnectionLayerResult.failed(
                ConnectionFailureCode.directPathBlocked,
              ),
            ],
            ConnectionLayer.webRtcPrimaryRelay: <ConnectionLayerResult>[
              const ConnectionLayerResult.failed(
                ConnectionFailureCode.turnCredentialsUnavailable,
              ),
            ],
            ConnectionLayer.webRtcBackupRelay: <ConnectionLayerResult>[
              const ConnectionLayerResult.succeeded(),
            ],
          },
        );
        final orchestrator = ConnectionCommandOrchestrator(
          transport: transport,
          runIdFactory: () => 'run-1',
          timeouts: const ConnectionCommandTimeoutConfig(
            retryBaseDelay: Duration.zero,
            retryMaxJitter: Duration.zero,
          ),
        );
        addTearDown(orchestrator.dispose);

        await orchestrator.connect('bob');
        await transport.waitForIdle();

        expect(transport.calls.map((call) => call.layer), <ConnectionLayer>[
          ConnectionLayer.preflight,
          ConnectionLayer.webRtcDirect,
          ConnectionLayer.webRtcPrimaryRelay,
          ConnectionLayer.webRtcBackupRelay,
        ]);
        expect(
          transport.calls.where(
            (call) => call.layer == ConnectionLayer.webRtcPrimaryRelay,
          ),
          hasLength(1),
        );
      },
    );

    test('manual direct failure emits one fallback request', () async {
      final transport = FakeConnectionTransport(
        scriptedResults: <ConnectionLayer, List<ConnectionLayerResult>>{
          ConnectionLayer.preflight: <ConnectionLayerResult>[
            const ConnectionLayerResult.succeeded(),
          ],
          ConnectionLayer.webRtcDirect: <ConnectionLayerResult>[
            const ConnectionLayerResult.failed(
              ConnectionFailureCode.directPathBlocked,
            ),
          ],
        },
      );
      final orchestrator = ConnectionCommandOrchestrator(
        transport: transport,
        runIdFactory: () => 'run-1',
      );
      final requests = <ConnectionFallbackRequest>[];
      final subscription = orchestrator.fallbackRequests.listen(requests.add);
      addTearDown(subscription.cancel);
      addTearDown(orchestrator.dispose);

      await orchestrator.connect(
        'bob',
        policy: const ConnectionPolicy(mode: ConnectionMode.webRtcDirectOnly),
      );
      await transport.waitForIdle();

      expect(requests, hasLength(1));
      expect(requests.single.peerId, 'bob');
      expect(requests.single.failedLayer, ConnectionLayer.webRtcDirect);
      expect(
        requests.single.failureCode,
        ConnectionFailureCode.directPathBlocked,
      );
      expect(requests.single.choices, <ConnectionFallbackChoice>[
        ConnectionFallbackChoice.tryAuto,
        ConnectionFallbackChoice.tryRelay,
        ConnectionFallbackChoice.tryIroh,
        ConnectionFallbackChoice.cancel,
      ]);
      expect(
        orchestrator.currentTimeline('bob')!.fallbackPromptAlreadyShown,
        isTrue,
      );
    });

    test(
      'fallback choice can be remembered for the session and never loops',
      () async {
        final transport = FakeConnectionTransport(
          scriptedResults: <ConnectionLayer, List<ConnectionLayerResult>>{
            ConnectionLayer.preflight: <ConnectionLayerResult>[
              const ConnectionLayerResult.succeeded(),
              const ConnectionLayerResult.succeeded(),
            ],
            ConnectionLayer.webRtcDirect: <ConnectionLayerResult>[
              const ConnectionLayerResult.failed(
                ConnectionFailureCode.directPathBlocked,
              ),
            ],
            ConnectionLayer.webRtcPrimaryRelay: <ConnectionLayerResult>[
              const ConnectionLayerResult.failed(
                ConnectionFailureCode.turnProviderTimedOut,
              ),
            ],
            ConnectionLayer.webRtcBackupRelay: <ConnectionLayerResult>[
              const ConnectionLayerResult.failed(
                ConnectionFailureCode.turnProviderTimedOut,
              ),
            ],
            ConnectionLayer.webRtcFullRestart: <ConnectionLayerResult>[
              const ConnectionLayerResult.failed(
                ConnectionFailureCode.turnCredentialsUnavailable,
              ),
            ],
          },
        );
        final orchestrator = ConnectionCommandOrchestrator(
          transport: transport,
          runIdFactory: () => 'run-1',
        );
        final requests = <ConnectionFallbackRequest>[];
        final subscription = orchestrator.fallbackRequests.listen(requests.add);
        addTearDown(subscription.cancel);
        addTearDown(orchestrator.dispose);

        await orchestrator.connect(
          'bob',
          policy: const ConnectionPolicy(mode: ConnectionMode.webRtcDirectOnly),
        );
        await transport.waitForIdle();

        await orchestrator.resolveFallback(
          peerId: 'bob',
          choice: ConnectionFallbackChoice.tryRelay,
          rememberForSession: true,
        );
        await transport.waitForIdle();

        expect(requests, hasLength(1));
        expect(
          orchestrator.policyForPeer('bob').mode,
          ConnectionMode.webRtcRelayOnly,
        );
        expect(orchestrator.currentTimeline('bob')!.canRetry, isTrue);
        expect(
          orchestrator.currentTimeline('bob')!.fallbackPromptAlreadyShown,
          isTrue,
        );
      },
    );
  });
}
