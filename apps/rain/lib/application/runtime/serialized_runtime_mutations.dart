class SerializedRuntimeMutations {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final next = _tail.catchError((_) {}).then((_) => action());
    _tail = next.then<void>((_) {}, onError: (_, _) {});
    return next;
  }
}
