import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/app_exit_coordinator.dart';

void main() {
  test('app exit coordinator runs registered handlers once', () async {
    final coordinator = AppExitCoordinator(timeout: const Duration(seconds: 1));
    var calls = 0;
    final token = coordinator.register((AppExitReason reason) async {
      calls += 1;
      expect(reason, AppExitReason.windowClose);
    });

    final first = coordinator.shutdown(AppExitReason.windowClose);
    final second = coordinator.shutdown(AppExitReason.windowClose);

    await Future.wait(<Future<void>>[first, second]);
    expect(calls, 1);
    token.unregister();
  });

  test('unregistered handlers are not called during shutdown', () async {
    final coordinator = AppExitCoordinator(timeout: const Duration(seconds: 1));
    var calls = 0;
    final token = coordinator.register((_) async => calls += 1);
    token.unregister();

    await coordinator.shutdown(AppExitReason.windowClose);

    expect(calls, 0);
  });

  test('app exit coordinator waits for every active handler', () async {
    final coordinator = AppExitCoordinator(timeout: const Duration(seconds: 1));
    final calls = <String>[];

    coordinator.register((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      calls.add('first');
    });
    coordinator.register((_) async {
      calls.add('second');
    });

    await coordinator.shutdown(AppExitReason.windowClose);

    expect(calls, containsAll(<String>['first', 'second']));
  });

  test('app exit coordinator is bounded by timeout', () async {
    final coordinator = AppExitCoordinator(
      timeout: const Duration(milliseconds: 20),
    );
    coordinator.register((_) => Completer<void>().future);

    final stopwatch = Stopwatch()..start();
    await coordinator.shutdown(AppExitReason.windowClose);
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('handler errors do not block shutdown', () async {
    final coordinator = AppExitCoordinator(timeout: const Duration(seconds: 1));
    var secondHandlerRan = false;
    coordinator.register((_) async {
      throw StateError('cleanup failed');
    });
    coordinator.register((_) async {
      secondHandlerRan = true;
    });

    await coordinator.shutdown(AppExitReason.windowClose);

    expect(secondHandlerRan, isTrue);
  });
}
