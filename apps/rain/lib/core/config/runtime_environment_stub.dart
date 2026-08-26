/// # runtime_environment_stub.dart
///
/// Stub implementation of [currentProcessEnvironment] for non-IO platforms
/// (web). Returns an empty map since file-based config is unavailable.
///
/// **Key types:** (none — top-level function)
///
/// **Depends on:** (none)
library;

Map<String, String> currentProcessEnvironment() => const <String, String>{};
