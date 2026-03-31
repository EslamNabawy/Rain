import 'package:flutter_test/flutter_test.dart';
import 'package:rain/config/app_environment.dart';

void main() {
  test('firebase is the default backend and points to the Rain RTDB instance', () {
    final environment = AppEnvironment.fromEnvironment();

    expect(environment.backend, RainBackend.firebase);
    expect(
      environment.firebaseDatabaseUrl,
      'https://rain-8fb4b-default-rtdb.firebaseio.com',
    );
  });
}
