import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/application/state/runtime_providers.dart';

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

  test('runtime adapter selection chooses rtdb adapter in default mode', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{},
    );
    final cloudFunctionsAdapter = FakeConnectionRequestAdapter(
      currentUsername: 'alice',
    );
    final rtdbAdapter = FakeConnectionRequestAdapter(currentUsername: 'alice');

    final selected = selectConnectionRequestAdapterForEnvironment(
      environment: environment,
      cloudFunctionsAdapter: cloudFunctionsAdapter,
      rtdbOnlyAdapter: rtdbAdapter,
    );

    expect(selected, same(rtdbAdapter));
  });

  test('runtime adapter selection keeps cloudFunctions mode explicit', () {
    final environment = AppEnvironment.fromEnvironment(
      runtimeEnvironment: const <String, String>{
        'CONNECTION_REQUEST_BACKEND_MODE': 'cloudFunctions',
      },
    );
    final cloudFunctionsAdapter = FakeConnectionRequestAdapter(
      currentUsername: 'alice',
    );
    final rtdbAdapter = FakeConnectionRequestAdapter(currentUsername: 'alice');

    final selected = selectConnectionRequestAdapterForEnvironment(
      environment: environment,
      cloudFunctionsAdapter: cloudFunctionsAdapter,
      rtdbOnlyAdapter: rtdbAdapter,
    );

    expect(selected, same(cloudFunctionsAdapter));
  });
}
