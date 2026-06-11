/// # connection_request_backend_mode.dart — protocol_brain package
///
/// Simple enum that selects the connection request backend implementation: cloudFunctions (uses Firebase Callable Functions) or rtdbOnly (direct Realtime Database writes). Controls which adapter variant is used at runtime.
///
/// **Key types:** ConnectionRequestBackendMode
///
/// **Package:** protocol_brain
///
/// **Depends on:** None (standalone enum)
enum ConnectionRequestBackendMode {
  cloudFunctions,
  rtdbOnly;

  static ConnectionRequestBackendMode parse(String value) {
    switch (value.trim()) {
      case 'cloudFunctions':
        return ConnectionRequestBackendMode.cloudFunctions;
      case 'rtdbOnly':
      case '':
        return ConnectionRequestBackendMode.rtdbOnly;
    }
    throw FormatException(
      'Unsupported connection request backend mode: $value',
    );
  }
}
