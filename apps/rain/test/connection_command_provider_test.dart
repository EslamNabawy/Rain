import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/connection_command/connection_command_models.dart';
import 'package:rain/application/connection_command/connection_command_orchestrator.dart';
import 'package:rain/application/connection_command/fake_connection_transport.dart';
import 'package:rain/application/state/app_state.dart';
import 'package:rain/application/state/app_providers.dart';

void main() {
  test(
    'connection command provider is absent while runtime is unavailable',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(connectionCommandOrchestratorProvider), isNull);
    },
  );

  test(
    'ConnectionsController.connect delegates to the command orchestrator',
    () async {
      final transport = FakeConnectionTransport(
        scriptedResults: <ConnectionLayer, List<ConnectionLayerResult>>{
          ConnectionLayer.preflight: <ConnectionLayerResult>[
            const ConnectionLayerResult.succeeded(),
          ],
          ConnectionLayer.webRtcDirect: <ConnectionLayerResult>[
            const ConnectionLayerResult.succeeded(),
          ],
        },
      );
      final orchestrator = ConnectionCommandOrchestrator(
        transport: transport,
        runIdFactory: () => 'run-1',
      );
      final container = ProviderContainer(
        overrides: <Override>[
          connectionCommandOrchestratorProvider.overrideWithValue(orchestrator),
        ],
      );
      addTearDown(() {
        orchestrator.dispose();
        container.dispose();
      });

      await container.read(connectionsProvider.notifier).connect('bob');
      await transport.waitForIdle();

      expect(transport.calls.map((call) => call.layer), <ConnectionLayer>[
        ConnectionLayer.preflight,
        ConnectionLayer.webRtcDirect,
      ]);
    },
  );

  test(
    'ConnectionsController.cancel delegates to the command orchestrator',
    () async {
      final transport = FakeConnectionTransport.hanging();
      final orchestrator = ConnectionCommandOrchestrator(
        transport: transport,
        runIdFactory: () => 'run-1',
      );
      final container = ProviderContainer(
        overrides: <Override>[
          connectionCommandOrchestratorProvider.overrideWithValue(orchestrator),
        ],
      );
      addTearDown(() {
        orchestrator.dispose();
        container.dispose();
      });

      final controller = container.read(connectionsProvider.notifier);
      await controller.connect('bob');
      await Future<void>.delayed(Duration.zero);

      await controller.cancel('bob');

      expect(transport.cancelCalls, <ConnectionLayer>[
        ConnectionLayer.preflight,
      ]);
      expect(
        container.read(connectionsProvider).peer('bob').manualIntent,
        ManualConnectionIntent.idle,
      );
      expect(
        container.read(connectionsProvider).peer('bob').actionBusy,
        isFalse,
      );
    },
  );

  test(
    'fallback request provider resumes command flow after a choice',
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
            const ConnectionLayerResult.succeeded(),
          ],
        },
      );
      final orchestrator = ConnectionCommandOrchestrator(
        transport: transport,
        runIdFactory: () => 'run-1',
      );
      final container = ProviderContainer(
        overrides: <Override>[
          connectionCommandOrchestratorProvider.overrideWithValue(orchestrator),
        ],
      );
      final requests = <ConnectionFallbackRequest>[];
      final fallbackSubscription = container
          .listen<AsyncValue<ConnectionFallbackRequest>>(
            connectionFallbackRequestProvider('bob'),
            (_, next) {
              final request = next.valueOrNull;
              if (request != null) {
                requests.add(request);
              }
            },
          );
      addTearDown(() {
        fallbackSubscription.close();
        orchestrator.dispose();
        container.dispose();
      });

      await container
          .read(connectionsProvider.notifier)
          .connect(
            'bob',
            policy: const ConnectionPolicy(
              mode: ConnectionMode.webRtcDirectOnly,
            ),
          );
      await transport.waitForIdle();

      expect(requests, hasLength(1));
      expect(
        requests.single.failureCode,
        ConnectionFailureCode.directPathBlocked,
      );

      await container
          .read(connectionsProvider.notifier)
          .resolveFallback('bob', ConnectionFallbackChoice.tryRelay);
      await transport.waitForIdle();

      expect(transport.calls.map((call) => call.layer), <ConnectionLayer>[
        ConnectionLayer.preflight,
        ConnectionLayer.webRtcDirect,
        ConnectionLayer.preflight,
        ConnectionLayer.webRtcPrimaryRelay,
      ]);
    },
  );
}
