/// # runtime_environment.dart
///
/// Conditional export barrel for [currentProcessEnvironment]. Exports the IO
/// implementation (reads config files + platform environment) on dart:io
/// platforms, or the stub (returns empty map) on web/other.
///
/// **Key types:** (none — conditional export)
///
/// **Depends on:** runtime_environment_io.dart, runtime_environment_stub.dart

export 'runtime_environment_stub.dart'
    if (dart.library.io) 'runtime_environment_io.dart';
