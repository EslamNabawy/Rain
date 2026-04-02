import 'package:flutter_test/flutter_test.dart';
import 'package:rain/config/app_environment.dart';

void main() {
  test('supabase is the default backend when no define overrides it', () {
    final environment = AppEnvironment.fromEnvironment();

    expect(environment.backend, RainBackend.supabase);
  });
}
