/// # serialized_runtime_mutations.dart
///
/// [SerializedRuntimeMutations] is a lightweight serial-execution queue that
/// chains futures so mutations (database writes, signaling commands) execute
/// one at a time, preventing race conditions without explicit locks.
///
/// **Key types:** [SerializedRuntimeMutations]
///
/// **Depends on:** runtime state management
library;

class SerializedRuntimeMutations {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final next = _tail.catchError((_) {}).then((_) => action());
    _tail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }
}
