/// # serialized_runtime_mutations_test.dart
///
/// Tests SerializedRuntimeMutations, ensuring that runtime mutations execute one at a time in submission order and that a failed mutation does not block subsequent mutations.
///
/// **Key types:** SerializedRuntimeMutations
///
/// **Depends on:** package:rain/application/runtime/serialized_runtime_mutations.dart
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/runtime/serialized_runtime_mutations.dart';

void main() {
  test(
    'serialized runtime mutations run one at a time in submission order',
    () async {
      final mutations = SerializedRuntimeMutations();
      final firstGate = Completer<void>();
      final events = <String>[];

      final first = mutations.run(() async {
        events.add('first-start');
        await firstGate.future;
        events.add('first-end');
        return 1;
      });

      final second = mutations.run(() async {
        events.add('second-start');
        return 2;
      });

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['first-start']);

      firstGate.complete();
      expect(await first, 1);
      expect(await second, 2);
      expect(events, <String>['first-start', 'first-end', 'second-start']);
    },
  );

  test(
    'serialized runtime mutations continue after a failed mutation',
    () async {
      final mutations = SerializedRuntimeMutations();
      final first = mutations.run<void>(() async {
        throw StateError('boom');
      });
      final second = mutations.run(() async => 2);

      await expectLater(first, throwsStateError);
      expect(await second, 2);
    },
  );
}
