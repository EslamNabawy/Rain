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
          backendStartupGrace: Duration.zero,
        );

        final status = await service.watch().firstWhere(
          (NetworkStatusState item) => item.kind != NetworkStatusKind.checking,
        );

        expect(status.kind, NetworkStatusKind.limited);
        expect(status.blocksNetworkActions, isFalse);
        expect(status.isOnline, isTrue);
        expect(status.actionErrorMessage, contains('backend'));
      },
    );

    test('optimistically stays online during backend startup grace', () async {
      final service = NetworkStatusService(
        connectivityProbe: _FakeConnectivityProbe(
          initial: const <ConnectivityResult>[ConnectivityResult.mobile],
        ),
        backendProbe: _FakeBackendProbe(initial: false),
        backendStartupGrace: const Duration(milliseconds: 30),
      );
      final statuses = <NetworkStatusKind>[];
      final subscription = service.watch().listen(
        (NetworkStatusState status) => statuses.add(status.kind),
      );

      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(statuses, isNot(contains(NetworkStatusKind.limited)));
      expect(statuses.last, NetworkStatusKind.online);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      await subscription.cancel();

      expect(statuses, contains(NetworkStatusKind.limited));
    });

    test('emits online again when backend reconnects', () async {
      final backend = _FakeBackendProbe(initial: false);
      final service = NetworkStatusService(
        connectivityProbe: _FakeConnectivityProbe(
          initial: const <ConnectivityResult>[ConnectivityResult.wifi],
        ),
        backendProbe: backend,
        backendStartupGrace: Duration.zero,
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

    test('emits a new online state when connectivity path changes', () async {
      final connectivity = _FakeConnectivityProbe(
        initial: const <ConnectivityResult>[ConnectivityResult.wifi],
      );
      final service = NetworkStatusService(
        connectivityProbe: connectivity,
        backendProbe: _FakeBackendProbe(initial: true),
      );
      final statuses = <NetworkStatusState>[];
      final subscription = service.watch().listen(statuses.add);

      await pumpEventQueue();
      connectivity.emit(const <ConnectivityResult>[ConnectivityResult.mobile]);
      await pumpEventQueue();
      await subscription.cancel();

      final onlineStates = statuses
          .where((NetworkStatusState status) {
            return status.kind == NetworkStatusKind.online;
          })
          .toList(growable: false);
      expect(onlineStates.map((NetworkStatusState status) => status.pathKey), [
        contains('wifi'),
        contains('mobile'),
      ]);
    });

    test(
      'marks limited immediately after a confirmed backend disconnect',
      () async {
        final backend = _FakeBackendProbe(initial: true);
        final service = NetworkStatusService(
          connectivityProbe: _FakeConnectivityProbe(
            initial: const <ConnectivityResult>[ConnectivityResult.wifi],
          ),
          backendProbe: backend,
          backendStartupGrace: const Duration(seconds: 30),
        );
        final statuses = <NetworkStatusKind>[];
        final subscription = service.watch().listen(
          (NetworkStatusState status) => statuses.add(status.kind),
        );

        await pumpEventQueue();
        backend.emit(false);
        await pumpEventQueue();
        await subscription.cancel();

        expect(statuses, contains(NetworkStatusKind.online));
        expect(statuses.last, NetworkStatusKind.limited);
      },
    );

    test('backend disconnect never blocks network actions', () async {
      final service = NetworkStatusService(
        connectivityProbe: _FakeConnectivityProbe(
          initial: const <ConnectivityResult>[ConnectivityResult.wifi],
        ),
        backendProbe: _FakeBackendProbe(initial: false),
        backendStartupGrace: Duration.zero,
      );

      final status = await service.watch().firstWhere(
        (NetworkStatusState item) => item.kind == NetworkStatusKind.limited,
      );

      expect(status.blocksNetworkActions, isFalse);
      expect(status.isOnline, isTrue);
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

  void emit(List<ConnectivityResult> connectivity) {
    _controller.add(connectivity);
  }
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
