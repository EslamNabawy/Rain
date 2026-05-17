import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';

void main() {
  group('NetworkStatusService', () {
    test('maps no network interface to offline', () async {
      final service = NetworkStatusService(
        connectivityProbe: _FakeConnectivityProbe(
          initial: const <ConnectivityResult>[ConnectivityResult.none],
        ),
        backendProbe: _FakeBackendProbe(initial: true),
      );

      final status = await service.watch().firstWhere(
        (NetworkStatusState item) => item.kind != NetworkStatusKind.checking,
      );

      expect(status.kind, NetworkStatusKind.offline);
      expect(status.blocksNetworkActions, isTrue);
    });

    test(
      'maps reachable network with disconnected backend to limited',
      () async {
        final service = NetworkStatusService(
          connectivityProbe: _FakeConnectivityProbe(
            initial: const <ConnectivityResult>[ConnectivityResult.wifi],
          ),
          backendProbe: _FakeBackendProbe(initial: false),
        );

        final status = await service.watch().firstWhere(
          (NetworkStatusState item) => item.kind != NetworkStatusKind.checking,
        );

        expect(status.kind, NetworkStatusKind.limited);
        expect(status.actionErrorMessage, contains('backend'));
      },
    );

    test('emits online again when backend reconnects', () async {
      final backend = _FakeBackendProbe(initial: false);
      final service = NetworkStatusService(
        connectivityProbe: _FakeConnectivityProbe(
          initial: const <ConnectivityResult>[ConnectivityResult.wifi],
        ),
        backendProbe: backend,
      );
      final statuses = <NetworkStatusKind>[];
      final subscription = service.watch().listen(
        (NetworkStatusState status) => statuses.add(status.kind),
      );

      await pumpEventQueue();
      backend.emit(true);
      await pumpEventQueue();
      await subscription.cancel();

      expect(statuses, contains(NetworkStatusKind.limited));
      expect(statuses, contains(NetworkStatusKind.online));
    });
  });
}

class _FakeConnectivityProbe implements ConnectivityProbe {
  _FakeConnectivityProbe({required this.initial});

  final List<ConnectivityResult> initial;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => initial;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;
}

class _FakeBackendProbe implements BackendConnectivityProbe {
  _FakeBackendProbe({required this.initial});

  final bool initial;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> checkConnected() async => initial;

  @override
  Stream<bool> watchConnected() => _controller.stream;

  void emit(bool connected) => _controller.add(connected);
}
