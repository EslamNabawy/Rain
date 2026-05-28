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
