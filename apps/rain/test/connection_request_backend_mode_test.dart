import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/core/config/app_environment.dart';

void main() {
  test('connection request backend defaults to rtdbOnly', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{},
    );

    expect(
      environment.connectionRequestBackendMode,
      ConnectionRequestBackendMode.rtdbOnly,
    );
  });

  test('connection request backend parser accepts cloudFunctions', () {
    expect(
      ConnectionRequestBackendMode.parse('cloudFunctions'),
      ConnectionRequestBackendMode.cloudFunctions,
    );
  });

  test('connection request backend parser accepts blank as rtdbOnly', () {
    expect(
      ConnectionRequestBackendMode.parse(''),
      ConnectionRequestBackendMode.rtdbOnly,
    );
  });

  test('connection request backend parser rejects unknown mode', () {
    expect(
      () => ConnectionRequestBackendMode.parse('firestore'),
      throwsFormatException,
    );
  });

  test('runtime environment can select cloudFunctions mode', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{
        'CONNECTION_REQUEST_BACKEND_MODE': 'cloudFunctions',
      },
    );

    expect(
      environment.connectionRequestBackendMode,
      ConnectionRequestBackendMode.cloudFunctions,
    );
  });
}
