import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bootstrap/app_bootstrap.dart';
import 'config/app_environment.dart';
import 'providers/app_providers.dart';
import 'screens/rain_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final environment = AppEnvironment.fromEnvironment();
  final bootstrap = await AppBootstrapper().bootstrap(environment);

  runApp(
    ProviderScope(
      overrides: <Override>[
        appBootstrapProvider.overrideWithValue(bootstrap),
      ],
      child: const RainApp(),
    ),
  );
}
